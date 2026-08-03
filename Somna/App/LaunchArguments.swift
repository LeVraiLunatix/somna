#if DEBUG
import Foundation

/// Test-only entry points into the app's starting state.
///
/// `#if DEBUG` so none of this exists in a build a tester installs. UI tests run
/// against the Debug configuration, which is where they are needed.
///
/// The alternative — driving onboarding from every accessibility test — would
/// mean each audit spent thirty seconds tapping through seven screens before
/// reaching the one it came to check, and would fail for reasons that have
/// nothing to do with what it is testing.
enum LaunchArguments {

    /// Starts on the main app rather than on onboarding.
    static let skipOnboarding = "-somna-skip-onboarding"

    /// Clears stored settings before launch, so a test starts from a known state.
    static let resetSettings = "-somna-reset"

    /// Skips the private-beta gate. UI tests are not testers.
    static let skipGate = "-somna-skip-gate"

    static var isSkippingOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(skipOnboarding)
    }

    static var isResettingSettings: Bool {
        ProcessInfo.processInfo.arguments.contains(resetSettings)
    }

    static var isSkippingGate: Bool {
        ProcessInfo.processInfo.arguments.contains(skipGate)
    }

    /// Applies whatever the launch arguments ask for.
    static func apply(to settings: any SettingsStoring) {
        if isResettingSettings {
            settings.save(.default)
        }
        if isSkippingOnboarding {
            var current = settings.load()
            current.hasCompletedOnboarding = true
            settings.save(current)
        }
        if isSkippingGate || isSkippingOnboarding {
            // Skipping onboarding implies skipping the gate: a test that asked
            // to start inside the app did not mean "inside the app, behind a
            // password field".
            var current = settings.load()
            current.hasUnlockedBeta = true
            settings.save(current)
        }
    }
}
#endif
