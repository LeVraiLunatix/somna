import AVFoundation
import Foundation
import OSLog

/// Progress of a morning pass.
struct AnalysisProgress: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case reading
        case classifying
        case extractingClips
        case summarising
        case finished
    }

    let stage: Stage
    /// 0–1.
    let fraction: Double
    let segmentsDone: Int
    let segmentsTotal: Int

    static let starting = AnalysisProgress(
        stage: .reading, fraction: 0, segmentsDone: 0, segmentsTotal: 0
    )
}

protocol NightAnalyzing: Sendable {
    func analyse(
        session: NightSession,
        segments: [AudioSegment],
        settings: UserSettings,
        onProgress: @Sendable (AnalysisProgress) -> Void
    ) async throws -> AnalysisOutcome
}

/// Everything a morning pass produced.
struct AnalysisOutcome: Sendable {
    let events: [NightEvent]
    let statistics: NightStatistics
    let quality: RecordingQuality
    let calmnessScore: Int?
    let summary: [SummaryStatement]
    let sleepWindow: SleepWindowEstimator.Estimate
}

/// Runs the morning pass.
///
/// Ordered so the expensive work is done on as little audio as possible:
/// candidate zones first from the cheap night metrics, then classification only
/// on segments that have any, then clips only for events that survived.
///
/// Every stage degrades rather than fails. One unreadable segment costs that
/// segment; a classifier that will not load costs the classification but keeps
/// the recording. The alternative — an analysis that gives up — throws away a
/// night the user cannot record again.
actor NightAnalysisEngine: NightAnalyzing {

    private let files: any NightFileStoring
    private let classifier: any SoundClassifying
    private let summariser: any SummaryGenerating
    private let clock: any Clocking
    private let calendar: Calendar

    init(
        files: any NightFileStoring,
        classifier: any SoundClassifying,
        summariser: any SummaryGenerating = TemplateSummaryGenerator(),
        clock: any Clocking,
        calendar: Calendar = .current
    ) {
        self.files = files
        self.classifier = classifier
        self.summariser = summariser
        self.clock = clock
        self.calendar = calendar
    }

    func analyse(
        session: NightSession,
        segments: [AudioSegment],
        settings: UserSettings,
        onProgress: @Sendable (AnalysisProgress) -> Void
    ) async throws -> AnalysisOutcome {

        let usable = segments.filter(\.isUsable).sorted { $0.startDate < $1.startDate }
        guard !usable.isEmpty else { throw AnalysisError.noReadableAudio }

        onProgress(AnalysisProgress(
            stage: .reading, fraction: 0, segmentsDone: 0, segmentsTotal: usable.count
        ))

        // 1. Read the night's own metrics and find what is worth looking at.
        let metricsBySegment = readMetrics(for: usable, session: session)
        let noiseFloor = estimateNoiseFloor(from: metricsBySegment.values.flatMap { $0 })

        var refined: [RuleBasedRefiner.Refined] = []
        var zonesBySegment: [UUID: [CandidateZone]] = [:]
        var overallPeak: Float = 0

        // 2. Classify, segment by segment, skipping the silent ones entirely.
        for (index, segment) in usable.enumerated() {
            try Task.checkCancellation()

            let metrics = metricsBySegment[segment.id] ?? []
            overallPeak = max(overallPeak, metrics.map(\.peak).max() ?? 0)

            let segmentOffset = segment.startDate.timeIntervalSince(session.startDate)
            let zones = CandidateSelector.select(
                metrics: metrics,
                noiseFloor: noiseFloor,
                sensitivityOffset: settings.analysisSensitivity.thresholdOffset * 0.1,
                totalDuration: segment.duration
            )
            zonesBySegment[segment.id] = zones

            onProgress(AnalysisProgress(
                stage: .classifying,
                fraction: Double(index) / Double(usable.count) * 0.7,
                segmentsDone: index,
                segmentsTotal: usable.count
            ))

            // The saving that makes a morning pass tolerable: a calm night is
            // mostly silence, and silence needs no classifier.
            guard !zones.isEmpty else { continue }

            let url = files.segmentURL(for: session.id, fileName: segment.fileName)
            let classifications: [SoundClassification]
            do {
                classifications = try await classifier.classify(fileURL: url, offset: segmentOffset)
            } catch {
                Log.analysis.error("Segment \(index, privacy: .public) could not be classified; skipping")
                continue
            }

            for classification in classifications {
                let localStart = classification.start - segmentOffset
                guard let zone = zones.first(where: {
                    $0.overlaps(localStart...(localStart + classification.duration))
                }) else { continue }

                let periodicity = EnvelopePeriodicity.strength(
                    levels: metrics
                        .filter { $0.offset >= zone.start && $0.offset <= zone.end }
                        .map(\.rms),
                    sampleInterval: metricsInterval(metrics)
                )

                refined.append(RuleBasedRefiner.refine(
                    RuleBasedRefiner.Input(
                        classification: classification,
                        zone: zone,
                        periodicity: periodicity
                    )
                ))
            }
        }

        // 3. Turn detections into events, then collapse repetition.
        var events = RuleBasedRefiner.makeEvents(
            from: refined,
            sessionID: session.id,
            sessionStart: session.startDate,
            rejectionThreshold: settings.effectiveRejectionThreshold,
            now: clock.now
        )
        events = EventGrouper.group(events)

        // 4. Clips, only for events that survived.
        onProgress(AnalysisProgress(
            stage: .extractingClips, fraction: 0.75,
            segmentsDone: usable.count, segmentsTotal: usable.count
        ))
        events = attachClips(to: events, session: session, segments: usable, settings: settings)

        // 5. Numbers, verdict, words.
        onProgress(AnalysisProgress(
            stage: .summarising, fraction: 0.9,
            segmentsDone: usable.count, segmentsTotal: usable.count
        ))

        let statistics = StatisticsCalculator.statistics(
            events: events, session: session, calendar: calendar
        )
        let gapCount = events.filter { $0.effectiveType == .sessionGap }.count

        let quality = RecordingQualityAssessor.assess(
            session: session,
            events: events,
            averageNoiseFloor: noiseFloor,
            peakLevel: Double(overallPeak),
            gapCount: gapCount
        )

        var scored = session
        scored.recordingQuality = quality

        let score = CalmnessScoreCalculator.score(
            statistics: statistics, quality: quality, isAnalysable: session.isAnalysable
        )

        let facts = SummaryFacts.make(
            session: scored, events: events, statistics: statistics, gapCount: gapCount
        )

        onProgress(AnalysisProgress(
            stage: .finished, fraction: 1,
            segmentsDone: usable.count, segmentsTotal: usable.count
        ))

        return AnalysisOutcome(
            events: events,
            statistics: statistics,
            quality: quality,
            calmnessScore: score,
            summary: summariser.summarise(facts),
            sleepWindow: SleepWindowEstimator.estimate(events: events, session: session)
        )
    }

    // MARK: - Metrics

    private func readMetrics(
        for segments: [AudioSegment],
        session: NightSession
    ) -> [UUID: [AudioMetrics]] {
        var result: [UUID: [AudioMetrics]] = [:]
        let directory = files.segmentsDirectory(for: session.id)

        for segment in segments {
            let name = segment.fileName
                .replacingOccurrences(of: ".\(AudioConstants.segmentExtension)", with: "")
            let url = directory.appending(path: "\(name).features.jsonl")
            result[segment.id] = (try? MetricsWriter.read(from: url)) ?? []
        }
        return result
    }

    /// The room's own floor, taken as a low percentile rather than a mean.
    ///
    /// A mean would be dragged upward by the very events the floor is meant to
    /// make detectable, so a noisy night would raise its own threshold and hide
    /// what happened in it.
    private func estimateNoiseFloor(from metrics: [AudioMetrics]) -> Double {
        guard !metrics.isEmpty else { return 0 }
        let sorted = metrics.map { Double($0.rms) }.sorted()
        return sorted[max(0, Int(Double(sorted.count) * 0.2) - 1)]
    }

    private func metricsInterval(_ metrics: [AudioMetrics]) -> TimeInterval {
        guard metrics.count >= 2 else { return 0.1 }
        return max(0.01, metrics[1].offset - metrics[0].offset)
    }

    // MARK: - Clips

    private func attachClips(
        to events: [NightEvent],
        session: NightSession,
        segments: [AudioSegment],
        settings: UserSettings
    ) -> [NightEvent] {
        let extractor = ClipExtractor(bitRate: settings.audioBitRate)
        let clipsDirectory = files.clipsDirectory(for: session.id)

        return events.map { event in
            guard let segment = segments.first(where: {
                event.startDate >= $0.startDate && event.startDate <= $0.endDate
            }) else { return event }

            let localStart = event.startDate.timeIntervalSince(segment.startDate)
            let localEnd = min(localStart + event.duration, segment.duration)

            guard let clip = extractor.extract(
                from: files.segmentURL(for: session.id, fileName: segment.fileName),
                range: localStart...max(localStart, localEnd),
                eventID: event.id,
                destinationDirectory: clipsDirectory
            ) else { return event }

            var updated = event
            updated.clipFileName = clip.fileName
            updated.waveformSamples = clip.waveform
            updated.peakLevel = max(event.peakLevel, Double(clip.peak))
            return updated
        }
    }
}
