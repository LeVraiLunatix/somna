import Foundation
import UIKit

/// What the battery is doing.
struct PowerState: Equatable, Sendable {
    /// 0–1, or `nil` when iOS will not report it (simulator, monitoring off).
    let level: Double?
    let isCharging: Bool
    let isLowPowerMode: Bool

    /// Below this, an unplugged eight-hour recording will not finish.
    ///
    /// Recording costs roughly 3–7 % per hour. At 30 % an unplugged phone dies
    /// somewhere around 04:00 — late enough that the user believes the night was
    /// recorded, early enough that most of it was not. That combination is worse
    /// than not starting at all.
    static let lowBatteryThreshold = 0.30

    var isSafeForOvernightRecording: Bool {
        if isCharging { return true }
        guard let level else { return true }
        return level >= Self.lowBatteryThreshold
    }
}

protocol PowerMonitoring: Sendable {
    @MainActor func snapshot() -> PowerState
}

/// Reads the real battery.
///
/// One of the few UIKit imports in the project: there is no SwiftUI equivalent,
/// and `ProcessInfo` only exposes Low Power Mode, not charge state.
struct DevicePowerMonitor: PowerMonitoring {

    @MainActor
    func snapshot() -> PowerState {
        let device = UIDevice.current

        // Monitoring is off by default and reports -1 until enabled. Enabling it
        // here rather than at launch keeps the cost to the screens that ask.
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }

        let raw = Double(device.batteryLevel)
        let level = raw < 0 ? nil : raw

        return PowerState(
            level: level,
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

/// A fixed battery, for previews and tests.
struct StubPowerMonitor: PowerMonitoring {
    let state: PowerState

    init(level: Double? = 0.85, isCharging: Bool = true, isLowPowerMode: Bool = false) {
        state = PowerState(level: level, isCharging: isCharging, isLowPowerMode: isLowPowerMode)
    }

    @MainActor
    func snapshot() -> PowerState { state }
}
