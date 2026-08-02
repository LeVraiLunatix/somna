import Foundation

/// The calmness score, 0–100.
///
/// **What it is:** how quiet the recording was.
/// **What it is not:** a measure of sleep, sleep quality, or health. The app
/// says so wherever the number appears, and the type is named for what it
/// actually measures so no screen can accidentally imply otherwise.
///
/// The formula is deliberately simple and inspectable. A score derived from an
/// opaque model would be impossible to explain to someone who disagrees with it,
/// and "why is my score 61" is a question this app must be able to answer.
enum CalmnessScoreCalculator {

    /// Penalty ceilings. Each factor is capped so no single one can dominate:
    /// a night with heavy snoring but nothing else should not score zero, and
    /// one loud bang should not erase an otherwise peaceful night.
    enum Weight {
        static let snoring = 35.0
        static let loudEvents = 20.0
        static let eventDensity = 20.0
        static let interruptions = 15.0
    }

    /// - Returns: `nil` when the recording cannot support a score at all.
    ///   Showing a number for an unusable night would give it a precision it does
    ///   not have, and a low score would read as "a bad night" rather than "a bad
    ///   recording".
    static func score(
        statistics: NightStatistics,
        quality: RecordingQuality?,
        isAnalysable: Bool
    ) -> Int? {
        guard isAnalysable else { return nil }
        if let quality, quality.rating == .unusable { return nil }

        var penalty = 0.0

        // Snoring is scored by how much of the night it occupied rather than by
        // how many episodes there were: ten brief snores are not a loud night.
        penalty += min(Weight.snoring, statistics.snoringFraction * 100 * 0.7)

        penalty += min(Weight.loudEvents, Double(statistics.loudEventCount) * 4)

        // Density excludes snoring, which is already counted above, so a snoring
        // night is not penalised twice for the same sound.
        let nonSnoringEvents = max(0, statistics.totalEventCount - (statistics.eventCountsByType[.snoring] ?? 0))
        let density = statistics.recordedDuration > 0
            ? Double(nonSnoringEvents) / (statistics.recordedDuration / 3600)
            : 0
        penalty += min(Weight.eventDensity, density * 2.5)

        // Interruptions lower the score because they lower confidence in it, and
        // the report says as much rather than leaving the drop unexplained.
        let coverage = quality?.coverage ?? 1
        penalty += min(Weight.interruptions, (1 - coverage) * 30)

        return Int((100 - penalty).rounded().clamped(to: 0...100))
    }

    /// Plain-language band, for the report. Never a verdict on the person.
    enum Band: String, Sendable {
        case veryCalm
        case calm
        case someActivity
        case restless

        init(score: Int) {
            switch score {
            case 85...: self = .veryCalm
            case 65..<85: self = .calm
            case 40..<65: self = .someActivity
            default: self = .restless
            }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
