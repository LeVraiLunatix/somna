import OSLog
import SwiftData
import SwiftUI
import UserNotifications

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

    /// Lives as long as the app does.
    ///
    /// A running night outlives whatever screen started it — the phone is
    /// locked, the user is asleep — so its state cannot belong to a view.
    @State private var session: SessionStore

    /// One bus for the whole app, so the lock-screen button reaches the running
    /// session wherever the user happens to have left the UI.
    @State private var commands = SessionCommandBus()

    /// Held, not just assigned: `UNUserNotificationCenter.delegate` is a weak
    /// reference, and a delegate nobody retains is a stop button that silently
    /// stops working.
    @State private var notificationDelegate: NotificationActionHandler?

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
                notifications: environment.notifications,
                appIcon: environment.appIcon
            )
        )
        _session = State(initialValue: SessionStore(environment: environment))
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
            .environment(commands)
            .environment(session)
            // Subscribed here rather than from the session screen: the
            // lock-screen stop button is pressed with no screen on display, and
            // a listener that lives on a view is a listener that is not there
            // when it matters. The command was silently dropped, the night ran
            // on unstopped, and the report showed 0:00 beside audio that was on
            // disk.
            .task { await session.observeCommands(commands) }
            .task {
                guard notificationDelegate == nil else { return }
                let bus = commands
                let handler = NotificationActionHandler {
                    Task { @MainActor in bus.send(.stopNight) }
                }
                notificationDelegate = handler

                let center = UNUserNotificationCenter.current()
                center.delegate = handler
                // Registered at launch, not when a night starts: iOS matches a
                // notification against the categories known when it is
                // delivered, so a late registration yields a notification with
                // no buttons on it.
                center.setNotificationCategories([NightControlNotification.category])
            }
        }
    }
}
