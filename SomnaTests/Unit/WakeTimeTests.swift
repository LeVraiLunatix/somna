import Foundation
import Testing

@testable import Somna

/// The wake alarm's one testable part, and the one worth testing.
///
/// AlarmKit itself cannot be exercised in CI. This can — and it is the piece
/// that fails in a way nobody notices until they oversleep: a wake time of 07:00
/// set at 23:40 means tomorrow, the same time set at 05:00 means this morning.
/// Getting it backwards is a missed alarm.
struct WakeTimeTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour, minute: minute
        )) ?? Date()
    }

    @Test("A wake time later tonight resolves to tomorrow morning")
    func setAtNightResolvesToTomorrow() throws {
        let now = date(3, 23, 40)
        let next = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))

        #expect(next == date(4, 7, 0))
        #expect(next.timeIntervalSince(now) > 7 * 3600)
    }

    @Test("A wake time still ahead today resolves to today")
    func setBeforeDawnResolvesToToday() throws {
        let now = date(4, 5, 0)
        let next = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))

        #expect(next == date(4, 7, 0))
        #expect(next.timeIntervalSince(now) == 2 * 3600)
    }

    /// Otherwise an alarm set for the current minute would fire instantly and
    /// end the night the moment it began.
    @Test("A wake time equal to now belongs to tomorrow")
    func exactlyNowIsTomorrow() throws {
        let now = date(4, 7, 0)
        let next = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))

        #expect(next == date(5, 7, 0))
    }

    @Test("A wake time just past resolves to tomorrow")
    func justPassedIsTomorrow() throws {
        let now = date(4, 7, 1)
        let next = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))

        #expect(next == date(5, 7, 0))
    }

    @Test("Midnight is handled like any other time")
    func midnight() throws {
        let now = date(3, 23, 30)
        let next = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 0, after: now, calendar: calendar
        ))

        #expect(next == date(4, 0, 0))
    }

    @Test("Out-of-range minute values wrap rather than failing")
    func minutesWrap() throws {
        let now = date(3, 23, 0)

        let wrapped = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 24 * 60 + 7 * 60, after: now, calendar: calendar
        ))
        let plain = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))
        #expect(wrapped == plain)

        let negative = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: -60, after: now, calendar: calendar
        ))
        #expect(negative == date(4, 23, 0))
    }

    @Test("The resulting night length is always positive")
    func durationIsPositive() throws {
        for hour in 0..<24 {
            let now = date(3, hour, 30)
            let duration = try #require(WakeTime.duration(
                untilMinutesFromMidnight: 7 * 60, from: now, calendar: calendar
            ))
            #expect(duration > 0, "Negative night length starting at \(hour):30")
            #expect(duration <= 24 * 3600)
        }
    }

    /// The setting is stored as minutes from midnight rather than as a `Date`
    /// precisely so that a night spent in another timezone still wakes the
    /// sleeper at the local hour they chose.
    @Test("The wake hour follows the calendar's timezone")
    func respectsTimeZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

        let now = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 23, minute: 0
        )) ?? Date()

        let parisWake = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: calendar
        ))
        let tokyoWake = try #require(WakeTime.nextOccurrence(
            ofMinutesFromMidnight: 7 * 60, after: now, calendar: tokyo
        ))

        #expect(parisWake != tokyoWake)
        #expect(tokyo.component(.hour, from: tokyoWake) == 7)
        #expect(calendar.component(.hour, from: parisWake) == 7)
    }
}
