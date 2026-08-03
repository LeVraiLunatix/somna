import AlarmKit
import Foundation
import OSLog
import SwiftUI

/// Metadata attached to Somna's alarms.
///
/// Empty, but required as AlarmKit's generic parameter. `nonisolated` because
/// the framework needs it outside the main actor.
nonisolated struct SomnaAlarmMetadata: AlarmMetadata {}

/// The wake alarm, via AlarmKit.
///
/// **Why AlarmKit and not a notification.** A `UNNotification` is silenced by
/// Focus and by the ring switch. Calling that "an alarm" would be exactly the
/// kind of overclaim this app refuses everywhere else — and the notification
/// bug found in the first beta proved the risk is not theoretical. AlarmKit is
/// the framework that actually rings through both.
///
/// **No paid account, and no widget extension.** AlarmKit needs only the
/// `NSAlarmKitUsageDescription` key and a runtime authorisation, so it works on
/// a free Apple account with sideloading. A widget extension is required only
/// for countdown presentations; a fixed-time alarm uses the system's own alert,
/// which already carries a stop button.
struct WakeAlarmService: WakeAlarmScheduling {

    func permission() async -> WakeAlarmPermission {
        switch AlarmManager.shared.authorizationState {
        case .notDetermined: .undetermined
        case .authorized: .granted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestPermission() async -> WakeAlarmPermission {
        guard await permission() == .undetermined else { return await permission() }

        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized ? .granted : .denied
        } catch {
            Log.notifications.error("Alarm authorisation request failed")
            return .denied
        }
    }

    func schedule(id: UUID, at date: Date, title: String, stopButtonTitle: String) async throws {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(
                text: LocalizedStringResource(stringLiteral: stopButtonTitle),
                textColor: .white,
                systemImageName: "stop.circle"
            )
        )

        let attributes = AlarmAttributes<SomnaAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Color(uiColor: UIColor(rgb: 0x6B8CF2))
        )

        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(date),
            attributes: attributes
        )

        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        Log.audio.info("Wake alarm scheduled for \(Log.short(id), privacy: .public)")
    }

    func cancel(id: UUID) async {
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            // Cancelling an alarm that already fired, or was never scheduled,
            // is not worth surfacing: the outcome the caller wanted is the case.
            Log.audio.info("Wake alarm cancellation had nothing to cancel")
        }
    }
}

/// An alarm that never rings, for previews and tests.
struct StubWakeAlarmService: WakeAlarmScheduling {
    let permissionState: WakeAlarmPermission

    init(permission: WakeAlarmPermission = .granted) {
        permissionState = permission
    }

    func permission() async -> WakeAlarmPermission { permissionState }
    func requestPermission() async -> WakeAlarmPermission { permissionState }
    func schedule(id: UUID, at date: Date, title: String, stopButtonTitle: String) async throws {}
    func cancel(id: UUID) async {}
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
