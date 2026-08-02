import XCTest

/// Proves the packaged app actually launches on a simulator, which a compile
/// check alone does not guarantee (missing assets, bad Info.plist keys and
/// launch-screen misconfiguration all fail at runtime only).
final class LaunchSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsRootView() {
        let app = XCUIApplication()
        app.launch()

        let root = app.descendants(matching: .any)["root.placeholder"]
        XCTAssertTrue(
            root.waitForExistence(timeout: 15),
            "The root view did not appear; the app failed to launch or the accessibility identifier changed."
        )
    }
}
