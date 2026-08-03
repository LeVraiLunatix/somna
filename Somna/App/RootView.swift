import SwiftUI

/// Top of the view hierarchy.
///
/// Decides between onboarding and the app, and owns the single navigation stack.
/// Still no tab bar: History, Trends and Settings arrive in Phase 4C, and
/// shipping a tab bar with three empty tabs would put dead ends in front of a
/// beta tester on day one.
struct RootView: View {

    @Environment(\.somna) private var environment
    @Environment(AppSettings.self) private var settings
    @State private var router = AppRouter()
    /// Owned here rather than per screen: playback has to survive navigation, or
    /// comparing three events would mean restarting the audio on every scroll.
    @State private var player = ClipPlayer()
    @State private var hasLaunched = false

    var body: some View {
        Group {
            if !hasLaunched {
                // The launch sequence owns the startup work it covers, so the
                // two cannot drift apart — a progress bar that outlives its task
                // is the kind of theatre this app refuses.
                LaunchView { hasLaunched = true }
            } else if settings.settings.hasCompletedOnboarding {
                mainApp.transition(.opacity)
            } else {
                OnboardingView().transition(.opacity)
            }
        }
        .somnaAnimation(value: hasLaunched)
        .somnaAnimation(value: settings.settings.hasCompletedOnboarding)
        .tint(SomnaColor.accentPrimary)
        .preferredColorScheme(colorScheme)
    }

    private var mainApp: some View {
        TabView(selection: Bindable(router).selectedTab) {
            ForEach(AppTab.available, id: \.self) { tab in
                Tab(title(for: tab), systemImage: tab.symbolName, value: tab) {
                    NavigationStack(path: router.path(for: tab)) {
                        screen(for: tab)
                            .navigationDestination(for: AppDestination.self, destination: destination)
                    }
                }
            }
        }
        .withPlaybackPanel()
        .environment(router)
        .environment(player)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                onStartSession: { router.push(.session, in: .home) },
                onShowDiagnostics: { router.push(.storage, in: .home) },
                onOpenNight: { router.push(.nightReport(sessionID: $0), in: .home) }
            )
        case .history:
            HistoryView(
                onOpenNight: { router.push(.nightReport(sessionID: $0), in: .history) },
                onStartSession: {
                    router.selectedTab = .home
                    router.push(.session, in: .home)
                }
            )
        case .settings:
            SettingsView()
        case .trends:
            TrendsView()
        }
    }

    @ViewBuilder
    private func destination(_ destination: AppDestination) -> some View {
        switch destination {
        case .session:
            SessionView()
        case .nightReport(let sessionID):
            NightReportView(sessionID: sessionID) {
                router.push(.timeline(sessionID: sessionID), in: router.selectedTab)
            }
        case .timeline(let sessionID):
            TimelineView(sessionID: sessionID)
        case .storage:
            SystemStatusView()
        case .premium:
            PremiumView()
        default:
            SystemStatusView()
        }
    }

    private func title(for tab: AppTab) -> String {
        switch tab {
        case .home: String(localized: "tab.home", defaultValue: "Tonight")
        case .history: String(localized: "tab.history", defaultValue: "Nights")
        case .trends: String(localized: "tab.trends", defaultValue: "Trends")
        case .settings: String(localized: "tab.settings", defaultValue: "Settings")
        }
    }

    /// Appearance follows the user's setting, and `nil` means "follow iOS".
    ///
    /// Read from the observable store, not from the repository: a plain
    /// `load()` here created no dependency, which is exactly why choosing the
    /// light theme used to change nothing.
    private var colorScheme: ColorScheme? {
        switch settings.settings.theme {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

#if DEBUG
// Previews are compiled into Release builds too, so they must not reach
// `AppEnvironment.preview()`, which is DEBUG-only on purpose: preview
// scaffolding has no business shipping in a beta.
@MainActor
private func previewRoot(_ environment: AppEnvironment) -> some View {
    RootView()
        .environment(\.somna, environment)
        .environment(AppSettings(
            repository: environment.settings,
            notifications: environment.notifications
        ))
}

#Preview("Onboarding") {
    previewRoot(.preview(microphone: .undetermined, notifications: .undetermined))
}

#Preview("Main app") {
    previewRoot(.preview(settings: {
        var settings = UserSettings.default
        settings.hasCompletedOnboarding = true
        return settings
    }()))
}
#endif
