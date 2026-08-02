import SwiftUI

/// Every destination the app can navigate to.
///
/// A closed enum rather than free-form `NavigationLink` destinations: it makes
/// the navigation graph reviewable, gives deep links one place to resolve, and
/// means a screen can be reached from a notification without the sending code
/// knowing how it is built.
enum AppDestination: Hashable, Sendable {
    case nightReport(sessionID: UUID)
    case timeline(sessionID: UUID)
    case history
    case trends
    case settings
    case storage
    case privacy
    case calibration
    case premium
}

/// The top-level sections.
enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home
    case history
    case trends
    case settings

    var symbolName: String {
        switch self {
        case .home: "moon.stars"
        case .history: "calendar"
        case .trends: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }
}

/// Navigation state.
///
/// One path per tab. A shared path would make switching tabs reset where the
/// user was, which is the single most irritating navigation bug in a tabbed app.
@MainActor
@Observable
final class AppRouter {

    var selectedTab: AppTab = .home
    var paths: [AppTab: [AppDestination]] = [:]

    /// A sheet presented above everything, used by the audio player and by
    /// destructive confirmations.
    var presentedSheet: AppDestination?

    func push(_ destination: AppDestination, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        paths[target, default: []].append(destination)
    }

    func popToRoot(in tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    func path(for tab: AppTab) -> Binding<[AppDestination]> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? [] },
            set: { [weak self] newValue in self?.paths[tab] = newValue }
        )
    }

    /// Jumps straight to a night, from a notification or from history.
    ///
    /// Resets the target tab first so the user does not end up several screens
    /// deep in a stack they never built.
    func showNightReport(sessionID: UUID) {
        selectedTab = .home
        paths[.home] = [.nightReport(sessionID: sessionID)]
    }
}
