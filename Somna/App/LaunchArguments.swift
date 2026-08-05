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


    static var isSkippingOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(skipOnboarding)
    }

    static var isResettingSettings: Bool {
        ProcessInfo.processInfo.arguments.contains(resetSettings)
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
    }
}
#endif
