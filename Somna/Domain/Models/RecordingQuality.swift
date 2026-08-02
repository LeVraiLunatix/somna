import Foundation

/// How usable a night's audio turned out to be.
///
/// Reported honestly and prominently. A night recorded through a pillow with a
/// fan running produces few detections, and without this the user reads that as
/// "a calm night" instead of "a bad recording" — the single most damaging
/// misunderstanding this app can create.
enum RecordingQualityRating: String, Codable, Sendable, CaseIterable {
    case excellent
    case good
    case poor
    /// Too degraded for any conclusion. The report says so instead of showing
    /// statistics that would be noise.
    case unusable
}

/// Specific, actionable problems found in a recording.
enum RecordingIssue: String, Codable, Sendable, CaseIterable {
    case phoneTooFar
    case microphoneObstructed
    case highConstantNoise
    case mediaPlaying
    case levelTooLow
    case sessionInterrupted
    case shortSession
}

struct RecordingQuality: Equatable, Sendable, Codable {
    var rating: RecordingQualityRating
    var issues: [RecordingIssue]

    /// Mean noise floor over the night, normalised against the calibration
    /// reference. Relative, never presented as decibels.
    var averageNoiseFloor: Double

    /// Fraction of the session that was actually captured, 0–1.
    var coverage: Double

    init(
        rating: RecordingQualityRating,
        issues: [RecordingIssue] = [],
        averageNoiseFloor: Double = 0,
        coverage: Double = 1
    ) {
        self.rating = rating
        self.issues = issues
        self.averageNoiseFloor = averageNoiseFloor
        self.coverage = coverage
    }
}

extension RecordingQuality {
    /// Whether the report should suppress statistics and explain instead.
    var suppressesConclusions: Bool {
        rating == .unusable
    }
}

extension RecordingIssue {
    /// English source string; localised in Phase 4 alongside the event catalogue.
    var advice: String {
        switch self {
        case .phoneTooFar:
            "Your iPhone may have been too far from the bed. Aim for under a metre."
        case .microphoneObstructed:
            "Something may have covered the microphone. Leave the bottom edge clear."
        case .highConstantNoise:
            "A steady noise, such as a fan, masked quieter sounds."
        case .mediaPlaying:
            "A television or music was playing for part of the night."
        case .levelTooLow:
            "The recording was very quiet throughout."
        case .sessionInterrupted:
            "Recording stopped and resumed at least once during the night."
        case .shortSession:
            "The session was too short for patterns to emerge."
        }
    }
}
