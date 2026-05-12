import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.3 — decoder coverage for `/v1/runs/{run_id}/events`
/// payload shapes. Every shape exercised against the byte-level
/// canonical evidence captured in
/// `Docs/Phases/Phase3/evidence/sse_runs_events.txt`.
///
/// The cornerstone test for upstream-Hermes robustness is
/// `testDecode_UnknownEventType_DecodesAsUnknown` — when Hermes adds
/// a new event type in the future, Diak must keep consuming the
/// stream, not crash. The matching pump-level test for the
/// "log + skip" behaviour lives in `RunStreamCoordinatorTests`.
final class RunEventPayloadTests: XCTestCase {

    private func event(_ data: String, type: String? = nil) -> RunEvent {
        RunEvent(event: type, id: nil, data: data)
    }

    // MARK: - message.delta

    func testDecode_MessageDelta_ExtractsTokenText() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"message.delta","run_id":"run_a","timestamp":1.0,"delta":" moon"}"#))
        XCTAssertEqual(payload, .messageDelta(text: " moon"))
    }

    func testDecode_MessageDelta_MissingDeltaFieldFallsBackToEmpty() throws {
        // Defensive — the decoder shouldn't throw if a delta event
        // lacks its text. Treats absent text as empty append.
        let payload = try RunEventPayload.decode(from: event(#"{"event":"message.delta","run_id":"r","timestamp":1.0}"#))
        XCTAssertEqual(payload, .messageDelta(text: ""))
    }

    func testDecode_MessageDelta_PreservesUnicode() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"message.delta","run_id":"r","timestamp":1.0,"delta":" ×"}"#))
        XCTAssertEqual(payload, .messageDelta(text: " ×"))
    }

    // MARK: - tool.started

    func testDecode_ToolStarted_ExtractsToolAndPreview() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"tool.started","run_id":"r","timestamp":1.0,"tool":"read_file","preview":"/tmp/sse_a_simple.sh"}"#))
        XCTAssertEqual(payload, .toolStarted(tool: "read_file", preview: "/tmp/sse_a_simple.sh"))
    }

    func testDecode_ToolStarted_PreviewOptional() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"tool.started","run_id":"r","timestamp":1.0,"tool":"terminal"}"#))
        XCTAssertEqual(payload, .toolStarted(tool: "terminal", preview: nil))
    }

    // MARK: - tool.completed

    func testDecode_ToolCompleted_HappyPath() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"tool.completed","run_id":"r","timestamp":2.0,"tool":"read_file","duration":1.325,"error":false}"#))
        XCTAssertEqual(payload, .toolCompleted(tool: "read_file", duration: 1.325, hadError: false))
    }

    func testDecode_ToolCompleted_ErrorFlagTrue() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"tool.completed","run_id":"r","timestamp":2.0,"tool":"terminal","duration":0.05,"error":true}"#))
        XCTAssertEqual(payload, .toolCompleted(tool: "terminal", duration: 0.05, hadError: true))
    }

    func testDecode_ToolCompleted_MissingDurationDecodesNil() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"tool.completed","run_id":"r","timestamp":2.0,"tool":"x"}"#))
        XCTAssertEqual(payload, .toolCompleted(tool: "x", duration: nil, hadError: false))
    }

    // MARK: - reasoning.available

    func testDecode_ReasoningAvailable_ExtractsText() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"reasoning.available","run_id":"r","timestamp":3.0,"text":"summary text"}"#))
        XCTAssertEqual(payload, .reasoningAvailable(text: "summary text"))
    }

    // MARK: - run.completed

    func testDecode_RunCompleted_WithUsage() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"run.completed","run_id":"r","timestamp":4.0,"output":"hello","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#))
        guard case .runCompleted(let output, let usage) = payload else {
            return XCTFail("Expected .runCompleted")
        }
        XCTAssertEqual(output, "hello")
        XCTAssertEqual(usage?.promptTokens, 10)
        XCTAssertEqual(usage?.completionTokens, 5)
        XCTAssertEqual(usage?.totalTokens, 15)
    }

    func testDecode_RunCompleted_NoOutputNoUsage() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"run.completed","run_id":"r","timestamp":4.0}"#))
        XCTAssertEqual(payload, .runCompleted(output: nil, usage: nil))
    }

    // MARK: - run.cancelled

    func testDecode_RunCancelled() throws {
        let payload = try RunEventPayload.decode(from: event(#"{"event":"run.cancelled","run_id":"r","timestamp":5.0}"#))
        XCTAssertEqual(payload, .runCancelled)
    }

    // MARK: - unknown event types (forward-compat contract)

    /// **Load-bearing for Hermes evolution.** When Hermes adds a new
    /// event type, Diak must continue consuming the stream — not
    /// crash. The decoder returns `.unknown` with the original event
    /// type so the consumer can log and skip.
    func testDecode_UnknownEventType_DecodesAsUnknown() throws {
        let raw = #"{"event":"tool.preflight","run_id":"r","timestamp":6.0,"tool":"future_tool"}"#
        let payload = try RunEventPayload.decode(from: event(raw))
        XCTAssertEqual(payload, .unknown(eventType: "tool.preflight", rawData: raw))
    }

    func testDecode_UnknownEventType_PreservesRawDataForLogging() throws {
        let raw = #"{"event":"reasoning.summary","run_id":"r","timestamp":7.0,"summary":"the model thought hard"}"#
        let payload = try RunEventPayload.decode(from: event(raw))
        guard case .unknown(let eventType, let rawData) = payload else {
            return XCTFail("Expected .unknown")
        }
        XCTAssertEqual(eventType, "reasoning.summary")
        XCTAssertEqual(rawData, raw)
    }

    // MARK: - malformed input (throws)

    func testDecode_NonJSONBody_ThrowsDataNotJSON() {
        XCTAssertThrowsError(try RunEventPayload.decode(from: event("not-json-just-text"))) { error in
            guard case RunEventPayload.DecodeError.dataNotJSON = error else {
                return XCTFail("Expected .dataNotJSON, got \(error)")
            }
        }
    }

    func testDecode_JSONWithoutEventField_ThrowsMissingEventField() {
        XCTAssertThrowsError(try RunEventPayload.decode(from: event(#"{"run_id":"r","timestamp":1.0}"#))) { error in
            XCTAssertEqual(error as? RunEventPayload.DecodeError, .missingEventField)
        }
    }

    // MARK: - Canonical evidence regression

    /// One-shot smoke test against a verbatim line from the WU3.1
    /// evidence file. If Hermes' event shape changes in a future
    /// release this test will fail and signal that REALITY.md
    /// needs re-investigation.
    func testDecode_CanonicalEvidenceFromWU31_ToolStarted() throws {
        let raw = #"{"event": "tool.started", "run_id": "run_df8e16be14994e57b04db984e49884e9", "timestamp": 1778551556.0137331, "tool": "read_file", "preview": "/tmp/sse_a_simple.sh"}"#
        let payload = try RunEventPayload.decode(from: event(raw))
        XCTAssertEqual(payload, .toolStarted(tool: "read_file", preview: "/tmp/sse_a_simple.sh"))
    }

    func testDecode_CanonicalEvidenceFromWU31_ToolCompletedWithDurationAndError() throws {
        let raw = #"{"event": "tool.completed", "run_id": "run_df8e16be14994e57b04db984e49884e9", "timestamp": 1778551557.3387442, "tool": "read_file", "duration": 1.325, "error": false}"#
        let payload = try RunEventPayload.decode(from: event(raw))
        XCTAssertEqual(payload, .toolCompleted(tool: "read_file", duration: 1.325, hadError: false))
    }

    func testDecode_CanonicalEvidenceFromWU31_MessageDelta() throws {
        let raw = #"{"event": "message.delta", "run_id": "run_df8e16be14994e57b04db984e49884e9", "timestamp": 1778551559.01047, "delta": "\n\n/tmp"}"#
        let payload = try RunEventPayload.decode(from: event(raw))
        XCTAssertEqual(payload, .messageDelta(text: "\n\n/tmp"))
    }
}
