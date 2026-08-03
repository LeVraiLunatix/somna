import XCTest

/// Runs Apple's own accessibility audit over every screen.
///
/// This is the part of accessibility that can be checked without a person: the
/// audit flags contrast below threshold, hit regions under 44 points, elements
/// with no description, text clipped at large sizes, and controls whose traits
/// lie about what they do.
///
/// What it cannot check is whether VoiceOver *makes sense* — whether the reading
/// order tells a story, whether a label says the useful thing. That stays a
/// human job, and Phase 8 says so rather than claiming the audit covers it.
final class AccessibilityAuditTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launch(
        skipOnboarding: Bool = true,
        contentSize: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-somna-reset"]
        if skipOnboarding {
            app.launchArguments.append("-somna-skip-onboarding")
        }
        if let contentSize {
            // Drives Dynamic Type from outside, so one build covers every size.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// Somna is used in the dark by people who have just woken up. Contrast and
    /// hit regions are not a formality here.
    private func audit(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try app.performAccessibilityAudit { issue in
                // The message is built here, inside the callback, rather than
                // carrying the issue out of it: `XCUIAccessibilityAuditIssue`
                // is not `Sendable`, and Swift 6 is right to refuse.
                let message = "\(screen) — \(issue.auditType): \(issue.compactDescription)"
                XCTFail(message, file: file, line: line)

                // Reported, then marked handled so the audit continues and one
                // screen yields every one of its problems in a single run.
                // Nothing is ignored: a false positive would get an explicit,
                // reasoned exemption here, never a blanket filter.
                return true
            }
        } catch {
            XCTFail("\(screen): the audit could not run — \(error)", file: file, line: line)
        }
    }

    // MARK: - Screens

    func testOnboardingIsAccessible() {
        let app = launch(skipOnboarding: false)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.root"].waitForExistence(timeout: 15))
        audit(app, screen: "Onboarding")
    }

    func testHomeIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 15))
        audit(app, screen: "Home")
    }

    func testHistoryIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 15))

        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.descendants(matching: .any)["history.root"].waitForExistence(timeout: 10))
        audit(app, screen: "History")
    }

    func testTrendsIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 15))

        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any)["trends.root"].waitForExistence(timeout: 10))
        audit(app, screen: "Trends")
    }

    func testSettingsIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 15))

        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 10))
        audit(app, screen: "Settings")
    }

    func testSessionPreparationIsAccessible() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 15))

        // The start button is only offered when nothing blocks a session; on a
        // simulator without microphone permission the screen shows the reason
        // instead, which is itself worth auditing.
        let start = app.buttons["Start tonight"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
            XCTAssertTrue(app.descendants(matching: .any)["session.root"].waitForExistence(timeout: 10))
            audit(app, screen: "Session preparation")
        } else {
            audit(app, screen: "Home (session blocked)")
        }
    }

    // MARK: - Dynamic Type

    /// AX5 is the setting used by the people who most need a night report to be
    /// legible at 6 a.m. A card that becomes unusable at this size is a card
    /// that fails the users it matters most to.
    func testHomeAtLargestTextSize() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 20))
        audit(app, screen: "Home at AX5")
    }

    func testSettingsAtLargestTextSize() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 20))

        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 10))
        audit(app, screen: "Settings at AX5")
    }

    func testOnboardingAtLargestTextSize() {
        let app = launch(
            skipOnboarding: false,
            contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.root"].waitForExistence(timeout: 20))
        audit(app, screen: "Onboarding at AX5")
    }
}
