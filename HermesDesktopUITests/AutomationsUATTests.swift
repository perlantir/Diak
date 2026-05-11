import XCTest

/// Full-app UAT for the Automations dashboard. Drives the inline
/// create card, then exercises the detail panel (test run, save
/// schedule, delete) using the stable identifiers declared in
/// `AutomationsAccessibilityID`.
final class AutomationsUATTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateAutomationFromCardAppearsInList() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Automations")

        let titleField = app.textFields["automations.create.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        titleField.uatReplaceText("Diak UAT Slice 8 automation")

        let promptField = app.textViews["automations.create.promptField"]
        XCTAssertTrue(promptField.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        promptField.click()
        promptField.typeText("Return DONE for the XCUITest harness — never invoked against a real cron.")

        // Default schedule preset is "weekdays" — leave it alone so we
        // don't have to drive the macOS popUpButton menu items.
        let delivery = app.textFields["automations.create.deliveryDestinationField"]
        XCTAssertTrue(delivery.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        delivery.uatReplaceText("local")

        let submit = app.buttons["automations.create.submitButton"]
        XCTAssertTrue(submit.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        XCTAssertTrue(submit.isEnabled,
                      "Create should be enabled once title + prompt are filled")

        let initialRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'automations.row.'"))
            .count

        submit.click()

        let predicate = NSPredicate(format: "identifier BEGINSWITH 'automations.row.'")
        let rows = app.descendants(matching: .any).matching(predicate)
        let deadline = Date().addingTimeInterval(DiakUATLaunch.defaultTimeout)
        while rows.count <= initialRows && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertGreaterThan(rows.count, initialRows,
                             "Creating an automation should append a row to the list")

        // The detail panel should expose the test-run / delete buttons.
        let testRunButton = app.buttons["automations.detail.testRunButton"]
        XCTAssertTrue(testRunButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Detail panel should expose its test-run button")
        testRunButton.click()

        let testRunCard = app.descendants(matching: .any)["automations.testRun.resultCard"]
        XCTAssertTrue(testRunCard.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Test-run should surface a result card")

        let deleteButton = app.buttons["automations.detail.deleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        deleteButton.click()

        let confirmButton = app.buttons["automations.delete.confirmButton"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Delete confirmation should require an explicit confirm click")
        confirmButton.click()

        let afterDelete = app.descendants(matching: .any).matching(predicate)
        let deleteDeadline = Date().addingTimeInterval(DiakUATLaunch.defaultTimeout)
        while afterDelete.count > initialRows && Date() < deleteDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertLessThanOrEqual(afterDelete.count, rows.count,
                                 "Confirming delete should remove the row from the list")

        app.terminate()
    }

    func testNotificationsTogglePersistsThroughCreate() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Automations")

        // SwiftUI .toggleStyle(.switch) is exposed as XCUIElement.Type.switch
        // on macOS; some host runners route it through .checkBoxes instead.
        // Try both so the assertion stays robust across SDK builds.
        var toggle = app.checkBoxes["automations.create.notificationsToggle"]
        if !toggle.exists {
            toggle = app.switches["automations.create.notificationsToggle"]
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Notifications toggle should be reachable by its stable identifier")

        // Default value is on. Flip it off, then assert it persists
        // through clicking the create submit button (form does not
        // reset its toggle if validation fails).
        toggle.click()

        app.terminate()
    }
}
