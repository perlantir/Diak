import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.3 — `StreamingAssistantMessage` event-application
/// semantics. Covers the segment-interleaving rules, tool-call
/// matching (started→completed by name FIFO), phase transitions,
/// and the toolCalls/assembledText projections used at persist time.
@MainActor
final class StreamingAssistantMessageTests: XCTestCase {

    // MARK: - appendDelta + text segment management

    func testAppendDelta_FirstTokenCreatesTextSegment() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("Hello")
        XCTAssertEqual(msg.segments.count, 1)
        guard case .text(let textSeg) = msg.segments[0] else {
            return XCTFail("Expected .text segment")
        }
        XCTAssertEqual(textSeg.state.text, "Hello")
    }

    func testAppendDelta_SubsequentTokensAppendToSameSegment() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("Hello")
        msg.appendDelta(", ")
        msg.appendDelta("world")
        XCTAssertEqual(msg.segments.count, 1, "deltas without intervening tool calls must merge into one segment")
        XCTAssertEqual(msg.assembledText, "Hello, world")
    }

    func testAppendDelta_EmptyTokenIsNoOp() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("hello")
        msg.appendDelta("")
        XCTAssertEqual(msg.segments.count, 1)
        XCTAssertEqual(msg.assembledText, "hello")
    }

    // MARK: - Tool segment interleaving

    func testToolStarted_CreatesNewToolSegment() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("Reading file ")
        _ = msg.toolStarted(tool: "read_file", preview: "/etc/hosts")
        XCTAssertEqual(msg.segments.count, 2)
        guard case .tool(let call) = msg.segments[1] else {
            return XCTFail("Expected .tool segment")
        }
        XCTAssertEqual(call.toolName, "read_file")
        XCTAssertEqual(call.preview, "/etc/hosts")
        XCTAssertEqual(call.status, .running)
    }

    func testAppendDelta_AfterToolCreatesNewTextSegment() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("Before ")
        _ = msg.toolStarted(tool: "x", preview: nil)
        msg.appendDelta("after")
        XCTAssertEqual(msg.segments.count, 3,
                       "tool segments split the text run; the next delta opens a new text segment")
        XCTAssertEqual(msg.assembledText, "Before after",
                       "assembledText concatenates only text segments and skips the tool")
    }

    // MARK: - Tool matching by name (no tool_call_id in /v1/runs evidence)

    func testToolCompleted_MatchesMostRecentRunningCallByName() {
        let msg = StreamingAssistantMessage(runId: "r1")
        _ = msg.toolStarted(tool: "read_file", preview: "a")
        _ = msg.toolStarted(tool: "write_file", preview: "b")
        msg.toolCompleted(tool: "read_file", duration: 1.2, hadError: false)

        guard case .tool(let read) = msg.segments[0],
              case .tool(let write) = msg.segments[1] else {
            return XCTFail("Expected two tool segments")
        }
        XCTAssertEqual(read.status, .completed, "read_file should match its own completion")
        XCTAssertEqual(read.durationSeconds, 1.2)
        XCTAssertEqual(write.status, .running, "write_file should still be in flight")
    }

    func testToolCompleted_StackOrder_MostRecentRunningWithMatchingNameWins() {
        // Two parallel calls of the same tool name. Completion
        // matches the MOST RECENT running call (LIFO by index in
        // the loop, but only running ones are considered).
        let msg = StreamingAssistantMessage(runId: "r1")
        _ = msg.toolStarted(tool: "terminal", preview: "first")
        _ = msg.toolStarted(tool: "terminal", preview: "second")
        msg.toolCompleted(tool: "terminal", duration: 0.5, hadError: false)

        guard case .tool(let first) = msg.segments[0],
              case .tool(let second) = msg.segments[1] else {
            return XCTFail("Expected two terminal segments")
        }
        XCTAssertEqual(first.status, .running)
        XCTAssertEqual(second.status, .completed,
                       "stack-by-name matcher closes the second (most recent) running call first")
    }

    func testToolCompleted_NoMatchingRunningCall_DroppedSilently() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.toolCompleted(tool: "ghost", duration: 1.0, hadError: false)
        XCTAssertTrue(msg.segments.isEmpty,
                      "completion without a matching started event is a no-op")
    }

    // MARK: - update(toolCallID:) (WU3.5 hook)

    func testUpdateToolCallID_TransformsCallInPlace() {
        let msg = StreamingAssistantMessage(runId: "r1")
        let id = msg.toolStarted(tool: "x", preview: nil)
        msg.update(toolCallID: id) { call in
            call.interrupt(at: Date())
        }
        guard case .tool(let call) = msg.segments[0] else {
            return XCTFail("Expected tool segment")
        }
        XCTAssertEqual(call.status, .interrupted,
                       "WU3.5 will use this hook to mark tool calls .interrupted or .alreadyExecuted")
    }

    // MARK: - Phase transitions

    func testTransitionToCompleted_FinalizesTextSegmentPhase() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("hello")
        msg.transition(to: .completed)
        XCTAssertEqual(msg.phase, .completed)
        guard case .text(let textSeg) = msg.segments[0] else {
            return XCTFail("Expected .text segment")
        }
        XCTAssertEqual(textSeg.state.phase, .completed,
                       "text segments must propagate phase so the streaming caret retracts")
    }

    func testTransitionToInterrupted_PropagatesAsInterruptedTextPhase() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("partial")
        msg.transition(to: .interrupted(reason: "TCP drop"))
        guard case .text(let textSeg) = msg.segments[0] else {
            return XCTFail("Expected .text segment")
        }
        guard case .interrupted(let reason) = textSeg.state.phase else {
            return XCTFail("Expected text segment phase .interrupted")
        }
        XCTAssertEqual(reason, "TCP drop")
    }

    func testTransitionToFailed_PropagatesAsErroredTextPhase() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("partial")
        msg.transition(to: .failed(reason: "API error"))
        guard case .text(let textSeg) = msg.segments[0] else {
            return XCTFail("Expected .text segment")
        }
        guard case .errored = textSeg.state.phase else {
            return XCTFail("Expected text segment phase .errored")
        }
    }

    // MARK: - Projections

    func testToolCalls_ProjectsOnlyToolSegments() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("intro ")
        _ = msg.toolStarted(tool: "x", preview: nil)
        msg.appendDelta(" outro")
        XCTAssertEqual(msg.toolCalls.count, 1)
        XCTAssertEqual(msg.toolCalls[0].toolName, "x")
    }

    func testAssembledText_OnlyTextSegments() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.appendDelta("a")
        _ = msg.toolStarted(tool: "x", preview: nil)
        msg.appendDelta("b")
        XCTAssertEqual(msg.assembledText, "ab")
    }

    func testRecordReasoning_StoresForInspectorPane() {
        let msg = StreamingAssistantMessage(runId: "r1")
        msg.recordReasoning("the model considered three options")
        XCTAssertEqual(msg.reasoning, "the model considered three options")
    }
}
