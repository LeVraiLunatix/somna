import OSLog
import SwiftData
import SwiftUI

/// Application entry point and composition root.
///
/// The only place that knows about concrete implementations: everything below
/// receives protocols through ``AppEnvironment``.
@main
struct SomnaApp: App {

    private let environment: AppEnvironment
    private let startupError: SomnaError?

    /// Created once, here, so every screen observes the same settings.
    @State private var settings: AppSettings

    init() {
        // Building the container is the one thing that can fail before any UI
        // exists. It is caught rather than allowed to trap: a beta tester whose
        // store is corrupt still needs a working Settings screen so they can
        // erase their data and carry on, and a crash on launch gives them nothing.
        do {
            let container = try ModelContainerFactory.makeContainer()
            environment = .live(modelContainer: container)
            startupError = nil

            #if DEBUG
            LaunchArguments.apply(to: environment.settings)
            #endif
        } catch let error as SomnaError {
            Log.app.fault("Launching in degraded mode: persistence unavailable")
            environment = .unconfigured
            startupError = error
        } catch {
            Log.app.fault("Launching in degraded mode: unexpected persistence failure")
            environment = .unconfigured
            startupError = .persistenceUnavailable(underlying: String(describing: type(of: error)))
        }

        // Built from the resolved environment, so it reads the same repository
        // the rest of the app writes to — including in degraded mode, where the
        // Settings screen still has to work well enough to erase data.
        _settings = State(
            initialValue: AppSettings(
                repository: environment.settings,
                notifications: environment.notifications
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let startupError {
                    ErrorStateView(error: startupError, retry: nil)
                        .background(SomnaColor.backgroundPrimary)
                } else {
                    RootView()
                }
            }
            .environment(\.somna, environment)
            .environment(settings)
        }
    }
}
