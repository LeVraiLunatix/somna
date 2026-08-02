import SwiftUI
import UIKit

/// Semantic colour tokens.
///
/// **Why code and not an asset catalogue.** Somna needs four variants of every
/// colour — light, dark, and an increased-contrast version of each. Expressed as
/// asset catalogues that is roughly thirty JSON files whose relationships are
/// invisible in review: nothing stops "surface" drifting lighter than
/// "surfaceElevated" in dark mode only. Here the whole palette is one readable
/// file, and the contrast variants sit next to the colours they reinforce.
///
/// This is the only place in the project allowed to contain a hex value, and one
/// of only two places allowed to import UIKit (the other is haptics). `UIColor`'s
/// dynamic provider is used because SwiftUI has no equivalent that reacts to
/// `accessibilityContrast`.
///
/// Every token is named for its role, never its appearance. There is no
/// `darkGray`, because the day someone needs it lighter, the name lies.
enum SomnaColor {

    // MARK: - Surfaces

    /// The page behind everything. Near-black rather than pure black: OLED pure
    /// black makes scroll edges shimmer, and this app is looked at in the dark.
    static let backgroundPrimary = dynamic(
        light: 0xF7F7F9, dark: 0x08080A,
        lightContrast: 0xFFFFFF, darkContrast: 0x000000
    )

    /// Grouped sections and sheets.
    static let backgroundSecondary = dynamic(
        light: 0xEFEFF3, dark: 0x101014,
        lightContrast: 0xF2F2F2, darkContrast: 0x000000
    )

    /// Cards.
    static let surface = dynamic(
        light: 0xFFFFFF, dark: 0x17171C,
        lightContrast: 0xFFFFFF, darkContrast: 0x1F1F26
    )

    /// Cards that sit above other cards.
    static let surfaceElevated = dynamic(
        light: 0xFFFFFF, dark: 0x1F1F26,
        lightContrast: 0xFFFFFF, darkContrast: 0x2A2A33
    )

    static let separator = dynamic(
        light: 0xD8D8DE, dark: 0x2A2A33,
        lightContrast: 0x9A9AA2, darkContrast: 0x4A4A57
    )

    // MARK: - Text

    static let textPrimary = dynamic(
        light: 0x101014, dark: 0xF2F2F5,
        lightContrast: 0x000000, darkContrast: 0xFFFFFF
    )

    static let textSecondary = dynamic(
        light: 0x5C5C68, dark: 0x9E9EAB,
        lightContrast: 0x3A3A44, darkContrast: 0xC4C4CE
    )

    /// Reserved for genuinely incidental text. Anything a user needs in order to
    /// act must be at least `textSecondary`.
    static let textTertiary = dynamic(
        light: 0x8A8A96, dark: 0x6E6E7B,
        lightContrast: 0x5C5C68, darkContrast: 0x9E9EAB
    )

    // MARK: - Accents

    /// Night blue. Primary actions and the calmness indicator.
    static let accentPrimary = dynamic(
        light: 0x3153B8, dark: 0x6B8CF2,
        lightContrast: 0x1F3A8C, darkContrast: 0x9DB4FF
    )

    /// Restrained violet, for secondary emphasis only. Never used alone to carry
    /// meaning — see `Differentiate Without Color`.
    static let accentSecondary = dynamic(
        light: 0x6B4FB8, dark: 0xA78BF0,
        lightContrast: 0x4E3593, darkContrast: 0xC4AEFF
    )

    // MARK: - Status

    static let success = dynamic(
        light: 0x2E7D5B, dark: 0x5CC49A,
        lightContrast: 0x1C5C41, darkContrast: 0x86DCB8
    )

    static let warning = dynamic(
        light: 0x996515, dark: 0xD9A441,
        lightContrast: 0x724A0C, darkContrast: 0xF0C264
    )

    static let error = dynamic(
        light: 0xA83A3A, dark: 0xE0706E,
        lightContrast: 0x7F2626, darkContrast: 0xFF9694
    )

    // MARK: - Confidence

    /// Confidence is always carried by the wording first (see
    /// `NightEventPhrasing`). These tints only reinforce it, so that removing
    /// colour entirely loses nothing.
    static func confidence(_ level: EventConfidence) -> Color {
        switch level {
        case .high: textPrimary
        case .medium: textSecondary
        case .low: textTertiary
        }
    }

    // MARK: - Dynamic resolution

    private static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightContrast: UInt32,
        darkContrast: UInt32
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let wantsContrast = traits.accessibilityContrast == .high
            return switch traits.userInterfaceStyle {
            case .light:
                UIColor(rgb: wantsContrast ? lightContrast : light)
            default:
                UIColor(rgb: wantsContrast ? darkContrast : dark)
            }
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
