import Foundation

/// Source of the current time.
///
/// Injected everywhere rather than calling `Date()` directly, so tests over
/// night boundaries, retention windows and sleep-window estimation are
/// deterministic. A test that depends on the wall clock is a test that fails at
/// midnight or in another timezone.
protocol Clocking: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
    var timeZone: TimeZone { get }
}

extension Clocking {
    var calendar: Calendar { Calendar.current }
    var timeZone: TimeZone { TimeZone.current }
}

/// The real clock, used by the running app.
struct SystemClock: Clocking {
    var now: Date { Date() }
}

/// A clock frozen at a chosen instant, for tests and previews.
///
/// Lives in the app target rather than the test target because SwiftUI previews
/// need it too, and a preview that shows "3 hours ago" differently on every
/// rebuild is not a preview.
struct FixedClock: Clocking {
    let now: Date
    let calendar: Calendar
    let timeZone: TimeZone

    init(
        now: Date,
        timeZone: TimeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
    ) {
        self.now = now
        self.timeZone = timeZone

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }
}
