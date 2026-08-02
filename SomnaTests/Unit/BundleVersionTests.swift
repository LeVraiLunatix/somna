import Foundation
import Testing

@testable import Somna

/// Smoke tests introduced with the Phase 7 CI validation.
///
/// They deliberately assert on build-time injected values: if CI ever stops
/// propagating `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, the AltStore
/// feed would publish a build the app cannot identify, and these tests catch it
/// before a release is cut.
struct BundleVersionTests {

    @Test("The host bundle exposes a non-empty marketing version")
    func hostBundleExposesMarketingVersion() {
        #expect(!Bundle.main.shortVersion.isEmpty)
        #expect(Bundle.main.shortVersion != "0.0.0")
    }

    @Test("The host bundle exposes a non-empty build number")
    func hostBundleExposesBuildNumber() {
        #expect(!Bundle.main.buildNumber.isEmpty)
        #expect(Bundle.main.buildNumber != "0")
    }

    @Test("The display version combines both values")
    func displayVersionCombinesBothValues() {
        let expected = "\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))"
        #expect(Bundle.main.displayVersion == expected)
    }

    @Test("The bundle declares the audio background mode")
    func bundleDeclaresAudioBackgroundMode() throws {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let declared = try #require(modes, "UIBackgroundModes is missing from Info.plist")

        // Overnight recording is only possible because of this key, and Somna
        // must never silently acquire a second background mode.
        #expect(declared == ["audio"])
    }

    @Test("The bundle declares a microphone usage description")
    func bundleDeclaresMicrophoneUsageDescription() {
        let description = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String
        #expect(description?.isEmpty == false)
    }
}
