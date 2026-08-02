import XCTest

/// Proves the packaged app actually launches and reaches its first real screen.
///
/// A compile check does not cover this: a missing asset colour, a bad Info.plist
/// key, a launch-screen misconfiguration or a persistent store that refuses to
/// open all fail at runtime only.
final class LaunchSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsStatusScreen() {
        let app = XCUIApplication()
        app.launch()

        let root = app.descendants(matching: .any)["status.root"]
        XCTAssertTrue(
            root.waitForExistence(timeout: 15),
            "The status screen did not appear; the app failed to launch or the store failed to open."
        )
    }

    /// The readiness screen resolves permissions and storage asynchronously.
    /// Reaching a settled state proves the injected environment is wired: the
    /// unconfigured fallback repository throws, which would surface the error
    /// state instead.
    func testStatusScreenReachesASettledState() {
        let app = XCUIApplication()
        app.launch()

        // A fresh simulator install has an undetermined microphone permission,
        // so either outcome is correct. What must not happen is neither — that
        // would mean the screen is still loading, or the injected environment
        // fell back to the repository that throws.
        let ready = app.staticTexts["Ready to record tonight"]
        let microphoneBlocked = app.staticTexts["Somna cannot hear anything"]

        let settled = ready.waitForExistence(timeout: 20)
            || microphoneBlocked.waitForExistence(timeout: 5)

        XCTAssertTrue(settled, "The status screen never resolved into a ready or blocked state.")
    }
}
