import Foundation
import XCTest
@testable import HermesDesktop

final class URLSessionHermesAPIClientM10Tests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStreamStub.reset()
    }

    func testStreamEventsConsumesSSECanvasAndToolEvents() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/sessions/sess-live/stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let payload = """
            event: message_started
            data: {"type":"message_started","message_id":"msg-1","session_id":"sess-live","role":"assistant"}

            data: {"type":"message_delta","message_id":"msg-1","text_delta":"Hello"}

            data: {"type":"canvas_updated","update":{"type":"document_section_updated","title":"Findings","bullets":["Live stream parsed"]}}

            data: {"type":"tool_started","message_id":"msg-1","activity":{"id":"tool-1","name":"Read file","status":"running","summary":"Inspecting"}}

            data: {"type":"session_ended","session_id":"sess-live","status":"completed"}
            """
            return (200, Data(payload.utf8), "text/event-stream")
        }

        var events: [HermesStreamEvent] = []
        for try await event in client.streamEvents(sessionID: "sess-live") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[0], .messageStarted(messageID: "msg-1", sessionID: "sess-live", role: .assistant))
        XCTAssertEqual(events[1], .messageDelta(messageID: "msg-1", textDelta: "Hello"))
        XCTAssertEqual(events[2], .canvasUpdated(.documentSectionUpdated(title: "Findings", bullets: ["Live stream parsed"])))
        if case .toolStarted(let messageID, let activity) = events[3] {
            XCTAssertEqual(messageID, "msg-1")
            XCTAssertEqual(activity.id, "tool-1")
            XCTAssertEqual(activity.status, .running)
        } else {
            XCTFail("Expected toolStarted event")
        }
        XCTAssertEqual(events[4], .sessionEnded(sessionID: "sess-live", status: .completed))
    }

    func testStreamEventsMapsHTTPFailure() async throws {
        let client = makeClient { _ in
            (503, Data("daemon down".utf8), "text/plain")
        }

        do {
            for try await _ in client.streamEvents(sessionID: "sess-live") {}
            XCTFail("Expected HTTP error")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .http(status: 503, body: "daemon down"))
        }
    }

    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data, String)) -> URLSessionHermesAPIClient {
        URLProtocolStreamStub.reset()
        URLProtocolStreamStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStreamStub.self]
        let session = URLSession(configuration: config)
        return URLSessionHermesAPIClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
    }
}

private final class URLProtocolStreamStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data, String))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data, contentType) = try Self.handler?(request) ?? (500, Data(), "text/plain")
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
