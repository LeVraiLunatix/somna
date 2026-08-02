import UIKit

/// Real haptics, via `UIFeedbackGenerator`.
///
/// One of only two files allowed to import UIKit (the other is `SomnaColor`):
/// SwiftUI's `sensoryFeedback` is view-bound, and Somna needs to acknowledge
/// events that originate in a service — a session ending because iOS interrupted
/// it, for instance — with no view involved.
///
/// `@MainActor` because `UIFeedbackGenerator` requires it. `play` is nonisolated
/// and hops, so callers on any actor can fire and forget: a haptic is never
/// worth making an audio engine wait.
struct LiveHapticFeedback: HapticFeedbacking {

    nonisolated func play(_ event: HapticEvent) {
        Task { @MainActor in
            Self.perform(event)
        }
    }

    @MainActor
    private static func perform(_ event: HapticEvent) {
        switch event {
        case .sessionStarted:
            // Softer than the stop: starting a night should feel like settling,
            // not like a confirmation dialog.
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        case .sessionStopped:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .calibrationFinished:
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .eventSelected:
            UISelectionFeedbackGenerator().selectionChanged()

        case .deletionConfirmed:
            // Warning rather than success: deletion is irreversible, and the
            // hand should register that even when the eyes have moved on.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)

        case .errorOccurred:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
