import Foundation
import XCTest
@testable import HermesDesktop

/// M12 Slice 9 — end-to-end Swift app-state UAT proof for Memory / Skills
/// / Automations form submission flows.
///
/// Each test drives the real view-model state machine that the visible
/// SwiftUI screens hold, through `MockHermesAPIClient`. The corresponding
/// scenario steps mirror the same field-by-field flow a tester would type
/// into Diak. The XCUITest runner can be blocked in unattended cron, but
/// these tests are not — they execute under the default release-gate
/// `xcodebuild test` invocation.
final class DiakAppStateUATScenarioTests: XCTestCase {

    // MARK: - Memory

    @MainActor
    func testMemoryScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()
        client.resetMemoryState()

        let report = await DiakAppStateUATScenario.runMemoryScenario(client: client)

        XCTAssertEqual(report.feature, "memory")
        XCTAssertTrue(report.passed,
                      "Memory app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 5,
                                    "Memory scenario must exercise refresh + create + edit + pin + delete.")

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("Memory dashboard loads"))
        XCTAssertTrue(stepNames.contains("Create memory honors acknowledge gate then persists"))
        XCTAssertTrue(stepNames.contains("Edit memory honors acknowledge gate then persists"))
        XCTAssertTrue(stepNames.contains("Pin toggle reaches boundary without acknowledgement"))
        XCTAssertTrue(stepNames.contains("Delete confirmation queues and removes record"))
        XCTAssertTrue(stepNames.contains("Imported memory rejects delete at boundary"))

        // Every step must contain at least one check so the evidence is
        // meaningful instead of an empty "passed" marker.
        XCTAssertTrue(report.steps.allSatisfy { !$0.checks.isEmpty })

        // Boundary mutation counts confirm the typed API was hit exactly
        // as the form sheets would have called it.
        XCTAssertEqual(client.createMemoryItemCallCount, 1)
        XCTAssertEqual(client.updateMemoryItemCallCount, 2,
                       "Edit and pin-toggle both flow through the update endpoint exactly once each.")
        XCTAssertEqual(client.deleteMemoryItemCallCount, 1)
    }

    // MARK: - Skills

    @MainActor
    func testSkillsScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()
        client.resetSkillState()

        let report = await DiakAppStateUATScenario.runSkillsScenario(client: client)

        XCTAssertEqual(report.feature, "skills")
        XCTAssertTrue(report.passed,
                      "Skills app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 4)

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("Skills catalog loads"))
        XCTAssertTrue(stepNames.contains("Direct add rejects missing required fields"))
        XCTAssertTrue(stepNames.contains("Direct add requires daemon-install acknowledgement"))
        XCTAssertTrue(stepNames.contains("Direct add persists draft and dismisses sheet"))

        // Direct-add path must have reached the typed API exactly once
        // (the missing-field + missing-ack pre-checks are local-only).
        XCTAssertEqual(client.createSkillDraftCallCount, 1)
        XCTAssertGreaterThanOrEqual(client.setSkillEnabledCallCount, 1,
                                    "Toggle step should have flipped at least one existing skill.")
    }

    // MARK: - Automations

    @MainActor
    func testAutomationsScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()
        client.resetAutomationState()

        let report = await DiakAppStateUATScenario.runAutomationsScenario(client: client)

        XCTAssertEqual(report.feature, "automations")
        XCTAssertTrue(report.passed,
                      "Automations app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 6)

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("Automations dashboard loads"))
        XCTAssertTrue(stepNames.contains("Create validation blocks invalid drafts"))
        XCTAssertTrue(stepNames.contains("Create automation persists schedule and delivery"))
        XCTAssertTrue(stepNames.contains("Test run shows visible succeeded state for selected job"))
        XCTAssertTrue(stepNames.contains("Update delivery and schedule persist on existing job"))
        XCTAssertTrue(stepNames.contains("Delete automation honors confirmation and removes record"))

        XCTAssertEqual(client.createAutomationCallCount, 1)
        XCTAssertEqual(client.testRunAutomationCallCount, 1)
        XCTAssertEqual(client.deleteAutomationCallCount, 1)
        XCTAssertGreaterThanOrEqual(client.updateAutomationCallCount, 2,
                                    "Update delivery + update schedule each flow through update endpoint.")
    }

    // MARK: - Aggregate

    @MainActor
    func testRunAllAggregatesEveryFeatureScenarioToPass() async {
        let report = await DiakAppStateUATScenario.runAll()

        XCTAssertTrue(report.passed, """
            App-state UAT FullReport reported a failure:
              memory: \(report.memory.passed)
              skills: \(report.skills.passed)
              automations: \(report.automations.passed)
            Failed step details: memory=\(failedDetails(report.memory.steps)), \
            skills=\(failedDetails(report.skills.steps)), \
            automations=\(failedDetails(report.automations.steps))
            """)
        XCTAssertEqual(report.memory.feature, "memory")
        XCTAssertEqual(report.skills.feature, "skills")
        XCTAssertEqual(report.automations.feature, "automations")
    }

    // MARK: - Sanitized evidence

    @MainActor
    func testSanitizedJSONObjectIsLeakSafeAndJSONEncodable() async throws {
        let report = await DiakAppStateUATScenario.runAll()
        let json = report.sanitizedJSONObject

        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys, .prettyPrinted]
        )
        let serialized = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Sanitization rule: the evidence payload must never echo back
        // the free-form text the user typed in the seam (only labels,
        // counters, gating booleans, and fingerprints).
        XCTAssertFalse(serialized.contains("Slice 9 UAT memory"),
                       "Sanitized evidence must not include memory titles users typed in.")
        XCTAssertFalse(serialized.contains("Slice 9 UAT skill"),
                       "Sanitized evidence must not include skill names users typed in.")
        XCTAssertFalse(serialized.contains("Slice 9 UAT automation"),
                       "Sanitized evidence must not include automation titles users typed in.")
        XCTAssertFalse(serialized.contains("Stay read-only."),
                       "Sanitized evidence must not include direct-add instructions.")

        XCTAssertTrue(serialized.contains("\"status\""))
        XCTAssertTrue(serialized.contains("\"memory\""))
        XCTAssertTrue(serialized.contains("\"skills\""))
        XCTAssertTrue(serialized.contains("\"automations\""))
    }

    @MainActor
    func testSnapshotFingerprintsChangeAsFormStateChanges() async {
        let client = MockHermesAPIClient()
        client.resetMemoryState()
        let viewModel = MemoryViewModel(client: client)
        await viewModel.refresh()

        let initial = DiakAppStateUATScenario.snapshotFingerprint(viewModel.uatSnapshot)
        viewModel.presentCreate()
        let presented = DiakAppStateUATScenario.snapshotFingerprint(viewModel.uatSnapshot)
        viewModel.draftAcknowledgedReview = true
        let acknowledged = DiakAppStateUATScenario.snapshotFingerprint(viewModel.uatSnapshot)

        XCTAssertNotEqual(initial, presented,
                          "Fingerprint should reflect that the create sheet became visible.")
        XCTAssertNotEqual(presented, acknowledged,
                          "Fingerprint should reflect that the acknowledge gate flipped.")
    }

    // MARK: - Helpers

    private func failedDetails(_ steps: [DiakAppStateUATScenario.Step]) -> String {
        let failures = steps
            .filter { !$0.passed }
            .map { step -> String in
                let failingChecks = step.checks
                    .filter { !$0.passed }
                    .map { "\($0.name): \($0.detail)" }
                    .joined(separator: "; ")
                return "[\(step.name)] -> \(failingChecks)"
            }
            .joined(separator: " | ")
        return failures.isEmpty ? "no failures" : failures
    }
}
