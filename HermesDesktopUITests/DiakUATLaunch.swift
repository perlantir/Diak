import XCTest

/// Shared launch helper for full-app UAT tests. Boots the built
/// `Diak.app` under `--diak-uat-mode`, which swaps the production
/// bridge client for the in-memory `MockHermesAPIClient` and skips
/// onboarding so the harness can immediately address Memory / Skills /
/// Automations identifiers.
enum DiakUATLaunch {
    /// Sentinel timeout for waitForExistence calls. macOS UI tests on
    /// CI runners occasionally take a few seconds to first render the
    /// sidebar, so the timeout is intentionally generous.
    static let defaultTimeout: TimeInterval = 10

    /// Launches a fresh Diak instance under UAT mode. Each test gets
    /// its own process so the mock client's in-memory state never
    /// leaks across cases.
    @discardableResult
    static func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--diak-uat-mode"] + extraArguments
        app.launch()
        return app
    }

    /// Returns the first sidebar item button that exposes the given
    /// section title. The sidebar items are plain `Button(action:)`
    /// wrappers, so XCUITest resolves them by their visible label.
    static func sidebarButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons[title]
    }

    /// Activates the named sidebar section and returns once it is
    /// hit-testable.
    @discardableResult
    static func navigate(_ app: XCUIApplication, to title: String) -> XCUIElement {
        let button = sidebarButton(app, title)
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout), "Sidebar item '\(title)' did not appear")
        button.click()
        return button
    }
}

/// Convenience wrappers — XCUITest's typing helpers don't always treat
/// SwiftUI `TextEditor` or `TextField` controls the same way as AppKit
/// fields, so we wrap them in one place that the test cases share.
extension XCUIElement {
    /// Clear and re-type into a text field. Uses keyboard select-all
    /// then delete-by-typing to remain robust against placeholder text
    /// and prior content from earlier tests in the same process.
    func uatReplaceText(_ value: String) {
        click()
        typeKey("a", modifierFlags: .command)
        typeKey(.delete, modifierFlags: [])
        typeText(value)
    }
}
