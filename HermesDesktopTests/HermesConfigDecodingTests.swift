import XCTest
@testable import HermesDesktop

final class HermesConfigDecodingTests: XCTestCase {

    func testConfigSnapshotDecodesSnakeCaseAndDefaults() throws {
        let json = """
        {
          "profiles": [
            {
              "id": "prof-default",
              "display_name": "Nick",
              "role": "engineer",
              "default_project_label": "HermesDesktop",
              "is_active": true
            }
          ],
          "active_profile_id": "prof-default",
          "providers": [
            {
              "id": "prov-local",
              "display_name": "Local",
              "kind": "ollama",
              "status": "ready",
              "default_model": "llama3.3:70b",
              "available_models": ["llama3.3:70b"],
              "needs_api_key": false,
              "has_api_key": true,
              "restart_required": true
            }
          ],
          "tools": [
            {
              "id": "tool-shell",
              "name": "Terminal",
              "description": "Run commands",
              "can_read": true,
              "can_write": true,
              "can_destroy": true,
              "policy": "always_ask",
              "is_enabled": true,
              "restart_required": false
            }
          ],
          "security": {
            "trusted_folders": [
              { "id": "fold-1", "path": "/tmp/demo", "allows_writes": true }
            ],
            "log_redaction": "strict",
            "log_retention_days": 30,
            "telemetry_enabled": false,
            "offline_mode_enabled": true,
            "restart_required": false
          },
          "daemon": {
            "version": "0.42.0",
            "build": "abc123",
            "profile": "local-dev",
            "uptime_seconds": 12.5,
            "log_path": "/Users/nick/Library/Logs/Hermes/daemon.log",
            "recent_lines": ["ready"],
            "last_checked_at": "2026-05-09T23:00:00Z"
          }
        }
        """

        let snapshot = try JSONDecoder().decode(HermesConfigSnapshot.self,
                                                from: Data(json.utf8))

        XCTAssertEqual(snapshot.activeProfileID, "prof-default")
        XCTAssertEqual(snapshot.profiles.first?.displayName, "Nick")
        XCTAssertEqual(snapshot.providers.first?.kind, .ollama)
        XCTAssertEqual(snapshot.providers.first?.restartRequired, true)
        XCTAssertEqual(snapshot.tools.first?.capabilities, [.read, .write, .destructive])
        XCTAssertEqual(snapshot.tools.first?.policy, .alwaysAsk)
        XCTAssertEqual(snapshot.security.logRedaction, .strict)
        XCTAssertEqual(snapshot.security.trustedFolders.first?.allowsWrites, true)
        XCTAssertEqual(snapshot.daemon.recentLines, ["ready"])
        XCTAssertNotNil(snapshot.daemon.lastCheckedAt)
    }

    func testConfigEnumsDecodeUnknownValuesSafely() throws {
        let provider = try JSONDecoder().decode(HermesModelProvider.self, from: Data("""
        {
          "id": "prov-x",
          "display_name": "Future Provider",
          "kind": "future_kind",
          "status": "brand_new_state"
        }
        """.utf8))
        XCTAssertEqual(provider.kind, .unknown)
        XCTAssertEqual(provider.status, .unknown)
        XCTAssertFalse(provider.needsAPIKey)
        XCTAssertFalse(provider.hasAPIKey)

        let tool = try JSONDecoder().decode(HermesToolPermission.self, from: Data("""
        {
          "id": "tool-x",
          "name": "Future Tool",
          "policy": "future_policy"
        }
        """.utf8))
        XCTAssertEqual(tool.policy, .unknown)
        XCTAssertFalse(tool.canRead)
        XCTAssertTrue(tool.isEnabled)
    }
}
