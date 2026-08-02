import Foundation

/// Haptic vocabulary, expressed as events rather than as intensities.
///
/// Callers say *what happened*, never *how it should feel*. That keeps the
/// physical language of the app consistent, and means retuning it later is one
/// edit rather than a search across every screen.
enum HapticEvent: Sendable {
    case sessionStarted
    case sessionStopped
    case calibrationFinished
    case eventSelected
    case deletionConfirmed
    case errorOccurred
}

/// Plays haptics.
///
/// Injected as a protocol so tests and previews are silent, and so the whole
/// channel can be disabled from one place.
protocol HapticFeedbacking: Sendable {
    func play(_ event: HapticEvent)
}

/// Haptics disabled. Used by previews, tests, and any context where feedback
/// would be meaningless.
struct SilentHapticFeedback: HapticFeedbacking {
    func play(_ event: HapticEvent) {}
}
