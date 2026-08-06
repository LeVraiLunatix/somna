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
    ///
    /// Three decisions here, each of which was wrong once.
    ///
    /// **`.playAndRecord` rather than `.record`, for `.mixWithOthers`.** Somna
    /// still plays nothing during a session. But starting a `.record` session
    /// stops whatever else is playing, and `.mixWithOthers` — the option that
    /// says "do not silence anyone" — is only accepted on `.playAndRecord`,
    /// `.playback` and `.multiRoute`. Falling asleep to music is not an edge
    /// case; an app that kills it at the moment you settle is one people stop
    /// opening. The wider category is the price of not doing that.
    ///
    /// **`.allowBluetoothA2DP` and deliberately *not* `.allowBluetooth`.** The
    /// latter is the hands-free profile — the one used for phone calls. Allowing
    /// it lets iOS pull AirPods into HFP, which is mono and roughly telephone
    /// quality: the music someone fell asleep to would suddenly sound like a
    /// call. A2DP alone keeps playback at full quality.
    ///
    /// **`.default` mode rather than `.measurement`:** unlike calibration, an
    /// eight-hour recording benefits from the input processing iOS applies, and
    /// the levels are compared against the calibration floor rather than used as
    /// absolute measurements.
    func activateForRecording() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            Log.audio.error("Recording session could not be activated")
            throw AudioError.sessionUnavailable
        }

        preferBuiltInMicrophone(session)
    }

    /// Records the room, not the ear.
    ///
    /// With headphones connected, iOS would otherwise be free to take its input
    /// from them — so a night spent wearing AirPods would be a recording of the
    /// inside of someone's ear canal, from a microphone that leaves the bedroom
    /// whenever they do. The phone is the thing sitting still beside the bed all
    /// night, and its microphone is the one every calibration was measured
    /// against.
    ///
    /// Failure is logged and tolerated: recording from a less good microphone
    /// beats not recording.
    private func preferBuiltInMicrophone(_ session: AVAudioSession) {
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            Log.audio.info("No built-in microphone offered; keeping the default input")
            return
        }
        do {
            try session.setPreferredInput(builtIn)
        } catch {
            Log.audio.error("Could not select the built-in microphone; keeping the default input")
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
