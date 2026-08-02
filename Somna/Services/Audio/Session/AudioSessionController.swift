import AVFoundation
import Foundation
import OSLog

/// Owns `AVAudioSession` for recording.
///
/// Recording continues with the screen locked and the app in the background
/// because `UIBackgroundModes` declares `audio` and this session stays active.
/// That is the entire mechanism — there is no trick involved, and no trick is
/// used: no silent playback loop, no misuse of the location background mode.
struct AudioSessionController: Sendable {

    /// Configures and activates the session for an overnight recording.
    func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            // `.record` rather than `.playAndRecord`: Somna plays nothing during
            // a session, and the narrower category is less likely to be preempted.
            //
            // `.default` mode rather than `.measurement`: unlike calibration,
            // an eight-hour recording benefits from the input processing iOS
            // applies, and the levels are compared against the calibration floor
            // rather than used as absolute measurements.
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            Log.audio.error("Recording session could not be activated")
            throw AudioError.sessionUnavailable
        }
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            // Deactivation failing does not endanger anything already written.
            Log.audio.info("Session deactivation reported an error; recorded audio is unaffected")
        }
    }

    /// Whether another app currently holds the input.
    var isInputAvailable: Bool {
        AVAudioSession.sharedInstance().isInputAvailable
    }
}

/// Turns the audio notifications iOS posts into recording events.
///
/// Delivered as one stream so the engine has a single place to react, and so the
/// ordering between an interruption and a media-services reset is preserved
/// rather than depending on which observer fired first.
enum AudioSessionEvents {

    static func stream(clock: any Clocking) -> AsyncStream<RecordingEvent> {
        AsyncStream { continuation in
            let center = NotificationCenter.default

            let interruptions = Task {
                for await notification in center.notifications(named: AVAudioSession.interruptionNotification) {
                    guard let event = interruptionEvent(from: notification, clock: clock) else { continue }
                    continuation.yield(event)
                }
            }

            let resets = Task {
                for await _ in center.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                    // Every audio object is now invalid. The engine must be
                    // rebuilt from scratch, not restarted.
                    Log.audio.error("Media services were reset; rebuilding the engine")
                    continuation.yield(.mediaServicesReset(at: clock.now))
                }
            }

            let routes = Task {
                for await notification in center.notifications(named: AVAudioSession.routeChangeNotification) {
                    logRouteChange(notification)
                }
            }

            continuation.onTermination = { _ in
                interruptions.cancel()
                resets.cancel()
                routes.cancel()
            }
        }
    }

    private static func interruptionEvent(
        from notification: Notification,
        clock: any Clocking
    ) -> RecordingEvent? {
        guard
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return nil }

        switch type {
        case .began:
            Log.audio.info("Audio interrupted")
            return .interruptionBegan(at: clock.now)

        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume = options.contains(.shouldResume)

            Log.audio.info("Interruption ended, system hint to resume: \(shouldResume, privacy: .public)")
            return .interruptionEnded(shouldResume: shouldResume)

        @unknown default:
            return nil
        }
    }

    /// Route changes do not stop a recording, but they change what is being
    /// recorded — headphones becoming the input is a different microphone, at a
    /// different distance from the bed. Logged so the quality assessment can
    /// explain a night that suddenly went quiet.
    private static func logRouteChange(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override:
            Log.audio.info("Audio route changed, reason \(raw, privacy: .public)")
        default:
            break
        }
    }
}
