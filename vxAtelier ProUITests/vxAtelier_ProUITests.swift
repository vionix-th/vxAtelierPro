import XCTest

final class vxAtelier_ProUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() throws {
        let app = launchApplication()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.isHittable)
    }

    @MainActor
    func testSettingsShortcutPresentsSettings() throws {
        let app = launchApplication()

        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(app.staticTexts["General Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testContentFilterShortcutsKeepMainWindowAvailable() throws {
        let app = launchApplication()

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }
}
