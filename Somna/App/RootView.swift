import SwiftUI

/// Top of the view hierarchy.
///
/// Deliberately a single screen rather than a tab bar with three empty tabs.
/// Shipping placeholder tabs would put dead ends in front of a beta tester on
/// day one; the tab bar arrives in Phase 4 together with the screens that fill it.
struct RootView: View {

    @Environment(\.somna) private var environment
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: router.path(for: .home)) {
            SystemStatusView()
                .navigationDestination(for: AppDestination.self) { destination in
                    // Every case is routed the moment its screen exists. Until
                    // then the router simply cannot produce these destinations —
                    // there is no code path that pushes them.
                    switch destination {
                    default:
                        SystemStatusView()
                    }
                }
        }
        .environment(router)
        .tint(SomnaColor.accentPrimary)
        .preferredColorScheme(colorScheme)
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
#Preview {
    RootView()
        .environment(\.somna, .preview())
}
#endif
