import SwiftUI

/// Top of the view hierarchy.
///
/// Decides between onboarding and the app, and owns the single navigation stack.
/// Still no tab bar: History, Trends and Settings arrive in Phase 4C, and
/// shipping a tab bar with three empty tabs would put dead ends in front of a
/// beta tester on day one.
struct RootView: View {

    @Environment(\.somna) private var environment
    @State private var router = AppRouter()
    /// Owned here rather than per screen: playback has to survive navigation, or
    /// comparing three events would mean restarting the audio on every scroll.
    @State private var player = ClipPlayer()
    @State private var hasCompletedOnboarding: Bool?

    var body: some View {
        Group {
            switch hasCompletedOnboarding {
            case .none:
                // Settings are read synchronously from UserDefaults, so this is
                // one frame at most — no spinner, which would flash and look
                // like a stutter.
                Color.clear
            case .some(false):
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            case .some(true):
                mainApp
                    .transition(.opacity)
            }
        }
        .task {
            if hasCompletedOnboarding == nil {
                hasCompletedOnboarding = environment.settings.load().hasCompletedOnboarding
            }
            await recoverInterruptedNights()
        }
        .somnaAnimation(value: hasCompletedOnboarding)
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
            // Not reachable: `AppTab.available` excludes it until the charts exist.
            SettingsView()
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

    /// Reconciles nights the app died in the middle of, and clears files that
    /// nothing references any more.
    ///
    /// Runs at launch rather than on demand because the user has no way to know
    /// it is needed: a session row stuck in `recording` looks like a night that
    /// is still going, forever.
    private func recoverInterruptedNights() async {
        let useCase = RecoverInterruptedSessionsUseCase(
            sessions: environment.sessions,
            files: environment.files,
            clock: environment.clock
        )
        // Failure here is not worth blocking launch over: it retries next time,
        // and nothing the user can see depends on it having happened yet.
        try? await useCase()
    }

    /// Appearance follows the user's setting, and `nil` means "follow iOS".
    private var colorScheme: ColorScheme? {
        switch environment.settings.load().theme {
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
#Preview("Onboarding") {
    RootView()
        .environment(\.somna, .preview(microphone: .undetermined, notifications: .undetermined))
}

#Preview("Main app") {
    RootView()
        .environment(\.somna, .preview(settings: {
            var settings = UserSettings.default
            settings.hasCompletedOnboarding = true
            return settings
        }()))
}
#endif
