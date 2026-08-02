import SwiftUI

/// Type scale, built entirely on system text styles so Dynamic Type works
/// without any per-view arithmetic.
///
/// Nothing here uses a fixed point size. A fixed size looks deliberate in a
/// mock-up and becomes unreadable at AX5, which is exactly the setting used by
/// the people who most need a night report to be legible at 6 a.m.
enum SomnaFont {

    /// The calmness score and nothing else. `.rounded` keeps a large number from
    /// reading as clinical.
    static let display = Font.system(.largeTitle, design: .rounded, weight: .semibold)

    static let screenTitle = Font.system(.title, weight: .semibold)
    static let sectionTitle = Font.system(.headline, weight: .semibold)
    static let cardTitle = Font.system(.subheadline, weight: .semibold)

    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body, weight: .medium)
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.caption)

    /// Times and durations. Monospaced digits stop a ticking clock from making
    /// the layout jitter.
    static let timestamp = Font.system(.subheadline, design: .default, weight: .regular)
        .monospacedDigit()
    static let statValue = Font.system(.title2, design: .rounded, weight: .semibold)
        .monospacedDigit()
}

enum SomnaSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Apple's minimum comfortable hit target. Interactive elements are never
    /// smaller than this, whatever the visual design suggests.
    static let minimumTapTarget: CGFloat = 44
}

enum SomnaRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let capsule: CGFloat = 999
}
