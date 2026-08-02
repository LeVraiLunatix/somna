import Foundation

/// Judges whether a night's audio can support any conclusion.
///
/// This runs before the report is shown, and it is allowed to veto it. The
/// alternative — a report full of statistics drawn from unusable audio — is the
/// single most damaging thing Somna could produce: a night recorded through a
/// pillow yields almost no detections, and without this that reads as "a calm
/// night" rather than "a bad recording".
enum RecordingQualityAssessor {

    /// Above this measured floor, quieter events are being masked.
    static let highNoiseFloor = 0.20
    /// Below this, essentially nothing reached the microphone.
    static let silentFloor = 0.002
    /// Below this share of the session captured, the picture has real holes.
    static let poorCoverage = 0.80

    static func assess(
        session: NightSession,
        events: [NightEvent],
        averageNoiseFloor: Double,
        peakLevel: Double,
        gapCount: Int
    ) -> RecordingQuality {

        var issues: [RecordingIssue] = []
        let coverage = session.captureCoverage ?? 1

        if !session.isAnalysable {
            issues.append(.shortSession)
        }
        if gapCount > 0 || coverage < poorCoverage {
            issues.append(.sessionInterrupted)
        }
        if averageNoiseFloor >= highNoiseFloor {
            issues.append(.highConstantNoise)
        }
        if peakLevel < 0.05 {
            issues.append(.levelTooLow)
        }

        // A microphone under a pillow and a genuinely silent room look identical
        // in the average. What separates them is that a real room has *peaks* —
        // a car outside, a creak. A night with no peak at all was not quiet, it
        // was deaf.
        if peakLevel < silentFloor {
            issues.append(.microphoneObstructed)
        }

        let mediaShare = events.filter { $0.effectiveType == .television }
            .reduce(0.0) { $0 + $1.duration }
        if session.recordedDuration > 0, mediaShare / session.recordedDuration > 0.25 {
            issues.append(.mediaPlaying)
        }

        return RecordingQuality(
            rating: rating(issues: issues, coverage: coverage, peakLevel: peakLevel),
            issues: issues,
            averageNoiseFloor: averageNoiseFloor,
            coverage: coverage
        )
    }

    private static func rating(
        issues: [RecordingIssue],
        coverage: Double,
        peakLevel: Double
    ) -> RecordingQualityRating {
        // Two conditions make a night genuinely unusable, and both mean the same
        // thing: whatever the app says about this night would be invented.
        if issues.contains(.microphoneObstructed) { return .unusable }
        if coverage < 0.25 { return .unusable }

        if issues.contains(.shortSession) { return .poor }
        if issues.contains(.highConstantNoise) || issues.contains(.levelTooLow) { return .poor }
        if issues.isEmpty && coverage >= 0.98 { return .excellent }
        return .good
    }
}
