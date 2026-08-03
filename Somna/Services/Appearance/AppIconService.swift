import Foundation
import OSLog
import UIKit

/// Swaps the home-screen icon to match the chosen palette.
///
/// `setAlternateIconName` needs no entitlement and no paid account, so it works
/// under sideloading. The variants live in the asset catalogue and are declared
/// in `project.yml`; the mark itself never changes, only the colour of its arcs
/// and the night behind them, so the icon stays recognisable as Somna whichever
/// one is picked.
protocol AppIconSwitching: Sendable {
    @MainActor func currentIconName() -> String?
    @MainActor func apply(_ palette: ThemePalette) async
}

struct AppIconService: AppIconSwitching {

    @MainActor
    func currentIconName() -> String? {
        UIApplication.shared.alternateIconName
    }

    @MainActor
    func apply(_ palette: ThemePalette) async {
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let target = palette.iconName
        // iOS shows a system alert on every successful change, so a redundant
        // call is not merely wasteful — it interrupts the user for nothing.
        guard target != UIApplication.shared.alternateIconName else { return }

        do {
            try await UIApplication.shared.setAlternateIconName(target)
            Log.ui.info("App icon changed to \(target ?? "default", privacy: .public)")
        } catch {
            // Never worth surfacing: the palette still applied everywhere inside
            // the app, and an icon that did not change is a cosmetic shortfall,
            // not a failure of anything the user asked for.
            Log.ui.error("App icon could not be changed")
        }
    }
}

/// An icon that never changes, for previews and tests.
struct StubAppIconService: AppIconSwitching {
    @MainActor func currentIconName() -> String? { nil }
    @MainActor func apply(_ palette: ThemePalette) async {}
}
