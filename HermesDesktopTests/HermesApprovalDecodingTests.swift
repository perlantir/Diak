import XCTest
@testable import HermesDesktop

final class HermesApprovalDecodingTests: XCTestCase {

    func testTerminalApprovalDecodes() throws {
        let json = Data("""
        {
          "id": "appr-001",
          "title": "Run migration",
          "summary": "Apply pending migrations.",
          "kind": "terminal_command",
          "status": "PENDING",
          "risk": "high",
          "created_at": "2026-05-09T22:30:00Z",
          "updated_at": "2026-05-09T22:30:30.500Z",
          "session_id": "sess-002",
          "session_title": "Migration helper",
          "tool_name": "shell.run",
          "requester": "Hermes Agent",
          "terminal_command": {
            "command": "npm run migrate",
            "working_directory": "/tmp/hermes",
            "shell": "/bin/zsh",
            "estimated_duration_seconds": 30
          }
        }
        """.utf8)

        let appr = try JSONDecoder().decode(HermesApprovalRequest.self, from: json)

        XCTAssertEqual(appr.id, "appr-001")
        XCTAssertEqual(appr.kind, .terminalCommand)
        XCTAssertEqual(appr.status, .pending)
        XCTAssertEqual(appr.risk, .high)
        XCTAssertEqual(appr.sessionTitle, "Migration helper")
        guard case .terminalCommand(let payload) = appr.payload else {
            return XCTFail("Expected terminal payload")
        }
        XCTAssertEqual(payload.command, "npm run migrate")
        XCTAssertEqual(payload.workingDirectory, "/tmp/hermes")
        XCTAssertEqual(payload.estimatedDurationSeconds, 30)
    }

    func testFileWriteApprovalDecodes() throws {
        let json = Data("""
        {
          "id": "appr-002",
          "title": "Write file",
          "kind": "file_write",
          "status": "pending",
          "risk": "medium",
          "created_at": "2026-05-09T22:00:00Z",
          "updated_at": "2026-05-09T22:00:00Z",
          "file_write": {
            "path": "README.md",
            "summary": "Tighten intro.",
            "unified_diff": "@@\\n-old line\\n+new line",
            "added_lines": 1,
            "removed_lines": 1
          }
        }
        """.utf8)

        let appr = try JSONDecoder().decode(HermesApprovalRequest.self, from: json)

        XCTAssertEqual(appr.kind, .fileWrite)
        guard case .fileWrite(let payload) = appr.payload else {
            return XCTFail("Expected file write payload")
        }
        XCTAssertEqual(payload.path, "README.md")
        XCTAssertEqual(payload.addedLines, 1)
        XCTAssertEqual(payload.removedLines, 1)
        XCTAssertTrue(payload.unifiedDiff.contains("+new line"))
    }

    func testConnectorApprovalDecodes() throws {
        let json = Data("""
        {
          "id": "appr-003",
          "title": "Send",
          "kind": "connector_send",
          "status": "pending",
          "risk": "critical",
          "created_at": "2026-05-09T22:00:00Z",
          "updated_at": "2026-05-09T22:00:00Z",
          "connector_send": {
            "connector_name": "Slack",
            "endpoint": "POST chat.postMessage",
            "method": "POST",
            "recipient": "#release",
            "body_preview": "hello world"
          }
        }
        """.utf8)

        let appr = try JSONDecoder().decode(HermesApprovalRequest.self, from: json)

        guard case .connectorSend(let payload) = appr.payload else {
            return XCTFail("Expected connector payload")
        }
        XCTAssertEqual(payload.connectorName, "Slack")
        XCTAssertEqual(payload.recipient, "#release")
        XCTAssertEqual(payload.method, "POST")
        XCTAssertEqual(appr.risk, .critical)
    }

    func testApprovalToleratesUnknownKindAndStatus() throws {
        let json = Data("""
        {
          "id": "appr-x",
          "title": "Mystery",
          "kind": "telepathy",
          "status": "ruminating",
          "risk": "vague",
          "created_at": "2026-05-09T22:00:00Z",
          "updated_at": "2026-05-09T22:00:00Z"
        }
        """.utf8)

        let appr = try JSONDecoder().decode(HermesApprovalRequest.self, from: json)

        XCTAssertEqual(appr.kind, .unknown)
        XCTAssertEqual(appr.status, .unknown)
        XCTAssertEqual(appr.risk, .unknown)
        XCTAssertEqual(appr.payload, .unknown)
        // Unknown risk maps to a non-zero display risk so the UI never
        // implies safety it can't actually verify.
        XCTAssertEqual(appr.displayRisk, .medium)
    }

    func testActionEvidenceDecodes() throws {
        let json = Data("""
        {
          "id": "evd-1",
          "title": "Wrote README.md",
          "summary": "+3 lines",
          "status": "COMPLETED",
          "occurred_at": "2026-05-09T22:00:00Z",
          "actor": "You",
          "tool_name": "files.write",
          "approval_id": "appr-002",
          "session_id": "sess-001",
          "artifacts": [
            { "id": "a-1", "kind": "file", "title": "README.md", "detail": "+3" }
          ]
        }
        """.utf8)

        let evidence = try JSONDecoder().decode(HermesActionEvidence.self, from: json)

        XCTAssertEqual(evidence.status, .completed)
        XCTAssertEqual(evidence.artifacts.count, 1)
        XCTAssertEqual(evidence.artifacts.first?.kind, .file)
    }

    func testActionEvidenceToleratesUnknownStatusAndArtifactKind() throws {
        let json = Data("""
        {
          "id": "evd-x",
          "title": "Wat",
          "status": "vibing",
          "occurred_at": "2026-05-09T22:00:00Z",
          "artifacts": [
            { "id": "art-x", "kind": "hologram", "title": "?" }
          ]
        }
        """.utf8)

        let evidence = try JSONDecoder().decode(HermesActionEvidence.self, from: json)

        XCTAssertEqual(evidence.status, .unknown)
        XCTAssertEqual(evidence.artifacts.first?.kind, .unknown)
    }
}
