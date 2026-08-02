import Foundation

/// Failures in the audio layer.
///
/// Separate from ``SomnaError`` because these are the errors that appear at
/// 23:40 when someone is trying to start a night, and each one needs its own
/// concrete instruction. "Recording failed" is not an instruction.
enum AudioError: Error, Equatable, Sendable {

    /// `AVAudioSession` refused to activate — usually another app holds the input.
    case sessionUnavailable

    /// The input node reported no usable format. Happens on a simulator with no
    /// host microphone, and on a device where the input is held exclusively.
    case inputUnavailable

    case engineFailedToStart

    /// The session was interrupted and could not be resumed.
    case interruptedAndNotResumed
}

extension AudioError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            String(localized: "audio.sessionUnavailable.title",
                   defaultValue: "Somna could not access the microphone")
        case .inputUnavailable:
            String(localized: "audio.inputUnavailable.title",
                   defaultValue: "No microphone input available")
        case .engineFailedToStart:
            String(localized: "audio.engineFailed.title",
                   defaultValue: "Recording could not start")
        case .interruptedAndNotResumed:
            String(localized: "audio.interrupted.title",
                   defaultValue: "Recording was interrupted")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .sessionUnavailable:
            String(localized: "audio.sessionUnavailable.suggestion",
                   defaultValue: "Another app may be using the microphone. Close it and try again.")
        case .inputUnavailable:
            String(localized: "audio.inputUnavailable.suggestion",
                   defaultValue: "If headphones or an external microphone are connected, try disconnecting them.")
        case .engineFailedToStart:
            String(localized: "audio.engineFailed.suggestion",
                   defaultValue: "Try again. If it keeps happening, restart your iPhone.")
        case .interruptedAndNotResumed:
            String(localized: "audio.interrupted.suggestion",
                   defaultValue: "What was recorded before the interruption has been kept.")
        }
    }
}
