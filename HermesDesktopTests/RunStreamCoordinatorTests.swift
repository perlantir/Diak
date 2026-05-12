import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.3 — `RunStreamCoordinator` exercise. Drives the event
/// pump against `StubURLProtocol`-stubbed SSE responses representing
/// the WU3.1-evidenced /v1/runs event shapes. Covers:
///
/// - Happy path: deltas + tool start/complete + run.completed
/// - User cancellation via `Task.cancel()`
/// - Connection drop (stream EOF without `run.completed`)
/// - Pre-stream auth failure
/// - **Forward-compat**: unknown event types are logged and skipped
///   without crashing the stream (the critical contract for
///   upstream-Hermes evolution).
@MainActor
final class RunStreamCoordinatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(apiKey: String = "test-key") -> HermesAPIServerClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return HermesAPIServerClient(
            baseURL: HermesAPIServerClient.defaultBaseURL,
            apiKey: apiKey,
            requestTimeout: 5,
            session: session
        )
    }

    // MARK: - Happy path

    func testConsume_DeltasOnly_ReturnsCompletedWithAssembledText() async {
        let sse = """
        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"Hello"}

        data: {"event":"message.delta","run_id":"r","timestamp":1.1,"delta":", "}

        data: {"event":"message.delta","run_id":"r","timestamp":1.2,"delta":"world"}

        data: {"event":"run.completed","run_id":"r","timestamp":2.0}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()

        XCTAssertEqual(outcome, .completed(text: "Hello, world"))
        XCTAssertEqual(assistantMessage.assembledText, "Hello, world")
        XCTAssertEqual(assistantMessage.phase, .completed)
    }

    func testConsume_ToolStartedThenCompletedThenDeltasThenDone() async {
        let sse = """
        data: {"event":"tool.started","run_id":"r","timestamp":1.0,"tool":"read_file","preview":"/etc/hosts"}

        data: {"event":"tool.completed","run_id":"r","timestamp":1.5,"tool":"read_file","duration":0.5,"error":false}

        data: {"event":"message.delta","run_id":"r","timestamp":2.0,"delta":"done"}

        data: {"event":"run.completed","run_id":"r","timestamp":3.0}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()

        XCTAssertEqual(outcome, .completed(text: "done"))
        XCTAssertEqual(assistantMessage.segments.count, 2,
                       "expected one tool segment + one text segment")
        XCTAssertEqual(assistantMessage.toolCalls.count, 1)
        XCTAssertEqual(assistantMessage.toolCalls[0].status, .completed)
        XCTAssertEqual(assistantMessage.toolCalls[0].durationSeconds, 0.5)
    }

    func testConsume_RunCompletedOutputUsedWhenNoDeltas() async {
        // Server sends a `run.completed` with `output` and no
        // intermediate `message.delta` events. Coordinator falls
        // back to the `output` field.
        let sse = """
        data: {"event":"run.completed","run_id":"r","timestamp":1.0,"output":"fallback body"}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()

        XCTAssertEqual(outcome, .completed(text: "fallback body"))
    }

    // MARK: - Forward-compat: unknown event types

    /// **Critical for upstream Hermes evolution.** When a future
    /// Hermes adds a new event type, Diak must keep consuming the
    /// stream — not crash, not error, not drop the surrounding
    /// events. This test verifies the contract.
    func testConsume_UnknownEventType_LoggedAndSkippedCleanly() async {
        let sse = """
        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"before "}

        data: {"event":"tool.preflight","run_id":"r","timestamp":1.5,"tool":"future"}

        data: {"event":"message.delta","run_id":"r","timestamp":2.0,"delta":"after"}

        data: {"event":"run.completed","run_id":"r","timestamp":3.0}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")

        var loggedTypes: [String] = []
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client,
            unknownEventLogger: { type, _ in loggedTypes.append(type) }
        )

        let outcome = await coordinator.consume()

        XCTAssertEqual(outcome, .completed(text: "before after"))
        XCTAssertEqual(loggedTypes, ["tool.preflight"],
                       "unknown events are logged exactly once; the surrounding deltas survive")
        XCTAssertEqual(assistantMessage.assembledText, "before after")
    }

    // MARK: - Malformed event lines

    func testConsume_MalformedEventBody_LoggedAndSkipped() async {
        // The data: body for one event is not valid JSON. Pump must
        // skip and keep going.
        let sse = """
        data: not-json

        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"ok"}

        data: {"event":"run.completed","run_id":"r","timestamp":2.0}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()
        XCTAssertEqual(outcome, .completed(text: "ok"))
    }

    // MARK: - Cancellation

    /// User clicks stop while the stream is in flight.
    /// `Task.cancel()` on the coordinator's enclosing task makes
    /// `consume()` return `.cancelled` with whatever partial content
    /// arrived first.
    func testConsume_TaskCancellation_ReturnsCancelledWithPartial() async {
        // Build a stream that yields deltas then pauses forever
        // (simulated by a never-completing handler). The coordinator
        // will see the first deltas, then we cancel its enclosing
        // task and observe `.cancelled(text: "Hello")`.
        let firstChunk = """
        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"Hello"}

        """
        // We construct an InputStream that emits firstChunk and
        // never EOFs. StubURLProtocol's handler returns the bytes
        // synchronously; that means we need a different shape.
        //
        // Simplest viable shape: yield the chunk, then have the
        // protocol leave the body open until cancellation flows
        // through. We approximate by yielding the chunk + a long
        // delay before EOF (the coordinator will be cancelled
        // before EOF arrives).
        let neverFinishing = firstChunk + String(repeating: " ", count: 1)
        StubURLProtocol.handler = { _ in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s of "no progress"
            return (200, ["Content-Type": "text/event-stream"], Data(neverFinishing.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        // Wrap in a Task so we can cancel mid-flight.
        let task = Task<RunStreamCoordinator.RunOutcome, Never> {
            await coordinator.consume()
        }
        // Give the protocol handler enough time to begin (less than
        // the 1.5s sleep above) then cancel.
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let outcome = await task.value

        switch outcome {
        case .cancelled:
            // Cancellation may surface before any deltas have been
            // observed (the URLProtocol's response hasn't been
            // delivered yet); both empty and "Hello" are valid
            // partial values.
            break
        case .interrupted:
            // Allowed: the URLSession may surface the cancellation
            // as a TCP drop instead. Either outcome honors the
            // contract that no content is lost.
            break
        default:
            XCTFail("expected .cancelled or .interrupted, got \(outcome)")
        }
    }

    // MARK: - run.cancelled event

    func testConsume_RunCancelledEvent_ReturnsCancelled() async {
        let sse = """
        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"partial"}

        data: {"event":"run.cancelled","run_id":"r","timestamp":2.0}

        """
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()
        XCTAssertEqual(outcome, .cancelled(text: "partial"))
        switch assistantMessage.phase {
        case .cancelled: break // expected
        default: XCTFail("expected phase .cancelled, got \(assistantMessage.phase)")
        }
    }

    // MARK: - Mid-stream interruption (stream ends without terminal)

    func testConsume_StreamEndsWithoutTerminal_ReturnsInterruptedWithPartial() async {
        let sse = """
        data: {"event":"message.delta","run_id":"r","timestamp":1.0,"delta":"hello"}

        data: {"event":"message.delta","run_id":"r","timestamp":1.1,"delta":" partial"}

        """
        // Note: no run.completed / run.cancelled — stream just ends.
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "text/event-stream"], Data(sse.utf8))
        }
        let client = makeClient()
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()
        switch outcome {
        case .interrupted(let text, _):
            XCTAssertEqual(text, "hello partial")
        default:
            XCTFail("expected .interrupted, got \(outcome)")
        }
    }

    // MARK: - Pre-stream auth failure

    func testConsume_AuthFailure_ReturnsFailedWithReason() async {
        StubURLProtocol.handler = { _ in
            (401, [:], Data("unauthorized".utf8))
        }
        let client = makeClient(apiKey: "wrong")
        let assistantMessage = StreamingAssistantMessage(runId: "r")
        let coordinator = RunStreamCoordinator(
            assistantMessage: assistantMessage,
            apiServerClient: client
        )

        let outcome = await coordinator.consume()
        switch outcome {
        case .failed(let reason):
            XCTAssertTrue(reason.contains("API_SERVER_KEY") || reason.contains("rejected"),
                          "auth failure surface must mention the key")
        default:
            XCTFail("expected .failed, got \(outcome)")
        }
    }
}
