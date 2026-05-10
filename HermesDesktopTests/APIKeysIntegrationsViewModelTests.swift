import Foundation
import XCTest
@testable import HermesDesktop

@MainActor
final class APIKeysIntegrationsViewModelTests: XCTestCase {

    // MARK: - Initial load / status mapping

    func testRefreshLoadsCatalogAndMapsStatus() async {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let store = InMemorySecretStore()
        let viewModel = APIKeysIntegrationsViewModel(client: client, secretStore: store)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.slots.count, 1)
        let composio = try! XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.descriptor.id, "composio")
        XCTAssertEqual(composio.status.presence, .missing)
        XCTAssertEqual(composio.primaryStatusBadge.label, "Configuration required")
        XCTAssertEqual(composio.primaryStatusBadge.tone, .warning)
        XCTAssertEqual(viewModel.boundaryNote, HermesSecretCatalog.defaultBoundaryNote)
    }

    func testRefreshFailureSurfacesUserFacingMessage() async {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = APIKeysIntegrationsViewModel(client: client)

        await viewModel.refresh()

        if case .failed(let message) = viewModel.loadState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected failed load state, got \(viewModel.loadState)")
        }
        XCTAssertTrue(viewModel.slots.isEmpty)
    }

    func testStatusBadgeReflectsValidityWhenSaved() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // Force a saved+valid status via the mock side door (testSecret with a pinned valid result).
        client.nextSecretTestResult = HermesSecretTestResult(
            id: "composio",
            isOK: true,
            validity: .valid,
            message: "ok",
            testedAt: Date()
        )

        // First we need to save so presence flips to .saved.
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_live_xyz")
        await viewModel.save(slotID: "composio")
        await viewModel.testConnection(slotID: "composio")

        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.status.presence, .saved)
        XCTAssertEqual(composio.status.validity, .valid)
        XCTAssertEqual(composio.primaryStatusBadge.label, "Valid")
        XCTAssertEqual(composio.primaryStatusBadge.tone, .success)
    }

    // MARK: - Save: success path

    func testSaveSuccessClearsRawDraftsAndUpdatesStatus() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let store = InMemorySecretStore()
        let viewModel = APIKeysIntegrationsViewModel(client: client, secretStore: store)
        await viewModel.refresh()

        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_live_xyz")
        viewModel.setDraft(slotID: "composio", fieldID: "base_url", value: "https://example.invalid")
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)

        await viewModel.save(slotID: "composio")

        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.status.presence, .saved)
        XCTAssertEqual(composio.fieldDrafts.values.filter { !$0.isEmpty }.count, 0,
                       "Sensitive drafts must be cleared after a successful save")
        XCTAssertFalse(composio.acknowledgedKeychainStorage,
                       "Acknowledgement must reset after save so the next change requires re-confirming")
        XCTAssertEqual(composio.inFlight, .idle)
        XCTAssertNil(composio.lastError)
        XCTAssertTrue(composio.requiresBridgeRestart)

        // The local secret store mirror should hold the value so Slice 3
        // can pick it up for bridge env injection.
        XCTAssertEqual(try store.getSecret(account: "composio.api_key"), "comp_live_xyz")
        XCTAssertEqual(try store.getSecret(account: "composio.base_url"), "https://example.invalid")

        // Mock client must not echo raw values back through the catalog.
        let saved = client._debugSavedSecretValues(forID: "composio")
        XCTAssertEqual(saved["api_key"], "comp_live_xyz")
    }

    // MARK: - Save: validation

    func testSaveRejectsMissingRequiredValueWithoutAcknowledgement() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // No draft, no acknowledgement.
        await viewModel.save(slotID: "composio")

        XCTAssertEqual(client.saveSecretCallCount, 0,
                       "Save must not hit the boundary when validation fails locally")
        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertNotNil(composio.lastError)
        XCTAssertEqual(composio.status.presence, .missing)
    }

    func testSaveRejectsAcknowledgedButEmptyDraft() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        // Leave only whitespace in the api_key — should be treated as empty.
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "   ")

        await viewModel.save(slotID: "composio")

        XCTAssertEqual(client.saveSecretCallCount, 0)
        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertNotNil(composio.lastError)
    }

    func testSaveRejectsWhenRequiredPrimaryIsMissingFromBothStateAndDraft() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // Draft only the optional base_url; api_key is required and not yet saved.
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        viewModel.setDraft(slotID: "composio", fieldID: "base_url", value: "https://example.invalid")

        await viewModel.save(slotID: "composio")

        XCTAssertEqual(client.saveSecretCallCount, 0,
                       "Save must reject locally when a required primary field is unsaved AND undrafted")
        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertNotNil(composio.lastError)
        XCTAssertTrue(composio.lastError?.contains("API key") == true,
                      "Error message should reference the missing field label, got \(composio.lastError ?? "nil")")
    }

    // MARK: - Remove

    func testRemoveClearsStatusAndStore() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let store = InMemorySecretStore()
        let viewModel = APIKeysIntegrationsViewModel(client: client, secretStore: store)
        await viewModel.refresh()

        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_live_xyz")
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        await viewModel.save(slotID: "composio")
        XCTAssertEqual(try store.getSecret(account: "composio.api_key"), "comp_live_xyz")

        await viewModel.remove(slotID: "composio")

        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.status.presence, .missing)
        XCTAssertEqual(composio.status.validity, .untested)
        XCTAssertNil(composio.lastTestMessage,
                     "Removing must clear any prior test verdict copy")
        XCTAssertNil(try store.getSecret(account: "composio.api_key"),
                     "Removing must drop local Keychain mirrors")
        XCTAssertTrue(composio.fieldDrafts.isEmpty)
    }

    // MARK: - Test connection

    func testTestConnectionSurfacesValidVerdict() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // Save first so presence becomes .saved.
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_live_xyz")
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        await viewModel.save(slotID: "composio")

        client.nextSecretTestResult = HermesSecretTestResult(
            id: "composio",
            isOK: true,
            validity: .valid,
            message: "All good",
            testedAt: Date()
        )

        await viewModel.testConnection(slotID: "composio")

        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.status.validity, .valid)
        XCTAssertEqual(composio.lastTestMessage, "All good")
        XCTAssertEqual(composio.lastTestTone, .success)
        XCTAssertEqual(composio.inFlight, .idle)
        XCTAssertEqual(client.testSecretCallCount, 1)
    }

    func testTestConnectionSurfacesInvalidVerdict() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // Save first so presence becomes .saved.
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "comp_live_xyz")
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        await viewModel.save(slotID: "composio")

        client.nextSecretTestResult = HermesSecretTestResult(
            id: "composio",
            isOK: false,
            validity: .invalid,
            message: "Provider rejected",
            testedAt: Date()
        )

        await viewModel.testConnection(slotID: "composio")

        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.status.validity, .invalid)
        XCTAssertEqual(composio.lastTestTone, .danger)
        XCTAssertEqual(composio.lastTestMessage, "Provider rejected")
    }

    func testTestConnectionWithoutSavedCredentialsDoesNotHitDaemon() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        await viewModel.testConnection(slotID: "composio")

        XCTAssertEqual(client.testSecretCallCount, 0,
                       "Testing must be a no-op when the slot has no saved credentials")
        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertEqual(composio.lastTestTone, .warning)
        XCTAssertNotNil(composio.lastTestMessage)
    }

    // MARK: - Restart bridge

    func testRestartBridgeClearsPerSlotRestartFlagAndRefreshes() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        // Save to flip requiresBridgeRestart on the slot.
        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "k")
        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        await viewModel.save(slotID: "composio")

        let preRestart = try XCTUnwrap(viewModel.slots.first)
        XCTAssertTrue(preRestart.requiresBridgeRestart)
        XCTAssertTrue(viewModel.hasAnyPendingRestart)

        await viewModel.restartBridge()

        XCTAssertFalse(viewModel.restartInFlight)
        XCTAssertNil(viewModel.restartLastError)
        XCTAssertNotNil(viewModel.restartLastMessage)
        XCTAssertFalse(viewModel.hasAnyPendingRestart,
                       "Restart must clear per-slot restart prompts")
    }

    // MARK: - canSave invariants

    func testCanSaveRequiresAcknowledgement() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let viewModel = APIKeysIntegrationsViewModel(client: client)
        await viewModel.refresh()

        viewModel.setDraft(slotID: "composio", fieldID: "api_key", value: "k")
        let composio = try XCTUnwrap(viewModel.slots.first)
        XCTAssertFalse(composio.canSave,
                       "Save must be disabled until the user acknowledges Keychain storage")

        viewModel.setAcknowledgedKeychainStorage(slotID: "composio", true)
        let composioAfter = try XCTUnwrap(viewModel.slots.first)
        XCTAssertTrue(composioAfter.canSave)
    }
}
