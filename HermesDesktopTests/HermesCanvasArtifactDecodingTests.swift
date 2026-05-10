import XCTest
@testable import HermesDesktop

final class HermesCanvasArtifactDecodingTests: XCTestCase {

    func testCanvasArtifactDecodesSnakeCaseAndOptionalRef() throws {
        let json = #"""
        {
            "id": "canvas-art-001",
            "session_id": "sess-001",
            "kind": "document",
            "title": "Architecture summary",
            "summary": "Module-by-module read with risk callouts.",
            "preview": "Hermes Agent owns daemon-side execution.",
            "created_at": "2026-05-09T10:00:00Z",
            "updated_at": "2026-05-09T11:30:00Z",
            "ref": {
                "id": "file-arch-md",
                "kind": "file",
                "title": "architecture.md",
                "detail": "Docs/architecture.md"
            }
        }
        """#.data(using: .utf8)!

        let artifact = try JSONDecoder().decode(HermesCanvasArtifact.self, from: json)
        XCTAssertEqual(artifact.id, "canvas-art-001")
        XCTAssertEqual(artifact.sessionID, "sess-001")
        XCTAssertEqual(artifact.kind, .document)
        XCTAssertEqual(artifact.kind.canvasTab, .document)
        XCTAssertEqual(artifact.title, "Architecture summary")
        XCTAssertEqual(artifact.preview, "Hermes Agent owns daemon-side execution.")
        XCTAssertEqual(artifact.ref?.kind, .file)
        XCTAssertEqual(artifact.ref?.title, "architecture.md")
        XCTAssertNotNil(artifact.updatedAt)
    }

    func testCanvasArtifactTolerantOfUnknownKind() throws {
        let json = #"""
        {
            "id": "canvas-art-zz",
            "session_id": "sess-x",
            "kind": "telepathy",
            "title": "From the future",
            "created_at": "2026-05-09T10:00:00Z"
        }
        """#.data(using: .utf8)!

        let artifact = try JSONDecoder().decode(HermesCanvasArtifact.self, from: json)
        XCTAssertEqual(artifact.kind, .unknown)
        // Unknown kinds still surface under document so the UI never loses them.
        XCTAssertEqual(artifact.kind.canvasTab, .document)
        XCTAssertNil(artifact.summary)
        XCTAssertNil(artifact.preview)
        XCTAssertNil(artifact.updatedAt)
        XCTAssertNil(artifact.ref)
    }

    func testCanvasArtifactKindMapsToCanvasTab() {
        XCTAssertEqual(HermesCanvasArtifact.Kind.code.canvasTab, .code)
        XCTAssertEqual(HermesCanvasArtifact.Kind.browser.canvasTab, .browser)
        XCTAssertEqual(HermesCanvasArtifact.Kind.design.canvasTab, .design)
        XCTAssertEqual(HermesCanvasArtifact.Kind.board.canvasTab, .board)
        XCTAssertEqual(HermesCanvasArtifact.Kind.other.canvasTab, .document)
    }

    func testCanvasArtifactListDecodesBoundaryNote() throws {
        let json = #"""
        {
            "session_id": "sess-001",
            "boundary_note": "Daemon owns execution.",
            "artifacts": [
                {
                    "id": "a-1",
                    "session_id": "sess-001",
                    "kind": "code",
                    "title": "Diff",
                    "created_at": "2026-05-09T10:00:00Z"
                }
            ]
        }
        """#.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HermesCanvasArtifactList.self, from: json)
        XCTAssertEqual(payload.sessionID, "sess-001")
        XCTAssertEqual(payload.boundaryNote, "Daemon owns execution.")
        XCTAssertEqual(payload.artifacts.count, 1)
        XCTAssertEqual(payload.artifacts.first?.kind, .code)
    }

    func testCanvasArtifactListDecodesEmptyArtifacts() throws {
        let json = #"""
        { "session_id": "sess-blank", "artifacts": [] }
        """#.data(using: .utf8)!

        let payload = try JSONDecoder().decode(HermesCanvasArtifactList.self, from: json)
        XCTAssertEqual(payload.sessionID, "sess-blank")
        XCTAssertTrue(payload.artifacts.isEmpty)
        XCTAssertNil(payload.boundaryNote)
    }
}
