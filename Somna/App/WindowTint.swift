import SwiftUI
import UIKit

/// Pushes the chosen accent down into UIKit.
///
/// `.tint` covers SwiftUI's own controls, which is why the tab bar and the
/// buttons turned amber the moment Dawn was picked. A `Form` row's picker is not
/// one of them: it draws its value through a UIKit list cell, which reads the
/// **window's** `tintColor` — and that starts life as the compiled `AccentColor`
/// asset. That asset is Midnight. So "Follow iOS" and "7 days" stayed Midnight
/// blue on a screen that had otherwise gone amber, showing two accents at once,
/// one of which nobody had chosen.
///
/// The asset cannot be dynamic; it is baked at build time and there is one of
/// it. Setting the window tint is what carries the choice into the parts SwiftUI
/// hands to UIKit — the picker values, and the menus they present.
private struct WindowTint: ViewModifier {

    let palette: ThemePalette

    func body(content: Content) -> some View {
        content.onChange(of: palette, initial: true) { apply() }
    }

    @MainActor
    private func apply() {
        // `UIColor(_:)` keeps the underlying dynamic provider, so the tint still
        // resolves per light/dark and per Increase Contrast rather than freezing
        // whichever appearance happened to be current when it was picked.
        let colour = UIColor(palette.accentPrimary)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = colour
            }
        }
    }
}

extension View {
    /// Applies `palette` to SwiftUI **and** to the UIKit windows underneath it.
    func somnaTint(_ palette: ThemePalette) -> some View {
        tint(palette.accentPrimary).modifier(WindowTint(palette: palette))
    }
}
