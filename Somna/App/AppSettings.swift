import Foundation
import Observation

/// The app's settings, as observable state.
///
/// **Why this exists.** `SettingsRepository` persists; it does not notify.
/// Reading it with `settings.load()` inside a view body creates no observable
/// dependency, so SwiftUI never learns that anything changed. That is what made
/// the light theme unreachable: the Settings screen updated, the root view kept
/// rendering the old value until the next launch.
///
/// The bug was visible on the theme, but the defect was general — `RootView`
/// read `hasCompletedOnboarding` the same way, and every session read the
/// analysis sensitivity the same way. One observable owner fixes all three.
///
/// The repository stays underneath as the persistence layer. This is only the
/// layer that was missing above it.
@MainActor
@Observable
final class AppSettings {

    private(set) var settings: UserSettings

    private let repository: any SettingsStoring
    private let notifications: any NotificationScheduling
    private let appIcon: any AppIconSwitching

    init(
        repository: any SettingsStoring,
        notifications: any NotificationScheduling,
        appIcon: any AppIconSwitching = StubAppIconService()
    ) {
        self.repository = repository
        self.notifications = notifications
        self.appIcon = appIcon
        settings = repository.load()
    }

    /// Mutates, persists, and rebuilds the notification schedule.
    ///
    /// A single entry point rather than a settable property: every change has to
    /// reach the disk *and* the notification centre, and a plain `var` would let
    /// a caller update one without the other.
    func update(_ mutate: (inout UserSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        guard updated != settings else { return }

        settings = updated
        repository.save(updated)

        Task { await notifications.refresh(for: updated) }

        // The icon follows the accent, guarded because iOS shows a system alert
        // every time a change succeeds — a redundant call interrupts the user
        // for nothing.
        //
        // The predicate compares against the icon *currently installed* rather
        // than against the previous palette. It is the honest question ("is the
        // Home Screen already showing this?") and it self-corrects if the two
        // ever drift, which comparing palettes would not.
        if appIcon.currentIconName() != updated.palette.iconName {
            Task { await appIcon.apply(updated.palette) }
        }
    }

    /// Convenience for the one flag that is set from outside the Settings screen.
    func markOnboardingComplete() {
        update { $0.hasCompletedOnboarding = true }
    }
}
