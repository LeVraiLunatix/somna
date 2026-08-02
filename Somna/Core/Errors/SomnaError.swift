import Foundation

/// Root error type.
///
/// Every case carries enough information for the UI to offer a concrete next
/// step. An error the user cannot act on is a bug in this enum, not a valid
/// state: `recoverySuggestion` is non-optional by design.
enum SomnaError: Error, Equatable, Sendable {

    /// A dependency was used before `RootView` injected the real environment.
    /// Only reachable through a programming mistake; surfaced rather than
    /// crashed so a preview or a misplaced view degrades instead of trapping.
    case environmentNotConfigured(component: String)

    /// The persistent store could not be opened or migrated.
    case persistenceUnavailable(underlying: String)

    /// A night referenced by the UI no longer exists.
    case sessionNotFound(id: UUID)

    /// Recording cannot start because too little space is left.
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)

    /// The microphone permission is not granted.
    case microphoneAccessDenied

    /// A file on disk is missing, truncated or unreadable.
    case corruptedFile

    /// A session ended with too little usable audio to analyse.
    case recordingTooShort(recorded: TimeInterval, minimum: TimeInterval)
}

extension SomnaError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .environmentNotConfigured:
            String(localized: "error.environment.title",
                   defaultValue: "Somna is not ready yet")
        case .persistenceUnavailable:
            String(localized: "error.persistence.title",
                   defaultValue: "Your nights could not be opened")
        case .sessionNotFound:
            String(localized: "error.sessionNotFound.title",
                   defaultValue: "This night is no longer available")
        case .insufficientStorage:
            String(localized: "error.storage.title",
                   defaultValue: "Not enough space to record")
        case .microphoneAccessDenied:
            String(localized: "error.microphone.title",
                   defaultValue: "Somna cannot hear anything")
        case .corruptedFile:
            String(localized: "error.corruptedFile.title",
                   defaultValue: "A recording could not be read")
        case .recordingTooShort:
            String(localized: "error.tooShort.title",
                   defaultValue: "This session was too short to analyse")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .environmentNotConfigured:
            String(localized: "error.environment.suggestion",
                   defaultValue: "Close and reopen Somna. If it happens again, please report it.")
        case .persistenceUnavailable:
            String(localized: "error.persistence.suggestion",
                   defaultValue: "Reopen Somna. Your recordings are still on the device and can be recovered.")
        case .sessionNotFound:
            String(localized: "error.sessionNotFound.suggestion",
                   defaultValue: "It may have been deleted. Pull to refresh your history.")
        case .insufficientStorage:
            String(localized: "error.storage.suggestion",
                   defaultValue: "Free up space, or delete older nights from Settings.")
        case .microphoneAccessDenied:
            String(localized: "error.microphone.suggestion",
                   defaultValue: "Allow microphone access for Somna in iOS Settings.")
        case .corruptedFile:
            String(localized: "error.corruptedFile.suggestion",
                   defaultValue: "The rest of the night is unaffected. This clip has been skipped.")
        case .recordingTooShort:
            String(localized: "error.tooShort.suggestion",
                   defaultValue: "Somna needs a few minutes of audio before it can detect anything.")
        }
    }
}
