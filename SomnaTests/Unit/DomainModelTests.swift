import Foundation
import Testing

@testable import Somna

struct EventConfidenceTests {

    @Test("Scores below the rejection threshold produce no confidence at all")
    func weakScoresAreRejected() {
        #expect(EventConfidence(score: 0.0) == nil)
        #expect(EventConfidence(score: 0.34) == nil)
        // A rejected detection must not degrade to `.low`: showing it would put
        // a guess on the timeline with the same visual weight as a real event.
        #expect(EventConfidence(score: 0.349) == nil)
    }

    @Test("Scores map to the documented bands")
    func scoresMapToBands() {
        #expect(EventConfidence(score: 0.35) == .low)
        #expect(EventConfidence(score: 0.54) == .low)
        #expect(EventConfidence(score: 0.55) == .medium)
        #expect(EventConfidence(score: 0.79) == .medium)
        #expect(EventConfidence(score: 0.80) == .high)
        #expect(EventConfidence(score: 1.0) == .high)
    }

    @Test("Non-finite scores are rejected rather than crashing")
    func nonFiniteScoresAreRejected() {
        #expect(EventConfidence(score: .nan) == nil)
        #expect(EventConfidence(score: .infinity) == .high)
        #expect(EventConfidence(score: -.infinity) == nil)
    }

    @Test("Confidence orders from low to high")
    func confidenceIsOrdered() {
        #expect(EventConfidence.low < .medium)
        #expect(EventConfidence.medium < .high)
        #expect(max(.low, .high) == .high)
    }
}

struct NightEventTests {

    private let sessionID = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEvent(
        type: NightEventType = .snoring,
        corrected: NightEventType? = nil,
        confidence: EventConfidence = .medium,
        duration: TimeInterval = 30
    ) -> NightEvent {
        NightEvent(
            sessionID: sessionID,
            type: type,
            userCorrectedType: corrected,
            confidence: confidence,
            startDate: now,
            endDate: now.addingTimeInterval(duration),
            createdAt: now
        )
    }

    @Test("A user correction overrides the model's classification")
    func userCorrectionWins() {
        let event = makeEvent(type: .snoring, corrected: .coughing)
        #expect(event.effectiveType == .coughing)
        // The original stays intact: the (model guess, human answer) pair is
        // exactly the signal a future model would learn from.
        #expect(event.type == .snoring)
    }

    @Test("A corrected event is stated with full confidence")
    func correctionRaisesConfidence() {
        let event = makeEvent(confidence: .low, corrected: .coughing)
        #expect(event.effectiveConfidence == .high)
        #expect(event.title == "Cough detected")
    }

    @Test("An uncorrected event keeps its hedged wording")
    func uncorrectedEventKeepsHedging() {
        #expect(makeEvent(type: .coughing, confidence: .medium).title == "Likely cough")
        #expect(makeEvent(type: .coughing, confidence: .low).title == "Cough-like sound")
    }

    @Test("An end date before the start date is clamped, never negative")
    func durationIsNeverNegative() {
        let event = NightEvent(
            sessionID: sessionID,
            type: .snoring,
            confidence: .high,
            startDate: now,
            endDate: now.addingTimeInterval(-500),
            createdAt: now
        )
        #expect(event.duration == 0)
    }

    @Test("Levels are clamped into 0...1")
    func levelsAreClamped() {
        let event = NightEvent(
            sessionID: sessionID,
            type: .impact,
            confidence: .high,
            startDate: now,
            endDate: now,
            peakLevel: 4.2,
            averageLevel: -1,
            createdAt: now
        )
        #expect(event.peakLevel == 1)
        #expect(event.averageLevel == 0)
    }

    @Test("Occurrence count is at least one")
    func occurrenceCountFloor() {
        #expect(makeEvent().occurrenceCount == 1)
        let grouped = NightEvent(
            sessionID: sessionID,
            type: .snoring,
            confidence: .high,
            startDate: now,
            endDate: now,
            occurrenceCount: 0,
            createdAt: now
        )
        #expect(grouped.occurrenceCount == 1)
        #expect(!grouped.isGrouped)
    }
}

struct NightSessionTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSession(
        recorded: TimeInterval,
        wallClock: TimeInterval
    ) -> NightSession {
        NightSession(
            startDate: start,
            endDate: start.addingTimeInterval(wallClock),
            status: .completed,
            recordedDuration: recorded,
            createdAt: start,
            updatedAt: start
        )
    }

    /// Presenting elapsed time as recorded time would inflate every statistic
    /// derived from it, and hide exactly the interruptions the user needs to see.
    @Test("Coverage reflects how much of the night was actually captured")
    func coverageDistinguishesRecordedFromElapsed() throws {
        let session = makeSession(recorded: 6 * 3600, wallClock: 8 * 3600)
        let coverage = try #require(session.captureCoverage)
        #expect(abs(coverage - 0.75) < 0.0001)
        #expect(session.wallClockDuration == 8 * 3600)
    }

    @Test("Coverage never exceeds one, even with inconsistent data")
    func coverageIsCapped() throws {
        let session = makeSession(recorded: 10 * 3600, wallClock: 8 * 3600)
        #expect(try #require(session.captureCoverage) == 1)
    }

    @Test("A running session has no coverage yet")
    func runningSessionHasNoCoverage() {
        let session = NightSession(
            startDate: start,
            status: .recording,
            recordedDuration: 600,
            createdAt: start,
            updatedAt: start
        )
        #expect(session.captureCoverage == nil)
        #expect(!session.isFinished)
    }

    @Test("Sessions shorter than the analysable minimum are not analysed")
    func shortSessionsAreNotAnalysable() {
        #expect(!makeSession(recorded: 4 * 60, wallClock: 4 * 60).isAnalysable)
        #expect(makeSession(recorded: 5 * 60, wallClock: 5 * 60).isAnalysable)
    }

    @Test("Interrupted sessions are not treated as finished")
    func interruptedIsNotFinished() {
        var session = makeSession(recorded: 3600, wallClock: 7200)
        session.status = .interrupted
        // They still hold usable audio, so the app must offer to analyse them
        // rather than discard the night.
        #expect(!session.isFinished)
        #expect(session.isAnalysable)
    }
}

struct RetentionPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Age-based policies purge only past their window")
    func ageBasedPolicies() {
        let sixDays = now.addingTimeInterval(-6 * 24 * 3600)
        let eightDays = now.addingTimeInterval(-8 * 24 * 3600)

        #expect(!AudioRetentionPolicy.sevenDays.shouldPurgeRawAudio(recordedAt: sixDays, now: now))
        #expect(AudioRetentionPolicy.sevenDays.shouldPurgeRawAudio(recordedAt: eightDays, now: now))
        #expect(!AudioRetentionPolicy.thirtyDays.shouldPurgeRawAudio(recordedAt: eightDays, now: now))
    }

    @Test("Keeping everything never purges")
    func keepAllNeverPurges() {
        let ancient = now.addingTimeInterval(-3650 * 24 * 3600)
        #expect(!AudioRetentionPolicy.keepAll.shouldPurgeRawAudio(recordedAt: ancient, now: now))
    }

    @Test("Clips-only purges immediately")
    func clipsOnlyPurgesImmediately() {
        #expect(AudioRetentionPolicy.clipsOnly.shouldPurgeRawAudio(recordedAt: now, now: now))
    }

    /// A night is ~115 MB raw. Defaulting to unlimited would quietly consume
    /// gigabytes of someone's phone for audio they will never replay.
    @Test("The default policy is not unlimited retention")
    func defaultIsNotKeepAll() {
        #expect(UserSettings.default.retentionPolicy != .keepAll)
    }

    @Test("Consent flags default to off")
    func consentDefaultsToOff() {
        #expect(!UserSettings.default.cloudProcessingConsent)
        #expect(!UserSettings.default.analyticsConsent)
    }

    @Test("Sensitivity shifts the rejection threshold within safe bounds")
    func sensitivityShiftsThreshold() {
        var settings = UserSettings.default

        settings.analysisSensitivity = .balanced
        #expect(settings.effectiveRejectionThreshold == EventConfidence.rejectionThreshold)

        settings.analysisSensitivity = .conservative
        #expect(settings.effectiveRejectionThreshold > EventConfidence.rejectionThreshold)

        settings.analysisSensitivity = .sensitive
        #expect(settings.effectiveRejectionThreshold < EventConfidence.rejectionThreshold)
        #expect(settings.effectiveRejectionThreshold >= 0.2)
    }
}

struct DurationTests {

    /// Decomposition is asserted instead of the localised string: rendered
    /// output varies by locale and OS version, and a test that breaks on an OS
    /// update without a real regression trains people to ignore failures.
    @Test("Durations decompose into whole units")
    func decomposition() {
        #expect(TimeInterval(7 * 3600 + 24 * 60 + 30).durationComponents
                == TimeInterval.Components(hours: 7, minutes: 24, seconds: 30))
        #expect(TimeInterval(59).durationComponents
                == TimeInterval.Components(hours: 0, minutes: 0, seconds: 59))
    }

    @Test("Negative and non-finite durations clamp to zero")
    func invalidDurationsClamp() {
        let zero = TimeInterval.Components(hours: 0, minutes: 0, seconds: 0)
        #expect(TimeInterval(-500).durationComponents == zero)
        #expect(TimeInterval.nan.durationComponents == zero)
        #expect(TimeInterval.infinity.durationComponents == zero)
    }

    @Test("Compact form is stable and locale-independent")
    func compactForm() {
        #expect(TimeInterval(7 * 3600 + 24 * 60).formattedCompactDuration == "7:24")
        #expect(TimeInterval(48).formattedCompactDuration == "0:48")
        #expect(TimeInterval(9 * 60 + 5).formattedCompactDuration == "9:05")
    }
}

struct WaveformCodingTests {

    @Test("Envelopes survive a round trip within display precision")
    func roundTrip() {
        let samples: [Float] = [0, 0.25, 0.5, 0.75, 1]
        let decoded = WaveformCoding.decode(WaveformCoding.encode(samples))

        #expect(decoded.count == samples.count)
        for (original, result) in zip(samples, decoded) {
            // 8-bit quantisation: indistinguishable at the size a bar is drawn.
            #expect(abs(original - result) < 0.01)
        }
    }

    @Test("Out-of-range and empty inputs are handled")
    func edgeCases() {
        #expect(WaveformCoding.encode([]) == nil)
        #expect(WaveformCoding.decode(nil).isEmpty)

        let decoded = WaveformCoding.decode(WaveformCoding.encode([-3, 5, .nan]))
        #expect(decoded == [0, 1, 0])
    }

    @Test("Encoding is one byte per sample")
    func encodingIsCompact() throws {
        let data = try #require(WaveformCoding.encode(Array(repeating: 0.5, count: 120)))
        #expect(data.count == 120)
    }
}
