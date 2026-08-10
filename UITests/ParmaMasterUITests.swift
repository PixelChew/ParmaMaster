import XCTest

@MainActor
final class ParmaMasterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingAndPrimaryDestinations() throws {
        let app = XCUIApplication()
        app.launch()

        let letsGo = app.buttons["Let’s go"]
        if letsGo.waitForExistence(timeout: 4) {
            letsGo.tap()
            XCTAssertTrue(app.staticTexts["First things first."].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Location, request permission"].exists)
            XCTAssertTrue(app.buttons["Camera & Photos, request permission"].exists)
            XCTAssertTrue(app.buttons["Notifications, request permission"].exists)
            app.buttons["Continue"].tap()
        }

        XCTAssertTrue(app.buttons["Log a Parma"].waitForExistence(timeout: 5))

        app.buttons["Parma Log"].tap()
        XCTAssertTrue(app.staticTexts["Your Parma Log is empty"].waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
        XCTAssertTrue(app.staticTexts["Parma Logging"].exists)
        XCTAssertTrue(app.staticTexts["Behaviour"].exists)
        XCTAssertTrue(app.staticTexts["Backup & Reset"].exists)

        app.staticTexts["Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        let darkTheme = app.buttons["Dark"]
        XCTAssertTrue(darkTheme.waitForExistence(timeout: 3))
        darkTheme.tap()
        XCTAssertTrue(darkTheme.isSelected)
        app.navigationBars["Appearance"].buttons["Settings"].tap()

        app.staticTexts["Behaviour"].tap()
        XCTAssertTrue(app.navigationBars["Behaviour"].waitForExistence(timeout: 3))
        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Appearance"].exists)

        app.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Nothing to search yet"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Search empty state in Dark Mode"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
