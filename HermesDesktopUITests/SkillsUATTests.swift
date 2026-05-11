import XCTest

/// Full-app UAT for the Skills library. Drives the direct-add sheet
/// end-to-end and verifies the form gating and submission behavior
/// promised by `SkillsAccessibilityID`.
final class SkillsUATTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDirectAddSubmitDisabledUntilAcknowledged() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Skills")

        let addButton = app.buttons["skills.addSkillButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        addButton.click()

        let sheet = app.descendants(matching: .any)["skills.directAddSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))

        let submit = app.buttons["skills.directAdd.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        XCTAssertFalse(submit.isEnabled,
                       "Submit should be disabled with empty required fields")

        // Fill the three required text fields. Submit should still be
        // gated by the install acknowledgement toggle.
        app.textFields["skills.directAdd.name"].uatReplaceText("Diak UAT Slice 8 skill")
        app.textFields["skills.directAdd.summary"].uatReplaceText("Validates direct add via XCUITest.")
        app.textFields["skills.directAdd.trigger"].uatReplaceText("Slice 8 verification only.")

        XCTAssertFalse(submit.isEnabled,
                       "Submit should remain disabled until the install acknowledgement is on")

        let acknowledge = app.checkBoxes["skills.directAdd.acknowledge"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        acknowledge.click()

        XCTAssertTrue(submit.isEnabled,
                      "Submit should enable once acknowledgement + required fields are filled")

        app.buttons["skills.directAdd.cancel"].click()
        XCTAssertTrue(waitForDisappear(sheet, timeout: DiakUATLaunch.defaultTimeout))
        app.terminate()
    }

    func testDirectAddSubmitCreatesSkillRow() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Skills")

        // Snapshot pre-existing skill rows so we can assert the count
        // increased after submission.
        let listExists = app.descendants(matching: .any)["skills.list"]
            .waitForExistence(timeout: DiakUATLaunch.defaultTimeout)
        XCTAssertTrue(listExists)
        let initialRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'skills.row.'"))
            .count

        app.buttons["skills.addSkillButton"].click()
        let sheet = app.descendants(matching: .any)["skills.directAddSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))

        app.textFields["skills.directAdd.name"].uatReplaceText("Diak UAT Slice 8 added skill")
        app.textFields["skills.directAdd.summary"].uatReplaceText("Persists through MockHermesAPIClient.createSkillDraft.")
        app.textFields["skills.directAdd.trigger"].uatReplaceText("XCUITest direct-add path.")
        app.checkBoxes["skills.directAdd.acknowledge"].click()

        let submit = app.buttons["skills.directAdd.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.click()

        XCTAssertTrue(waitForDisappear(sheet, timeout: DiakUATLaunch.defaultTimeout),
                      "Direct-add sheet should dismiss after a successful submit")

        // After dismissal the catalog reloads. The new skill row count
        // should be strictly greater than the pre-submit snapshot.
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'skills.row.'")
        let updatedRows = app.descendants(matching: .any).matching(predicate)
        let deadline = Date().addingTimeInterval(DiakUATLaunch.defaultTimeout)
        while updatedRows.count <= initialRows && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertGreaterThan(updatedRows.count, initialRows,
                             "Submitting a new direct-add skill should add a row to the catalog")
        app.terminate()
    }
}
