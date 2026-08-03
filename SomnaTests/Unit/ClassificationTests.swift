import Foundation
import Testing

@testable import Somna

private func metrics(
    count: Int,
    rms: Float,
    from offset: TimeInterval = 0,
    interval: TimeInterval = 0.1,
    zcr: Float = 0.2
) -> [AudioMetrics] {
    (0..<count).map {
        AudioMetrics(
            offset: offset + Double($0) * interval,
            rms: rms,
            peak: rms * 1.4,
            zeroCrossingRate: zcr
        )
    }
}

struct CandidateSelectorTests {

    /// A calm night is mostly silence, and silence needs no classifier.
    @Test("A silent night produces no candidates")
    func silenceProducesNothing() {
        let zones = CandidateSelector.select(
            metrics: metrics(count: 600, rms: 0.01),
            noiseFloor: 0.01,
            totalDuration: 60
        )
        #expect(zones.isEmpty)
    }

    @Test("A burst above the floor becomes a candidate")
    func burstIsDetected() throws {
        var samples = metrics(count: 100, rms: 0.01)
        samples += metrics(count: 30, rms: 0.4, from: 10)
        samples += metrics(count: 100, rms: 0.01, from: 13)

        let zones = CandidateSelector.select(
            metrics: samples, noiseFloor: 0.01, totalDuration: 60
        )

        let zone = try #require(zones.first)
        #expect(zone.start < 10)
        #expect(zone.end > 12)
    }

    /// A dip between two snores must not split one bout into two events.
    @Test("A brief dip does not split one event")
    func briefDipDoesNotSplit() {
        var samples = metrics(count: 20, rms: 0.4, from: 0)
        samples += metrics(count: 5, rms: 0.01, from: 2)
        samples += metrics(count: 20, rms: 0.4, from: 2.5)

        let zones = CandidateSelector.select(
            metrics: samples, noiseFloor: 0.01, totalDuration: 60
        )
        #expect(zones.count == 1)
    }

    /// The threshold adapts to the room: a noisy room needs a bigger jump.
    @Test("A noisy room raises its own threshold")
    func thresholdAdaptsToTheRoom() {
        let samples = metrics(count: 100, rms: 0.2)

        let quiet = CandidateSelector.select(metrics: samples, noiseFloor: 0.01, totalDuration: 60)
        let noisy = CandidateSelector.select(metrics: samples, noiseFloor: 0.2, totalDuration: 60)

        #expect(!quiet.isEmpty)
        #expect(noisy.isEmpty)
    }

    /// Without a budget, a night with a fan would mark everything and the
    /// morning pass would take as long as the night did.
    @Test("Analysis never covers more than the budgeted share of a night")
    func budgetIsEnforced() {
        var samples: [AudioMetrics] = []
        for block in 0..<20 {
            samples += metrics(count: 30, rms: 0.5, from: Double(block) * 10)
            samples += metrics(count: 30, rms: 0.01, from: Double(block) * 10 + 3)
        }

        let total: TimeInterval = 200
        let zones = CandidateSelector.select(
            metrics: samples, noiseFloor: 0.01, totalDuration: total
        )
        let covered = zones.reduce(0) { $0 + $1.duration }

        #expect(covered <= total * CandidateSelector.maximumFraction + 0.01)
    }

    @Test("Candidates come back in chronological order")
    func zonesAreChronological() {
        var samples: [AudioMetrics] = []
        for block in 0..<5 {
            samples += metrics(count: 20, rms: Float(block + 1) * 0.1, from: Double(block) * 20)
            samples += metrics(count: 20, rms: 0.005, from: Double(block) * 20 + 2)
        }

        let zones = CandidateSelector.select(
            metrics: samples, noiseFloor: 0.005, totalDuration: 1000
        )
        #expect(zones == zones.sorted { $0.start < $1.start })
    }

    @Test("Empty metrics produce no candidates rather than crashing")
    func emptyMetrics() {
        #expect(CandidateSelector.select(metrics: [], noiseFloor: 0, totalDuration: 60).isEmpty)
    }
}

struct EnvelopePeriodicityTests {

    /// Snoring has a rhythm; nothing else Somna listens for does. This is what
    /// lets the refiner disagree with a classifier that heard a fan.
    @Test("A breathing rhythm scores high")
    func rhythmIsDetected() {
        // One cycle every four seconds, sampled ten times a second.
        let levels = (0..<400).map { index -> Float in
            let phase = Double(index) * 0.1 / 4.0 * 2 * .pi
            return Float(0.3 + 0.25 * sin(phase))
        }

        let strength = EnvelopePeriodicity.strength(levels: levels, sampleInterval: 0.1)
        #expect(strength > 0.5)
    }

    /// The case this measure exists for. A fan is steady; snoring swings.
    /// Before the swing floor was added, rounding noise left over from removing
    /// the mean autocorrelated at 0.95 and a fan scored as strongly rhythmic —
    /// exactly backwards.
    @Test("A perfectly steady hum has no rhythm")
    func steadyLevelHasNoRhythm() {
        let strength = EnvelopePeriodicity.strength(
            levels: Array(repeating: 0.3, count: 400), sampleInterval: 0.1
        )
        #expect(strength == 0)
    }

    @Test("A hum with only slight drift still has no rhythm")
    func slightlyDriftingHumHasNoRhythm() {
        let levels = (0..<400).map { Float(0.30 + Double($0) * 0.000_01) }
        #expect(EnvelopePeriodicity.strength(levels: levels, sampleInterval: 0.1) < 0.35)
    }

    @Test("Too few samples yield no score rather than a false one")
    func tooFewSamples() {
        #expect(EnvelopePeriodicity.strength(levels: [0.1, 0.2], sampleInterval: 0.1) == 0)
    }
}

struct ClassificationMappingTests {

    /// Apple's label set is not a published contract: names differ between OS
    /// versions. Exact matching would make a point release silently stop
    /// detecting doors.
    @Test("Labels match by substring, so naming variants still map")
    func substringMatching() {
        #expect(ClassificationMapping.type(for: "snoring") == .snoring)
        #expect(ClassificationMapping.type(for: "person_snoring") == .snoring)
        #expect(ClassificationMapping.type(for: "door_open_or_close") == .door)
        #expect(ClassificationMapping.type(for: "cat_meow") == .animal)
    }

    /// Specific rules must beat general ones, or an alarm clock becomes a clock.
    @Test("More specific labels win over general ones")
    func specificRulesWinFirst() {
        #expect(ClassificationMapping.type(for: "alarm_clock") == .alarm)
        #expect(ClassificationMapping.type(for: "snoring_breathing") == .snoring)
    }

    @Test("An unrecognised label becomes unknown, never a guess")
    func unknownLabelsStayUnknown() {
        #expect(ClassificationMapping.type(for: "zzz_unheard_of_class") == .unknown)
    }

    @Test("Matching ignores case")
    func caseInsensitive() {
        #expect(ClassificationMapping.type(for: "Snoring") == .snoring)
        #expect(ClassificationMapping.type(for: "COUGH") == .coughing)
    }

    /// A label that vanished in an OS update must be discovered at analysis
    /// time, not inferred from a night that mysteriously found no snoring.
    @Test("Missing expected classes are reported")
    func missingClassesAreReported() {
        let missing = ClassificationMapping.missingExpectedPatterns(in: ["speech", "rain"])
        #expect(missing.contains("snor"))
        #expect(missing.contains("cough"))
        #expect(!missing.contains("speech"))
    }

    @Test("A complete classifier reports nothing missing")
    func completeClassifier() {
        let missing = ClassificationMapping.missingExpectedPatterns(
            in: ["snoring", "coughing", "speech", "breathing"]
        )
        #expect(missing.isEmpty)
    }
}

struct RuleBasedRefinerTests {

    private func zone(
        duration: TimeInterval = 5,
        zcr: Float = 0.15,
        peak: Float = 0.6
    ) -> CandidateZone {
        CandidateZone(
            start: 0, end: duration, peak: peak,
            averageLevel: 0.3, averageZeroCrossingRate: zcr
        )
    }

    private func input(
        identifier: String,
        confidence: Double = 0.8,
        periodicity: Double = 0.6,
        zone: CandidateZone? = nil
    ) -> RuleBasedRefiner.Input {
        RuleBasedRefiner.Input(
            classification: SoundClassification(
                identifier: identifier, confidence: confidence, start: 0, duration: 5
            ),
            zone: zone ?? self.zone(),
            periodicity: periodicity
        )
    }

    /// The rule that stops a bedroom fan being reported as snoring every night.
    @Test("Snoring without a breath rhythm is not called snoring")
    func snoringNeedsRhythm() {
        let refined = RuleBasedRefiner.refine(input(identifier: "snoring", periodicity: 0.05))

        #expect(refined.type == .whiteNoise)
        #expect(refined.adjustment == .snoringWithoutRhythm)
        #expect(refined.confidence <= 0.5)
    }

    @Test("Snoring with a rhythm is left alone")
    func rhythmicSnoringSurvives() {
        let refined = RuleBasedRefiner.refine(input(identifier: "snoring", periodicity: 0.7))

        #expect(refined.type == .snoring)
        #expect(refined.adjustment == nil)
        #expect(refined.confidence == 0.8)
    }

    @Test("Snoring that is too bright loses confidence")
    func brightSnoringIsDowngraded() {
        let refined = RuleBasedRefiner.refine(
            input(identifier: "snoring", periodicity: 0.7, zone: zone(zcr: 0.5))
        )
        #expect(refined.type == .snoring)
        #expect(refined.confidence < 0.8)
        #expect(refined.adjustment == .snoringTooBright)
    }

    /// Speech is never a third of a second long.
    @Test("A burst too brief to be speech becomes bedding noise")
    func briefSpeechIsRustling() {
        let refined = RuleBasedRefiner.refine(
            input(identifier: "speech", zone: zone(duration: 0.4))
        )
        #expect(refined.type == .beddingNoise)
        #expect(refined.adjustment == .speechTooBrief)
    }

    @Test("Normal speech is left alone")
    func normalSpeechSurvives() {
        let refined = RuleBasedRefiner.refine(input(identifier: "speech", zone: zone(duration: 3)))
        #expect(refined.type == .talking)
        #expect(refined.adjustment == nil)
    }

    @Test("A short bright quiet transient is reported as possible movement")
    func transientBecomesMovement() {
        let refined = RuleBasedRefiner.refine(
            input(identifier: "unrecognised_thing", zone: zone(duration: 1, zcr: 0.45, peak: 0.3))
        )
        #expect(refined.type == .movementNoise)
        #expect(refined.adjustment == .unclassifiedTransient)
    }

    /// Every rule may only lower confidence or make a label vaguer. None of them
    /// may invent a detection the model did not make.
    @Test("No rule ever raises confidence")
    func rulesNeverPromote() {
        let cases: [(String, Double, CandidateZone)] = [
            ("snoring", 0.05, zone()),
            ("snoring", 0.7, zone(zcr: 0.5)),
            ("speech", 0.6, zone(duration: 0.3)),
            ("unrecognised", 0.6, zone(duration: 1, zcr: 0.45, peak: 0.3)),
            ("rain", 0.9, zone()),
        ]

        for (identifier, periodicity, area) in cases {
            let source = input(identifier: identifier, confidence: 0.8,
                               periodicity: periodicity, zone: area)
            let refined = RuleBasedRefiner.refine(source)
            #expect(
                refined.confidence <= source.classification.confidence,
                "\(identifier) had its confidence raised by a rule"
            )
        }
    }

    @Test("Detections below the rejection threshold never become events")
    func weakDetectionsAreDropped() {
        let refined = [
            RuleBasedRefiner.Refined(type: .coughing, confidence: 0.2, start: 0,
                                     duration: 1, peak: 0.5, adjustment: nil),
            RuleBasedRefiner.Refined(type: .coughing, confidence: 0.9, start: 10,
                                     duration: 1, peak: 0.5, adjustment: nil),
        ]

        let events = RuleBasedRefiner.makeEvents(
            from: refined,
            sessionID: UUID(),
            sessionStart: Date(timeIntervalSince1970: 1_800_000_000),
            rejectionThreshold: EventConfidence.rejectionThreshold,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(events.count == 1)
        #expect(events.first?.confidence == .high)
    }

    /// "Conservative" must mean fewer, surer events — not the same events with
    /// different labels.
    @Test("A stricter sensitivity yields strictly fewer events")
    func sensitivityChangesTheCount() {
        let refined = (0..<10).map { index in
            RuleBasedRefiner.Refined(
                type: .coughing, confidence: 0.3 + Double(index) * 0.05,
                start: Double(index) * 60, duration: 1, peak: 0.5, adjustment: nil
            )
        }

        func count(threshold: Double) -> Int {
            RuleBasedRefiner.makeEvents(
                from: refined, sessionID: UUID(),
                sessionStart: Date(timeIntervalSince1970: 1_800_000_000),
                rejectionThreshold: threshold,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            ).count
        }

        #expect(count(threshold: 0.45) < count(threshold: 0.35))
    }
}
