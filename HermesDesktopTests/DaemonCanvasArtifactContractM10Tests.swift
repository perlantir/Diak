import XCTest
@testable import HermesDesktop

/// Pins the wire shape produced by `Scripts/diak_dev_daemon.py` for
/// the M10 canvas artifact and stream contracts. These are pure
/// decoding/state tests so they run inside the standard XCTest harness
/// without requiring a daemon process. If the compatibility daemon's
/// payload drifts, the literal JSON in this file must drift with it.
final class DaemonCanvasArtifactContractM10Tests: XCTestCase {

    /// Mirror of `canvas_artifact_payload("sess-diak-live-qa")` in
    /// `Scripts/diak_dev_daemon.py`. Keep these byte-for-byte equivalent
    /// so a contract regression in either side fails the suite.
    private static let cannedSessionPayload: String = #"""
    {
        "session_id": "sess-diak-live-qa",
        "boundary_note": "Compatibility daemon: artifacts are typed references only. Real browser/code/design execution stays in the production Hermes daemon.",
        "artifacts": [
            {
                "id": "canvas-art-doc",
                "session_id": "sess-diak-live-qa",
                "kind": "document",
                "title": "Diak QA notes",
                "summary": "Document tab fixture used by the compatibility daemon.",
                "preview": "Diak reads typed canvas artifacts through the Hermes Agent boundary; this fixture proves the wire shape.",
                "created_at": "2026-05-10T10:00:00Z",
                "ref": {"id": "file-qa-md", "kind": "file", "title": "qa-notes.md", "detail": "Docs/QA/qa-notes.md"}
            },
            {
                "id": "canvas-art-code",
                "session_id": "sess-diak-live-qa",
                "kind": "code",
                "title": "Diff fixture",
                "summary": "Code tab fixture; the daemon does not execute or write code.",
                "preview": "diff --git a/Diak.swift b/Diak.swift\n+ // compatibility daemon fixture",
                "created_at": "2026-05-10T10:00:00Z",
                "ref": {"id": "file-diak-diff", "kind": "file", "title": "Diak.swift", "detail": "HermesDesktop/Diak.swift"}
            },
            {
                "id": "canvas-art-browser",
                "session_id": "sess-diak-live-qa",
                "kind": "browser",
                "title": "Hermes Agent reference",
                "summary": "Browser tab fixture; the daemon does not navigate or screenshot.",
                "preview": "https://example.com/hermes-agent",
                "created_at": "2026-05-10T10:00:00Z",
                "ref": {"id": "link-hermes-agent", "kind": "link", "title": "Hermes Agent overview", "detail": "example.com"}
            },
            {
                "id": "canvas-art-design",
                "session_id": "sess-diak-live-qa",
                "kind": "design",
                "title": "Tab strip mock",
                "summary": "Design tab fixture; the daemon does not render images.",
                "preview": "Doc · Board · Browser · Code · Design",
                "created_at": "2026-05-10T10:00:00Z"
            },
            {
                "id": "canvas-art-board",
                "session_id": "sess-diak-live-qa",
                "kind": "board",
                "title": "QA punch list",
                "summary": "Board tab fixture; daemon does not mutate trackers.",
                "preview": "5 fixture artifacts pinned across the canvas tabs.",
                "created_at": "2026-05-10T10:00:00Z"
            }
        ]
    }
    """#

    func testDaemonCanvasArtifactsContractDecodesAllFiveTabs() throws {
        let data = Self.cannedSessionPayload.data(using: .utf8)!
        let payload = try JSONDecoder().decode(HermesCanvasArtifactList.self, from: data)

        XCTAssertEqual(payload.sessionID, "sess-diak-live-qa")
        XCTAssertEqual(payload.boundaryNote,
                       "Compatibility daemon: artifacts are typed references only. Real browser/code/design execution stays in the production Hermes daemon.")
        XCTAssertEqual(payload.artifacts.count, 5)

        let kinds = payload.artifacts.map { $0.kind }
        XCTAssertEqual(Set(kinds), Set([.document, .code, .browser, .design, .board]))

        let codeArtifact = try XCTUnwrap(payload.artifacts.first { $0.kind == .code })
        XCTAssertEqual(codeArtifact.codePreviewLanguage, "SWIFT")
        XCTAssertEqual(codeArtifact.codePreviewPath, "HermesDesktop/Diak.swift")

        let browserArtifact = try XCTUnwrap(payload.artifacts.first { $0.kind == .browser })
        XCTAssertEqual(browserArtifact.browserPreviewURL?.absoluteString,
                       "https://example.com/hermes-agent")
        XCTAssertEqual(browserArtifact.browserPreviewHost, "example.com")
    }

    func testDaemonCanvasArtifactsApplyToCanvasStatePerTab() throws {
        let data = Self.cannedSessionPayload.data(using: .utf8)!
        let payload = try JSONDecoder().decode(HermesCanvasArtifactList.self, from: data)

        var state = HermesCanvasState.bootstrap(sessionTitle: "Diak compatibility daemon")
        state.setArtifacts(payload.artifacts, boundaryNote: payload.boundaryNote)

        for tab in HermesCanvasTab.allCases {
            let primary = state.primaryArtifact(for: tab)
            XCTAssertNotNil(primary, "Expected primary artifact for tab \(tab)")
            XCTAssertEqual(primary?.kind.canvasTab, tab,
                           "Primary artifact for \(tab) should map back to that tab")
        }

        XCTAssertEqual(state.artifactBoundaryNote, payload.boundaryNote)
        XCTAssertTrue(state.secondaryArtifacts(for: .document).isEmpty,
                      "Daemon fixture pins one artifact per tab; document tab should have no secondaries")
    }

    /// Mirror of the SSE body returned by the compatibility daemon's
    /// `/sessions/{id}/stream` route. Pins the wire shape end-to-end so
    /// changes to the daemon stream events break the suite.
    func testDaemonStreamSSEContractDecodesIntoCanvasUpdate() async throws {
        let body = """
        data: {"type":"message_started","message_id":"msg-assistant-stream","session_id":"sess-diak-live-qa","role":"assistant"}

        data: {"type":"message_delta","message_id":"msg-assistant-stream","text_delta":"Diak compatibility stream is working. "}

        data: {"type":"message_delta","message_id":"msg-assistant-stream","text_delta":"No external side effects were performed."}

        data: {"type":"canvas_updated","update":{"type":"document_section_updated","title":"Findings","bullets":["Compatibility daemon stream parsed by canvas reducer."]}}

        data: {"type":"message_completed","message_id":"msg-assistant-stream"}

        data: {"type":"session_ended","session_id":"sess-diak-live-qa","status":"completed"}
        """

        DaemonContractURLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/sessions/sess-diak-live-qa/stream")
            return (200, Data(body.utf8), "text/event-stream")
        }
        defer { DaemonContractURLProtocolStub.handler = nil }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DaemonContractURLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)

        var events: [HermesStreamEvent] = []
        for try await event in client.streamEvents(sessionID: "sess-diak-live-qa") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 6)
        if case .canvasUpdated(.documentSectionUpdated(let title, let bullets)) = events[3] {
            XCTAssertEqual(title, "Findings")
            XCTAssertEqual(bullets, ["Compatibility daemon stream parsed by canvas reducer."])
        } else {
            XCTFail("Expected canvas_updated/document_section_updated as 4th event, got \(events[3])")
        }

        if case .sessionEnded(let id, let status) = events[5] {
            XCTAssertEqual(id, "sess-diak-live-qa")
            XCTAssertEqual(status, .completed)
        } else {
            XCTFail("Expected session_ended as last event, got \(events[5])")
        }
    }
}

private final class DaemonContractURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data, contentType) = Self.handler?(request) ?? (500, Data(), "text/plain")
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
