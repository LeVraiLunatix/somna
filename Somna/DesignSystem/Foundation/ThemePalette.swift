import SwiftUI
import UIKit

/// The accent a user picked.
///
/// **Only accents vary.** Backgrounds, surfaces and text stay as they are, for
/// two reasons. Their contrast ratios were measured against each other and
/// re-deriving four sets would mean four chances to ship something unreadable.
/// And Somna is looked at in a dark bedroom: a palette that lightens the page
/// is not a preference, it is a worse app at 3 a.m.
///
/// So personalisation changes the colour of what the app points at, never the
/// legibility of what it says.
enum ThemePalette: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The original. Night blue.
    case midnight
    /// Warm amber, for people who find blue too cold at night.
    case dawn
    /// Cool teal.
    case tide
    /// Almost no colour at all.
    case ink

    var id: String { rawValue }

    var accentPrimary: Color {
        switch self {
        case .midnight: Self.dynamic(light: 0x3153B8, dark: 0x6B8CF2,
                                     lightContrast: 0x1F3A8C, darkContrast: 0x9DB4FF)
        case .dawn: Self.dynamic(light: 0x9A5312, dark: 0xE0934A,
                                 lightContrast: 0x743C08, darkContrast: 0xF5B072)
        case .tide: Self.dynamic(light: 0x0F6B72, dark: 0x4FBEC6,
                                 lightContrast: 0x08494E, darkContrast: 0x7FD8DE)
        case .ink: Self.dynamic(light: 0x3A3A44, dark: 0xC4C4CE,
                                lightContrast: 0x1A1A20, darkContrast: 0xE6E6EC)
        }
    }

    var accentSecondary: Color {
        switch self {
        case .midnight: Self.dynamic(light: 0x6B4FB8, dark: 0xA78BF0,
                                     lightContrast: 0x4E3593, darkContrast: 0xC4AEFF)
        case .dawn: Self.dynamic(light: 0xA83A5B, dark: 0xE87E9C,
                                 lightContrast: 0x7F2640, darkContrast: 0xFCA3BB)
        case .tide: Self.dynamic(light: 0x2E7D5B, dark: 0x5CC49A,
                                 lightContrast: 0x1C5C41, darkContrast: 0x86DCB8)
        case .ink: Self.dynamic(light: 0x5C5C68, dark: 0x9E9EAB,
                                lightContrast: 0x3A3A44, darkContrast: 0xC4C4CE)
        }
    }

    /// Matches the icon variant declared in `project.yml`. `nil` means the
    /// primary icon, which is what `setAlternateIconName` expects.
    var iconName: String? {
        switch self {
        case .midnight: nil
        case .dawn: "AppIconDawn"
        case .tide: "AppIconTide"
        case .ink: "AppIconInk"
        }
    }

    /// The accent used to draw this palette's swatch in Settings.
    var swatch: Color { accentPrimary }

    private static func dynamic(
        light: UInt32, dark: UInt32, lightContrast: UInt32, darkContrast: UInt32
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let wantsContrast = traits.accessibilityContrast == .high
            return switch traits.userInterfaceStyle {
            case .light: UIColor(paletteRGB: wantsContrast ? lightContrast : light)
            default: UIColor(paletteRGB: wantsContrast ? darkContrast : dark)
            }
        })
    }
}

extension EnvironmentValues {
    /// Set once, at the root. Read wherever an accent is drawn.
    ///
    /// Passed through the environment rather than held in a mutable global:
    /// a colour that depends on hidden state is the kind of thing that works
    /// until two screens disagree about it.
    @Entry var somnaPalette: ThemePalette = .midnight
}

private extension UIColor {
    convenience init(paletteRGB rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
