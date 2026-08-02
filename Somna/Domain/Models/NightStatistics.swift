import Foundation

/// What a night added up to.
///
/// Every field is derived from detected events and measured audio. Nothing here
/// is inferred about sleep itself, because nothing in the recording supports it.
struct NightStatistics: Equatable, Sendable, Codable {

    var recordedDuration: TimeInterval
    /// Time with no detected event, which is not the same as time asleep.
    var quietDuration: TimeInterval

    var snoringDuration: TimeInterval
    var coughCount: Int
    var talkingDuration: TimeInterval
    var loudEventCount: Int
    var totalEventCount: Int

    var eventCountsByType: [NightEventType: Int]

    /// Longest stretch with nothing detected, if one is long enough to mean
    /// anything.
    var calmestPeriod: DateInterval?
    /// The hour of the night holding the most events.
    var busiestHour: Date?

    static let empty = NightStatistics(
        recordedDuration: 0,
        quietDuration: 0,
        snoringDuration: 0,
        coughCount: 0,
        talkingDuration: 0,
        loudEventCount: 0,
        totalEventCount: 0,
        eventCountsByType: [:],
        calmestPeriod: nil,
        busiestHour: nil
    )
}

extension NightStatistics {
    /// Share of the recording with nothing detected, 0–1.
    var quietFraction: Double {
        guard recordedDuration > 0 else { return 0 }
        return min(1, quietDuration / recordedDuration)
    }

    var snoringFraction: Double {
        guard recordedDuration > 0 else { return 0 }
        return min(1, snoringDuration / recordedDuration)
    }

    /// Detected events per hour of recording.
    var eventsPerHour: Double {
        guard recordedDuration > 0 else { return 0 }
        return Double(totalEventCount) / (recordedDuration / 3600)
    }
}
