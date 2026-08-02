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
        }
        .somnaAnimation(value: hasCompletedOnboarding)
        .tint(SomnaColor.accentPrimary)
        .preferredColorScheme(colorScheme)
    }

    private var mainApp: some View {
        NavigationStack(path: router.path(for: .home)) {
            HomeView(
                // Recording lands in Phase 5; until then Home says so rather
                // than offering a button that does nothing.
                onStartSession: nil,
                onShowDiagnostics: { router.push(.storage, in: .home) }
            )
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .storage:
                    SystemStatusView()
                default:
                    // Unreachable: no code path pushes the other destinations
                    // until their screens exist in Phase 4B and 4C.
                    SystemStatusView()
                }
            }
        }
        .environment(router)
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
