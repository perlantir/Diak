import Foundation
import XCTest
@testable import HermesDesktop

final class ConnectorsViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsCatalogAndSelectsFirstConnector() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(client.connectorsCallCount, 1)
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertFalse(viewModel.connectors.isEmpty)
        XCTAssertNotNil(viewModel.selectedConnector)
        XCTAssertFalse(viewModel.boundaryNote.isEmpty)
    }

    @MainActor
    func testSetupStartsOAuthAndPersistsChallenge() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        var openedURLs: [URL] = []
        let viewModel = ConnectorsViewModel(client: client, openURL: { openedURLs.append($0) })
        await viewModel.refresh()
        let notion = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-notion" })
        viewModel.presentSetup(for: notion)

        await viewModel.confirmSetup()

        XCTAssertEqual(client.beginConnectorSetupCallCount, 1)
        XCTAssertNotNil(viewModel.setupChallenge)
        XCTAssertEqual(viewModel.setupChallenge?.state, .awaitingOAuth)
        XCTAssertEqual(viewModel.setupChallenge?.connectorID, notion.id)
        XCTAssertNotNil(viewModel.setupChallenge?.setupURL)
        XCTAssertEqual(openedURLs, [try XCTUnwrap(viewModel.setupChallenge?.setupURL)])

        let updated = try XCTUnwrap(viewModel.connectors.first { $0.id == notion.id })
        XCTAssertEqual(updated.status, .pending)
        XCTAssertNotNil(updated.pendingApprovalID)

        viewModel.dismissSetup()
        XCTAssertNil(viewModel.setupChallenge)
        XCTAssertNil(viewModel.setupConnector)
        XCTAssertTrue(viewModel.setupAcknowledged)
    }

    @MainActor
    func testUpdatePolicyMutatesSelectedConnector() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)
        await viewModel.refresh()
        let github = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-github" })
        XCTAssertEqual(github.writePolicy, .autoApproveLowRisk)

        await viewModel.updatePolicy(for: github, to: .blocked)

        XCTAssertEqual(client.updateConnectorPolicyCallCount, 1)
        let updated = try XCTUnwrap(viewModel.connectors.first { $0.id == github.id })
        XCTAssertEqual(updated.writePolicy, .blocked)
        if case .succeeded(let note) = viewModel.actionState {
            XCTAssertTrue(note.contains("Block writes"))
        } else {
            XCTFail("Expected succeeded action state, got \(viewModel.actionState)")
        }
    }

    @MainActor
    func testDisconnectFlipsStatusAndClearsSync() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)
        await viewModel.refresh()
        let slack = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-slack" })
        XCTAssertTrue(slack.status.isUsable)

        await viewModel.disconnect(slack)

        XCTAssertEqual(client.disconnectConnectorCallCount, 1)
        let updated = try XCTUnwrap(viewModel.connectors.first { $0.id == slack.id })
        XCTAssertEqual(updated.status, .notConnected)
        XCTAssertEqual(updated.syncStatus, .neverSynced)
        XCTAssertNil(updated.lastSyncedAt)
    }

    @MainActor
    func testMissingScopesSurfaceFromFixtures() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)
        await viewModel.refresh()

        // GitHub fixture has a required-but-not-granted PR write scope.
        let github = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-github" })
        XCTAssertTrue(github.hasMissingScopes)
        XCTAssertEqual(github.missingScopes.first?.id, "pull_requests:write")

        // Connected, fully-scoped fixture should NOT report missing scopes.
        let linear = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-linear" })
        XCTAssertFalse(linear.hasMissingScopes)
    }

    @MainActor
    func testRefreshSurfacesOfflineFailureMessage() async throws {
        let client = MockHermesAPIClient(outcome: .offline)
        let viewModel = ConnectorsViewModel(client: client)

        await viewModel.refresh()

        if case .failed(let message) = viewModel.state {
            XCTAssertEqual(message, HermesAPIError.notReachable.userFacingMessage)
        } else {
            XCTFail("Expected failed state, got \(viewModel.state)")
        }
    }


    @MainActor
    func testSearchFiltersConnectorCatalogByNameSummaryCapabilityAndScope() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)
        await viewModel.refresh()

        viewModel.searchText = "gmail.send"
        XCTAssertEqual(viewModel.filteredConnectors.map(\.id), ["conn-gmail"])

        viewModel.searchText = "webhook"
        XCTAssertEqual(viewModel.filteredConnectors.map(\.id), ["conn-http"])

        viewModel.searchText = "send"
        XCTAssertTrue(viewModel.filteredConnectors.contains { $0.id == "conn-slack" })
    }

    @MainActor
    func testRiskyConnectorActionsRequireExplicitConfirmation() async throws {
        let client = MockHermesAPIClient()
        client.resetConnectorState()
        let viewModel = ConnectorsViewModel(client: client)
        await viewModel.refresh()
        let slack = try XCTUnwrap(viewModel.connectors.first { $0.id == "conn-slack" })

        viewModel.requestDisconnect(slack)
        XCTAssertNotNil(viewModel.pendingSafetyConfirmation)
        XCTAssertEqual(client.disconnectConnectorCallCount, 0)
        viewModel.cancelPendingSafetyAction()
        XCTAssertNil(viewModel.pendingSafetyConfirmation)

        viewModel.requestPolicyUpdate(for: slack, to: .autoApproveLowRisk)
        XCTAssertNotNil(viewModel.pendingSafetyConfirmation)
        XCTAssertEqual(client.updateConnectorPolicyCallCount, 0)
        await viewModel.confirmPendingSafetyAction()
        XCTAssertNil(viewModel.pendingSafetyConfirmation)
        XCTAssertEqual(client.updateConnectorPolicyCallCount, 1)
    }

}
