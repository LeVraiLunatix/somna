import Foundation

/// One thing the summary is allowed to say.
///
/// **This enum is the anti-hallucination mechanism.** The summary generator
/// cannot write a sentence; it can only choose a case and fill it with values it
/// took from ``SummaryFacts``. There is no code path from the generator to free
/// text, so a summary claiming an event that did not happen would require adding
/// a case for it — a visible, reviewable change rather than a phrasing drift.
///
/// Storing statements rather than rendered prose also keeps the summary
/// translatable: a night recorded while the phone was in French still reads
/// correctly after switching to English, because the words are produced at
/// display time rather than frozen at analysis time.
enum SummaryStatement: Equatable, Sendable, Codable {

    /// The night was quiet overall.
    case overallCalm

    /// The night held a lot of activity.
    case overallActive(eventCount: Int)

    /// Snoring clustered into one clear stretch.
    case snoringConcentrated(start: Date, end: Date, total: TimeInterval)

    /// Snoring happened, but scattered.
    case snoringScattered(total: TimeInterval)

    case coughs(count: Int)

    case speech(total: TimeInterval)

    /// A single loud event worth pointing at.
    case loudEvent(at: Date)

    case calmestStretch(start: Date, end: Date)

    /// The recording was interrupted, so the picture is incomplete.
    case interrupted(gapCount: Int)

    /// The audio was too degraded to conclude anything from.
    case qualityUnusable

    /// Not enough audio to say anything.
    case tooShort

    /// Nothing at all was detected.
    case nothingDetected
}

/// The only material a summary may be built from.
///
/// Assembled once from real events and measured audio, then handed to the
/// generator. The generator has no other input — not the events, not the
/// session — which is what makes the invariant enforceable rather than aspirational.
struct SummaryFacts: Equatable, Sendable {

    let recordedDuration: TimeInterval
    let isAnalysable: Bool
    let quality: RecordingQualityRating
    let coverage: Double
    let gapCount: Int

    let statistics: NightStatistics

    /// Window containing the bulk of the snoring, when there is a clear one.
    let snoringWindow: DateInterval?
    /// The single loudest event of the night, when one stands out.
    let loudestEventDate: Date?

    static func make(
        session: NightSession,
        events: [NightEvent],
        statistics: NightStatistics,
        gapCount: Int
    ) -> SummaryFacts {
        SummaryFacts(
            recordedDuration: session.recordedDuration,
            isAnalysable: session.isAnalysable,
            quality: session.recordingQuality?.rating ?? .good,
            coverage: session.captureCoverage ?? 1,
            gapCount: gapCount,
            statistics: statistics,
            snoringWindow: Self.snoringWindow(in: events),
            loudestEventDate: Self.loudestEvent(in: events)
        )
    }

    /// The span holding the snoring, when it is concentrated rather than spread
    /// across the whole night.
    ///
    /// Returns `nil` when snoring is scattered, because "between 23:10 and 06:40"
    /// is technically true and completely useless.
    private static func snoringWindow(in events: [NightEvent]) -> DateInterval? {
        let snoring = events.filter { $0.effectiveType == .snoring }
        guard let first = snoring.first, let last = snoring.last, snoring.count >= 2 else {
            return nil
        }

        let span = last.endDate.timeIntervalSince(first.startDate)
        let sounded = snoring.reduce(0) { $0 + $1.duration }

        // Concentrated enough to be worth naming: the snoring occupies a real
        // share of the window it spans.
        guard span > 0, sounded / span >= 0.15 else { return nil }
        return DateInterval(start: first.startDate, end: last.endDate)
    }

    private static func loudestEvent(in events: [NightEvent]) -> Date? {
        let candidates = events.filter { $0.effectiveType == .impact || $0.peakLevel >= 0.75 }
        return candidates.max { $0.peakLevel < $1.peakLevel }?.startDate
    }
}
