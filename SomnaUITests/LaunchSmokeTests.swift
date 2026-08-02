import XCTest

/// Proves the packaged app launches and reaches its first real screen.
///
/// A compile check does not cover this: a missing asset colour, a bad Info.plist
/// key, a launch-screen misconfiguration or a persistent store that refuses to
/// open all fail at runtime only.
final class LaunchSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A fresh install has never completed onboarding, so this is what a first
    /// beta tester sees.
    func testFreshInstallStartsInOnboarding() {
        let app = XCUIApplication()
        app.launch()

        let onboarding = app.descendants(matching: .any)["onboarding.root"]
        XCTAssertTrue(
            onboarding.waitForExistence(timeout: 15),
            "Onboarding did not appear; the app failed to launch or settings could not be read."
        )
    }

    /// Walks the four explanatory steps. They must be reachable without granting
    /// anything: the permission prompt comes after the explanations, and a
    /// tester who reads carefully must not hit a wall before it.
    func testExplanatoryStepsAreReachableWithoutPermissions() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.root"].waitForExistence(timeout: 15))

        let advance = app.buttons["Continue"]
        for step in 1...3 {
            XCTAssertTrue(
                advance.waitForExistence(timeout: 5),
                "Continue was unavailable at explanatory step \(step)."
            )
            advance.tap()
        }

        // Step four is the privacy explanation; step five asks for the microphone.
        XCTAssertTrue(
            app.staticTexts["Everything stays on this iPhone"].waitForExistence(timeout: 5),
            "The privacy step was not reached."
        )
    }

    /// The microphone step must never trap someone who has not answered yet, and
    /// must not offer a button that iOS will ignore.
    func testMicrophoneStepBlocksOnlyUntilAnswered() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.root"].waitForExistence(timeout: 15))

        let advance = app.buttons["Continue"]
        for _ in 0..<4 {
            guard advance.waitForExistence(timeout: 5) else { break }
            advance.tap()
        }

        let allow = app.buttons["Allow microphone access"]
        XCTAssertTrue(
            allow.waitForExistence(timeout: 5),
            "The microphone step did not offer a request button while undetermined."
        )
        XCTAssertFalse(
            advance.isEnabled,
            "Onboarding advanced past the microphone step before it was answered."
        )
    }
}
