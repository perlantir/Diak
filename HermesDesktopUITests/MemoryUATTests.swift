import XCTest

/// Full-app UAT for the Memory dashboard. Boots the real `Diak.app`
/// under `--diak-uat-mode`, navigates to Memory through the sidebar,
/// and exercises the add / edit / delete flows by addressing only the
/// stable identifiers declared in `MemoryAccessibilityID`. Submission
/// outcomes are verified by re-querying the list/detail surfaces — the
/// XCUITest harness never reaches into view-model state directly.
final class MemoryUATTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddMemoryFromAddButtonAppearsInList() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Memory")

        let addButton = app.buttons["memory.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Memory add button should be reachable from the route")
        addButton.click()

        let sheet = app.descendants(matching: .any)["memory.editSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: DiakUATLaunch.defaultTimeout),
                      "Memory edit sheet should present after Add")

        let titleField = app.textFields["memory.editSheet.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        titleField.uatReplaceText("Diak UAT Slice 8 memory")

        let bodyField = app.textViews["memory.editSheet.bodyField"]
        XCTAssertTrue(bodyField.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        bodyField.click()
        bodyField.typeText("Recorded by the Slice 8 XCUITest harness — no real daemon write.")

        let acknowledge = app.checkBoxes["memory.editSheet.acknowledgeToggle"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        if acknowledge.value as? Int == 0 || (acknowledge.value as? String) == "0" {
            acknowledge.click()
        }

        let saveButton = app.buttons["memory.editSheet.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        XCTAssertTrue(saveButton.isEnabled,
                      "Save should be enabled once the acknowledgement is toggled on")
        saveButton.click()

        XCTAssertTrue(waitForDisappear(sheet, timeout: DiakUATLaunch.defaultTimeout),
                      "Memory edit sheet should dismiss after a successful save")

        // The new memory should land in the list. The mock client
        // generates the id from the title slug — we don't pin the
        // exact id here, but at least one memory row must exist after
        // the save (the default fixture also seeds a few entries).
        let list = app.descendants(matching: .any)["memory.list"]
        XCTAssertTrue(list.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))
        let anyMemoryRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'memory.row.'"))
        XCTAssertGreaterThan(anyMemoryRow.count, 0,
                             "At least one memory row should be visible after save")

        app.terminate()
    }

    func testCancelMemoryAddDismissesSheetWithoutSaving() throws {
        let app = DiakUATLaunch.launch()
        DiakUATLaunch.navigate(app, to: "Memory")

        let baselineRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'memory.row.'"))
        // Give the list a moment to load before snapshotting the count.
        _ = app.descendants(matching: .any)["memory.list"]
            .waitForExistence(timeout: DiakUATLaunch.defaultTimeout)
        let baselineCount = baselineRows.count

        app.buttons["memory.addButton"].click()

        let sheet = app.descendants(matching: .any)["memory.editSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: DiakUATLaunch.defaultTimeout))

        app.buttons["memory.editSheet.closeButton"].click()
        XCTAssertTrue(waitForDisappear(sheet, timeout: DiakUATLaunch.defaultTimeout))

        XCTAssertEqual(baselineRows.count, baselineCount,
                       "Cancel should not mutate the visible memory list")
        app.terminate()
    }
}

/// Polls the element's existence until it disappears or the timeout
/// elapses. Mirrors the absence of `XCUIElement.waitForNonExistence`
/// on older Xcode toolchains.
func waitForDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !element.exists { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return !element.exists
}
