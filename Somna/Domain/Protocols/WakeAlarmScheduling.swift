import Foundation

/// Whether Somna may ring an alarm.
enum WakeAlarmPermission: String, Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

/// Schedules the alarm that ends a night.
///
/// A protocol because AlarmKit is iOS 26 only, unverified on a device, and the
/// rest of the app must not care. It also keeps the tests honest: nothing here
/// can be exercised in CI, so everything that *can* be tested lives in
/// ``WakeTime`` instead.
protocol WakeAlarmScheduling: Sendable {
    func permission() async -> WakeAlarmPermission
    func requestPermission() async -> WakeAlarmPermission

    /// Schedules a one-off alarm.
    func schedule(id: UUID, at date: Date, title: String, stopButtonTitle: String) async throws
    func cancel(id: UUID) async
}

/// When the alarm should next go off.
///
/// Pure, and separated from the alarm service for one reason: this is the part
/// that can be wrong in a way nobody notices until they oversleep. A wake time
/// of 07:00 set at 23:40 means tomorrow; set at 05:00 it means this morning.
/// Getting that backwards is a missed alarm, so it is computed here and tested.
enum WakeTime {

    /// The next occurrence of `minutesFromMidnight`, strictly after `now`.
    ///
    /// - Parameter minutesFromMidnight: stored timezone-independently, like the
    ///   evening reminder, so a night spent in another timezone still wakes the
    ///   sleeper at the local hour they chose.
    static func nextOccurrence(
        ofMinutesFromMidnight minutes: Int,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        let normalised = ((minutes % 1440) + 1440) % 1440

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = normalised / 60
        components.minute = normalised % 60
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return nil }

        // Strictly after: an alarm set for the exact current minute belongs to
        // tomorrow, not to a moment that has already passed.
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    /// How long a night would run if it ended at the next wake time.
    static func duration(
        untilMinutesFromMidnight minutes: Int,
        from now: Date,
        calendar: Calendar
    ) -> TimeInterval? {
        guard let next = nextOccurrence(ofMinutesFromMidnight: minutes, after: now, calendar: calendar)
        else { return nil }
        return next.timeIntervalSince(now)
    }
}
