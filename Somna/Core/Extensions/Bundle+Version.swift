import Foundation

extension Bundle {

    /// The marketing version, e.g. `0.1.0`.
    ///
    /// Injected at build time from `MARKETING_VERSION`, which CI derives from
    /// the git tag. Falls back to `0.0.0` rather than crashing: a missing
    /// version is a packaging defect, never a reason to take the app down.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The build number, e.g. `142`.
    ///
    /// Injected from `CURRENT_PROJECT_VERSION`, which CI sets to the workflow
    /// run number so builds are strictly increasing and never collide.
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Human-readable version used in the Settings "About" section and in
    /// diagnostic exports, e.g. `0.1.0 (142)`.
    var displayVersion: String {
        "\(shortVersion) (\(buildNumber))"
    }
}
