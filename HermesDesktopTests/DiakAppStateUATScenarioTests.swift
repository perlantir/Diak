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

    // MARK: - Settings (M12 Slice 10)

    @MainActor
    func testSettingsScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()
        client.resetSecretState()

        let report = await DiakAppStateUATScenario.runSettingsScenario(client: client)

        XCTAssertEqual(report.feature, "settings")
        XCTAssertTrue(report.passed,
                      "Settings app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 6,
                                    "Settings scenario must exercise load + blocked save + save + test + restart + remove.")

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("API keys catalog loads Composio slot in configuration-required state"))
        XCTAssertTrue(stepNames.contains("Save without keychain acknowledgement is blocked at the view model"))
        XCTAssertTrue(stepNames.contains("Save with acknowledgement persists Composio metadata and clears raw drafts"))
        XCTAssertTrue(stepNames.contains("Test connection routes through daemon verdict"))
        XCTAssertTrue(stepNames.contains("Restart bridge clears per-slot restart prompts"))
        XCTAssertTrue(stepNames.contains("Remove tears Composio slot back down to missing"))

        XCTAssertEqual(client.saveSecretCallCount, 1)
        XCTAssertEqual(client.testSecretCallCount, 1)
        XCTAssertEqual(client.deleteSecretCallCount, 1)
        XCTAssertEqual(client.restartDaemonCallCount, 1)

        // Raw secret material must never end up in evidence fingerprints.
        for step in report.steps {
            XCTAssertFalse(step.snapshotFingerprint.contains("comp_uat_key_placeholder"),
                           "Settings fingerprint leaked raw API key: \(step.snapshotFingerprint)")
        }
    }

    // MARK: - Connectors (M12 Slice 10)

    @MainActor
    func testConnectorsScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()
        client.resetConnectorState()

        let report = await DiakAppStateUATScenario.runConnectorsScenario(client: client)

        XCTAssertEqual(report.feature, "connectors")
        XCTAssertTrue(report.passed,
                      "Connectors app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 4)

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("Connectors catalog loads"))
        XCTAssertTrue(stepNames.contains("Setup blocked with configuration_required when Composio is missing"))
        XCTAssertTrue(stepNames.contains("Setup proceeds and opens OAuth handoff once Composio presence is satisfied"))
        XCTAssertTrue(stepNames.contains("Disconnect honors safety confirmation and clears connected state"))

        XCTAssertEqual(client.beginConnectorSetupCallCount, 2,
                       "Connector setup must be exercised twice (blocked + ready).")
        XCTAssertEqual(client.disconnectConnectorCallCount, 1)
    }

    // MARK: - Chat / sessions (M12 Slice 10)

    @MainActor
    func testChatSessionsScenarioFormFlowPasses() async {
        let client = MockHermesAPIClient()

        let report = await DiakAppStateUATScenario.runChatSessionsScenario(client: client)

        XCTAssertEqual(report.feature, "chat")
        XCTAssertTrue(report.passed,
                      "Chat app-state UAT scenario reported a failure: \(failedDetails(report.steps))")
        XCTAssertGreaterThanOrEqual(report.steps.count, 5)

        let stepNames = Set(report.steps.map { $0.name })
        XCTAssertTrue(stepNames.contains("Sessions rail loads catalog"))
        XCTAssertTrue(stepNames.contains("Open existing chat A restores prior messages"))
        XCTAssertTrue(stepNames.contains("Continue chat A keeps prior messages and calls continueSession"))
        XCTAssertTrue(stepNames.contains("Start a brand-new chat B creates a separate session"))
        XCTAssertTrue(stepNames.contains("Switch back to chat A restores its transcript independently of chat B"))

        XCTAssertGreaterThanOrEqual(client.continueSessionCallCount, 1,
                                    "Continuing an existing chat must route through continueSession.")
        XCTAssertGreaterThanOrEqual(client.createSessionCallCount, 1,
                                    "Starting a brand-new chat must route through createSession.")
        XCTAssertGreaterThanOrEqual(client.sessionsCallCount, 1)
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
              settings: \(report.settings.passed)
              connectors: \(report.connectors.passed)
              chat: \(report.chat.passed)
            Failed step details: memory=\(failedDetails(report.memory.steps)), \
            skills=\(failedDetails(report.skills.steps)), \
            automations=\(failedDetails(report.automations.steps)), \
            settings=\(failedDetails(report.settings.steps)), \
            connectors=\(failedDetails(report.connectors.steps)), \
            chat=\(failedDetails(report.chat.steps))
            """)
        XCTAssertEqual(report.memory.feature, "memory")
        XCTAssertEqual(report.skills.feature, "skills")
        XCTAssertEqual(report.automations.feature, "automations")
        XCTAssertEqual(report.settings.feature, "settings")
        XCTAssertEqual(report.connectors.feature, "connectors")
        XCTAssertEqual(report.chat.feature, "chat")
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
        XCTAssertFalse(serialized.contains("comp_uat_key_placeholder"),
                       "Sanitized evidence must not include raw Composio API key drafts.")
        XCTAssertFalse(serialized.contains("Slice 10 UAT follow-up"),
                       "Sanitized evidence must not include chat prompt text users typed in.")
        XCTAssertFalse(serialized.contains("Slice 10 UAT brand-new chat"),
                       "Sanitized evidence must not include chat prompt text users typed in.")
        XCTAssertFalse(serialized.contains("https://composio.uat.local"),
                       "Sanitized evidence must not include base URL drafts users typed in.")

        XCTAssertTrue(serialized.contains("\"status\""))
        XCTAssertTrue(serialized.contains("\"memory\""))
        XCTAssertTrue(serialized.contains("\"skills\""))
        XCTAssertTrue(serialized.contains("\"automations\""))
        XCTAssertTrue(serialized.contains("\"settings\""))
        XCTAssertTrue(serialized.contains("\"connectors\""))
        XCTAssertTrue(serialized.contains("\"chat\""))
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
