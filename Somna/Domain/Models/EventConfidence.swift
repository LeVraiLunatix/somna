import Foundation

/// How sure Somna is about a classification.
///
/// The thresholds are product decisions, not tuning constants: they set how
/// assertive the app is allowed to be about someone's night. They are defined
/// once, here, so no screen can quietly present a weak detection as a fact.
///
/// Anything below ``rejectionThreshold`` is not surfaced at all. Missing an
/// event costs a user nothing; inventing one costs their trust in every other
/// event on the timeline.
enum EventConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    /// Scores under this are discarded during analysis and never reach the UI.
    static let rejectionThreshold = 0.35

    static let mediumThreshold = 0.55
    static let highThreshold = 0.80

    /// Maps a classifier score to a confidence level.
    ///
    /// - Returns: `nil` when the score is too weak to show, which callers must
    ///   treat as "drop this detection" rather than "show it as low".
    init?(score: Double) {
        guard score.isFinite, score >= Self.rejectionThreshold else { return nil }
        switch score {
        case Self.highThreshold...: self = .high
        case Self.mediumThreshold..<Self.highThreshold: self = .medium
        default: self = .low
        }
    }
}

extension EventConfidence: Comparable {
    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: EventConfidence, rhs: EventConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}
