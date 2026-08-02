import Foundation

/// Why a session ended.
///
/// Recorded on the night so the report can explain what happened, and so
/// "stopped by the user" is never confused with "iOS killed us".
enum StopReason: String, Equatable, Sendable, Codable {
    case userRequested
    case batteryCritical
    case diskFull
    case appTerminating
    /// An interruption that never handed control back.
    case interruptionNotResolved
}

/// Where a recording is.
///
/// `interrupted` and `resuming` both carry the instant the interruption began,
/// because the timeline needs the gap's real duration — a gap shown as a moment
/// rather than as twenty minutes would make a broken night look intact. Carrying
/// it through `resuming` means a failed resume returns to the *original* gap
/// rather than inventing a new one.
enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case interrupted(since: Date)
    case resuming(since: Date)
    case stopping(reason: StopReason)
    case stopped(reason: StopReason)
    case failed(AudioError)
}

/// What can happen to a recording.
enum RecordingEvent: Equatable, Sendable {
    case start
    case engineStarted
    case interruptionBegan(at: Date)
    /// iOS tells us whether it thinks resuming is appropriate. It is a hint, not
    /// a guarantee: the flag is routinely absent after long interruptions such as
    /// a phone call, even when resuming would work.
    case interruptionEnded(shouldResume: Bool)
    case engineResumed
    /// The media daemon restarted; every audio object is now invalid.
    case mediaServicesReset(at: Date)
    case stopRequested(reason: StopReason)
    case engineStopped
    case failure(AudioError)
}

/// Transitions, as a pure function.
///
/// Extracted from the engine on purpose. Interruption handling is the part of
/// Somna most likely to lose someone's night, and it is also the part that
/// cannot be reproduced on a CI runner: no phone calls, no Siri, no media
/// daemon crashes. Keeping the rules pure means they can be tested exhaustively
/// even though the hardware they describe is unavailable.
enum RecordingStateMachine {

    /// - Returns: the next state, or `nil` when the event does not apply and
    ///   should be ignored rather than treated as an error. Audio notifications
    ///   arrive out of order and in duplicate; treating every unexpected one as
    ///   a failure would end nights that were fine.
    static func next(from state: RecordingState, on event: RecordingEvent) -> RecordingState? {
        switch (state, event) {

        case (.idle, .start):
            return .starting

        case (.starting, .engineStarted):
            return .recording

        // An interruption arriving while starting still counts: iOS can preempt
        // between activating the session and the engine reporting ready.
        case (.starting, .interruptionBegan(let date)),
             (.recording, .interruptionBegan(let date)):
            return .interrupted(since: date)

        case (.interrupted(let since), .interruptionEnded):
            // Somna attempts to resume even when iOS omits the `shouldResume`
            // hint. The worst case is a restart that fails, which is recoverable;
            // honouring a hint that is routinely absent would abandon nights that
            // could have continued.
            return .resuming(since: since)

        case (.resuming, .engineResumed):
            return .recording

        // A failed resume returns to the original gap rather than to `.failed`:
        // the segments written so far are intact, another interruption-ended
        // notification may still arrive, and the night is not over.
        case (.resuming(let since), .failure):
            return .interrupted(since: since)

        // The media daemon can restart at any point, invalidating every audio
        // object. Modelled as an interruption because the recovery path — rebuild
        // the engine, open a new segment — is identical.
        case (.starting, .mediaServicesReset(let date)),
             (.recording, .mediaServicesReset(let date)):
            return .interrupted(since: date)

        case (.resuming(let since), .mediaServicesReset):
            return .interrupted(since: since)

        case (_, .stopRequested(let reason)):
            // Stopping is always allowed from an active state, and never from a
            // terminal one — a second stop must not resurrect a finished session.
            return state.isActive ? .stopping(reason: reason) : nil

        case (.stopping(let reason), .engineStopped):
            return .stopped(reason: reason)

        case (.starting, .failure(let error)),
             (.recording, .failure(let error)):
            return .failed(error)

        default:
            return nil
        }
    }
}

extension RecordingState {

    /// Whether audio is being captured right now.
    var isCapturing: Bool {
        if case .recording = self { return true }
        return false
    }

    /// Whether the session is still alive, even if not currently capturing.
    ///
    /// An interrupted session is *not* over: it holds usable segments and may
    /// still resume.
    var isActive: Bool {
        switch self {
        case .starting, .recording, .interrupted, .resuming, .stopping: true
        case .idle, .stopped, .failed: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .stopped, .failed: true
        case .idle, .starting, .recording, .interrupted, .resuming, .stopping: false
        }
    }

    /// When the current interruption began, if there is one.
    var interruptedSince: Date? {
        switch self {
        case .interrupted(let since), .resuming(let since): since
        default: nil
        }
    }

    /// How the night should be recorded in the database once it ends.
    ///
    /// Only a deliberate stop produces a night ready for analysis. Everything
    /// else is `interrupted`, which keeps the audio and lets the user decide —
    /// rather than `failed`, which reads as "your night is gone".
    var resultingSessionStatus: NightSessionStatus {
        switch self {
        case .stopped(let reason):
            reason == .userRequested ? .awaitingAnalysis : .interrupted
        case .failed:
            .interrupted
        case .idle, .starting, .recording, .interrupted, .resuming, .stopping:
            .recording
        }
    }
}
