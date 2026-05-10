import Foundation
import XCTest
@testable import HermesDesktop

final class HermesConnectorDecodingTests: XCTestCase {
    func testConnectorDecodesSnakeCaseAndUnknownEnumCases() throws {
        let data = Data("""
        {
          "id": "conn-mystery",
          "kind": "wormhole_provider",
          "display_name": "Wormhole",
          "summary": "An unrecognised provider added by a future daemon.",
          "status": "weird_state",
          "sync_status": "still_thinking",
          "write_policy": "vibe_check",
          "capabilities": ["read", "send", "telekinesis"],
          "scopes": [
            { "id": "wormhole.read", "display_name": "Read traffic", "is_granted": true, "is_required": true },
            { "id": "wormhole.write", "display_name": "Send traffic", "detail": "Required to publish.", "is_granted": false, "is_required": true }
          ],
          "setup_kind": "ceremonial",
          "account_label": "primary@uberkiwi.com",
          "last_synced_at": "2026-05-09T22:30:14Z",
          "last_error": "Provider returned 502 once.",
          "pending_approval_id": "appr-conn-setup-conn-mystery"
        }
        """.utf8)

        let connector = try JSONDecoder().decode(HermesConnector.self, from: data)

        XCTAssertEqual(connector.kind, .unknown, "Unknown provider kinds must decode to .unknown without throwing.")
        XCTAssertEqual(connector.status, .unknown)
        XCTAssertEqual(connector.syncStatus, .unknown)
        XCTAssertEqual(connector.writePolicy, .alwaysAsk, "Unknown write policy strings should be treated as the safe default.")
        XCTAssertEqual(connector.setupKind, .unknown)
        XCTAssertEqual(connector.capabilities.count, 3)
        XCTAssertEqual(connector.capabilities.last, .unknown,
                       "Unknown capability strings must decode to .unknown so the row still renders.")
        XCTAssertEqual(connector.scopes.count, 2)
        XCTAssertTrue(connector.hasMissingScopes,
                      "Required scopes that are not granted should surface through hasMissingScopes.")
        XCTAssertEqual(connector.missingScopes.first?.id, "wormhole.write")
        XCTAssertEqual(connector.accountLabel, "primary@uberkiwi.com")
        XCTAssertEqual(connector.lastError, "Provider returned 502 once.")
        XCTAssertNotNil(connector.lastSyncedAt)
        XCTAssertEqual(connector.pendingApprovalID, "appr-conn-setup-conn-mystery")
    }

    func testCatalogDecodesSnakeCaseBoundaryNote() throws {
        let data = Data("""
        {
          "connectors": [
            {
              "id": "conn-x",
              "kind": "slack",
              "display_name": "Slack",
              "status": "connected",
              "sync_status": "ok",
              "write_policy": "always_ask",
              "capabilities": ["read", "write"],
              "scopes": [],
              "setup_kind": "oauth"
            }
          ],
          "boundary_note": "Daemon-owned writes only."
        }
        """.utf8)

        let catalog = try JSONDecoder().decode(HermesConnectorCatalog.self, from: data)
        XCTAssertEqual(catalog.connectors.count, 1)
        XCTAssertEqual(catalog.connectors.first?.kind, .slack)
        XCTAssertEqual(catalog.boundaryNote, "Daemon-owned writes only.")
    }

    func testSetupChallengeDecodesUnknownStateSafely() throws {
        let data = Data("""
        {
          "connector_id": "conn-x",
          "setup_kind": "oauth",
          "state": "stargate_alignment",
          "message": "Realigning stargate.",
          "approval_id": "appr-1"
        }
        """.utf8)

        let challenge = try JSONDecoder().decode(HermesConnectorSetupChallenge.self, from: data)
        XCTAssertEqual(challenge.state, .unknown)
        XCTAssertEqual(challenge.setupKind, .oauth)
        XCTAssertEqual(challenge.approvalID, "appr-1")
    }

    func testRoundTripPreservesPolicyAndScopes() throws {
        let connector = HermesConnector(
            id: "conn-x",
            kind: .github,
            displayName: "GitHub",
            summary: "Repos",
            status: .connected,
            syncStatus: .ok,
            writePolicy: .autoApproveLowRisk,
            capabilities: [.read, .write],
            scopes: [
                HermesConnectorScope(id: "repo:read", displayName: "Read", isGranted: true, isRequired: true),
                HermesConnectorScope(id: "pr:write", displayName: "PRs", isGranted: false, isRequired: true)
            ],
            setupKind: .oauth,
            accountLabel: "uberkiwi"
        )

        let data = try JSONEncoder().encode(connector)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["display_name"] as? String, "GitHub")
        XCTAssertEqual(object["write_policy"] as? String, "auto_approve_low_risk")
        XCTAssertEqual(object["setup_kind"] as? String, "oauth")
        let scopes = try XCTUnwrap(object["scopes"] as? [[String: Any]])
        XCTAssertEqual(scopes.count, 2)
        XCTAssertEqual(scopes.first?["display_name"] as? String, "Read")

        let decoded = try JSONDecoder().decode(HermesConnector.self, from: data)
        XCTAssertEqual(decoded, connector)
    }
}
