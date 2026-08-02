import SwiftUI

/// Application entry point.
///
/// - Note: This is the minimal build-validation version introduced by the
///   Phase 7 smoke test. Dependency injection (`AppEnvironment`), the SwiftData
///   model container and routing (`AppRouter`) are wired in Phase 3.
///   See `docs/01-PHASE-2-ARBORESCENCE.md`.
@main
struct SomnaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
