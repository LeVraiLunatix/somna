import Foundation

extension TimeInterval {

    /// A duration split into whole hours, minutes and seconds.
    ///
    /// Deliberately separate from formatting: the decomposition is pure and
    /// unit-testable, while the localised rendering depends on the user's locale
    /// and cannot be asserted reliably across OS versions.
    ///
    /// Negative durations clamp to zero — a negative night length is a data
    /// defect, and rendering "-3 h" to a user helps nobody.
    struct Components: Equatable, Sendable {
        let hours: Int
        let minutes: Int
        let seconds: Int
    }

    var durationComponents: Components {
        let total = Int((self.isFinite ? max(0, self) : 0).rounded())
        return Components(
            hours: total / 3600,
            minutes: (total % 3600) / 60,
            seconds: total % 60
        )
    }

    /// Long form for headline figures: `7 hr 24 min`, `48 min`, `12 sec`.
    ///
    /// Seconds are shown only for durations under a minute, because a night
    /// report reading "7 hr 24 min 12 sec" implies a precision the estimate does
    /// not have.
    func formattedDuration(locale: Locale = .current) -> String {
        let components = durationComponents
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar

        if components.hours > 0 {
            formatter.allowedUnits = [.hour, .minute]
        } else if components.minutes > 0 {
            formatter.allowedUnits = [.minute]
        } else {
            formatter.allowedUnits = [.second]
        }

        return formatter.string(from: durationComponentsRounded) ?? "—"
    }

    /// Compact form for dense contexts such as timeline rows: `7:24`, `0:48`.
    var formattedCompactDuration: String {
        let components = durationComponents
        if components.hours > 0 {
            return String(format: "%d:%02d", components.hours, components.minutes)
        }
        return String(format: "%d:%02d", components.minutes, components.seconds)
    }

    /// Rounds away the sub-unit remainder so the formatter never renders a unit
    /// the caller decided to hide.
    private var durationComponentsRounded: TimeInterval {
        let components = durationComponents
        if components.hours > 0 {
            return TimeInterval(components.hours * 3600 + components.minutes * 60)
        }
        if components.minutes > 0 {
            return TimeInterval(components.minutes * 60)
        }
        return TimeInterval(components.seconds)
    }
}
