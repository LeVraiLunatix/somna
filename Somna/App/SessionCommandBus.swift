import Foundation
import Observation

/// A command that reaches a running night from outside the app's own screens.
enum SessionCommand: Sendable, Equatable {
    /// The lock-screen button, or anything else that ends a night without the
    /// session screen being on display.
    case stopNight
}

/// Carries those commands to whoever owns the running session.
///
/// The lock-screen "End the night" button is handled while Somna is in the
/// background, by the notification delegate — nowhere near the screen that
/// started the session. The delegate could stop the recording itself, and that
/// is exactly what it must not do: a night can already end by button, by alarm,
/// by dead battery, by full disk. Each of those paths cancels the alarm, closes
/// the file, runs the morning analysis. A fifth path written separately would be
/// a fifth chance to forget one of those steps, on the path nobody can watch
/// because it only runs at four in the morning with the screen off.
///
/// So the delegate posts a command, and `SessionStore` — which already owns
/// every other way a night ends — handles it the same way it handles the button.
@MainActor
@Observable
final class SessionCommandBus {

    private var listeners: [UUID: AsyncStream<SessionCommand>.Continuation] = [:]

    func send(_ command: SessionCommand) {
        for listener in listeners.values { listener.yield(command) }
    }

    /// Commands from now on. A method, not a property: it registers a listener.
    ///
    /// Nothing is buffered. A stop that arrives when no night is running is not
    /// a stop to replay against the next one — it is a button pressed on a
    /// notification that outlived what it referred to.
    func stream() -> AsyncStream<SessionCommand> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.listeners[id] = nil }
            }
        }
    }
}
