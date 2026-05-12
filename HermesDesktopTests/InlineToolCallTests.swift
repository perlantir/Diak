import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.4 — `InlineToolCall` state machine and elapsed-time
/// math. Covers the four-state contract from Decision #17 (running,
/// completed, interrupted, alreadyExecuted) plus the Codable round-
/// trip needed for `DiakMessage.toolCallsJSON` persistence.
final class InlineToolCallTests: XCTestCase {

    private let anchor = Date(timeIntervalSinceReferenceDate: 100)

    // MARK: - Construction defaults

    func testInit_DefaultsToRunning() {
        let call = InlineToolCall(toolName: "read_file", startedAt: anchor)
        XCTAssertEqual(call.status, .running)
        XCTAssertFalse(call.hadError)
        XCTAssertNil(call.finishedAt)
        XCTAssertNil(call.durationSeconds)
        XCTAssertEqual(call.toolName, "read_file")
    }

    // MARK: - .running → .completed

    func testComplete_TransitionsRunningToCompleted_WithServerDuration() {
        var call = InlineToolCall(toolName: "read_file", startedAt: anchor)
        let later = anchor.addingTimeInterval(1.3)
        call.complete(at: later, durationSeconds: 1.325, hadError: false)
        XCTAssertEqual(call.status, .completed)
        XCTAssertEqual(call.finishedAt, later)
        XCTAssertEqual(call.durationSeconds, 1.325)
        XCTAssertFalse(call.hadError)
    }

    func testComplete_DurationFallsBackToWallClock() {
        // Server didn't report duration; the value type computes it.
        var call = InlineToolCall(toolName: "x", startedAt: anchor)
        let later = anchor.addingTimeInterval(2.5)
        call.complete(at: later, durationSeconds: nil, hadError: false)
        XCTAssertEqual(call.durationSeconds ?? .nan, 2.5, accuracy: 0.001)
    }

    func testComplete_PreservesHadError() {
        var call = InlineToolCall(toolName: "terminal", startedAt: anchor)
        call.complete(at: anchor.addingTimeInterval(0.1), durationSeconds: 0.1, hadError: true)
        XCTAssertTrue(call.hadError)
        XCTAssertEqual(call.status, .completed)
    }

    func testComplete_IdempotentOnAlreadyCompleted() {
        // Defensive: a duplicate `tool.completed` from upstream
        // shouldn't reset the wall-clock duration to zero.
        var call = InlineToolCall(toolName: "x", startedAt: anchor)
        call.complete(at: anchor.addingTimeInterval(1.0), durationSeconds: 1.0, hadError: false)
        let firstDuration = call.durationSeconds
        call.complete(at: anchor.addingTimeInterval(10), durationSeconds: 10, hadError: true)
        XCTAssertEqual(call.durationSeconds, firstDuration,
                       "completed→completed is a no-op so the first observation wins")
        XCTAssertFalse(call.hadError)
    }

    // MARK: - .running → .interrupted (WU3.5 design hook)

    func testInterrupt_TransitionsRunningToInterrupted() {
        var call = InlineToolCall(toolName: "long_tool", startedAt: anchor)
        call.interrupt(at: anchor.addingTimeInterval(0.5))
        XCTAssertEqual(call.status, .interrupted)
        XCTAssertEqual(call.durationSeconds ?? .nan, 0.5, accuracy: 0.001)
    }

    func testInterrupt_NoOpOnCompletedCall() {
        var call = InlineToolCall(toolName: "fast_tool", startedAt: anchor)
        call.complete(at: anchor.addingTimeInterval(0.05), durationSeconds: 0.05, hadError: false)
        let beforeStatus = call.status
        call.interrupt(at: anchor.addingTimeInterval(10))
        XCTAssertEqual(call.status, beforeStatus,
                       "stop arriving after completion must NOT downgrade to .interrupted; that's the WU3.5 .alreadyExecuted case")
    }

    // MARK: - .running → .alreadyExecuted (WU3.5 design hook)

    func testMarkAlreadyExecuted_TransitionsAndPreservesDuration() {
        var call = InlineToolCall(toolName: "fast_tool", startedAt: anchor)
        call.complete(at: anchor.addingTimeInterval(0.05), durationSeconds: 0.05, hadError: false)
        call.markAlreadyExecuted(at: anchor.addingTimeInterval(0.2))
        XCTAssertEqual(call.status, .alreadyExecuted)
        XCTAssertEqual(call.durationSeconds, 0.05,
                       "alreadyExecuted from completed preserves the server-reported duration")
    }

    func testMarkAlreadyExecuted_ComputesDurationIfMissing() {
        var call = InlineToolCall(toolName: "x", startedAt: anchor)
        call.markAlreadyExecuted(at: anchor.addingTimeInterval(0.07))
        XCTAssertEqual(call.durationSeconds ?? .nan, 0.07, accuracy: 0.001)
    }

    // MARK: - elapsedSeconds(at:)

    func testElapsedSeconds_RunningReflectsLiveClock() {
        let call = InlineToolCall(toolName: "x", startedAt: anchor, status: .running)
        let elapsed = call.elapsedSeconds(at: anchor.addingTimeInterval(1.5))
        XCTAssertEqual(elapsed, 1.5, accuracy: 0.001)
    }

    func testElapsedSeconds_CompletedFreezesAtDuration() {
        var call = InlineToolCall(toolName: "x", startedAt: anchor)
        call.complete(at: anchor.addingTimeInterval(0.4), durationSeconds: 0.4, hadError: false)
        let elapsed = call.elapsedSeconds(at: anchor.addingTimeInterval(100))
        XCTAssertEqual(elapsed, 0.4, accuracy: 0.001,
                       "completed elapsed must NOT tick after completion")
    }

    func testElapsedSeconds_InterruptedFreezesAtInterruptInstant() {
        var call = InlineToolCall(toolName: "x", startedAt: anchor)
        call.interrupt(at: anchor.addingTimeInterval(0.8))
        let elapsed = call.elapsedSeconds(at: anchor.addingTimeInterval(50))
        XCTAssertEqual(elapsed, 0.8, accuracy: 0.001)
    }

    // MARK: - Codable persistence

    func testCodable_RoundTrip_PreservesAllFields() throws {
        // Use a Date whose timeIntervalSince1970 is exactly representable
        // in binary IEEE-754 so JSON Double round-trip is bit-stable.
        // 100.0 + 978307200 = 978307300.0 — exact. We add 0.25 (a clean
        // dyadic fraction) for finishedAt so 978307200.25 also round-
        // trips without loss.
        let exact = Date(timeIntervalSinceReferenceDate: 100)
        var call = InlineToolCall(
            toolName: "terminal",
            preview: "ls /",
            startedAt: exact
        )
        call.complete(at: exact.addingTimeInterval(0.25),
                      durationSeconds: 0.25,
                      hadError: true)

        // Use .secondsSince1970 to preserve sub-second precision —
        // ISO8601 default strips fractional seconds, which would
        // change `durationSeconds` round-trip values. Production
        // encoder (in ChatViewModel.encodeToolCalls) matches.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(call)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let restored = try decoder.decode(InlineToolCall.self, from: data)

        XCTAssertEqual(restored, call,
                       "Round-trip equality required for DiakMessage.toolCallsJSON persistence")
    }

    /// Even for non-dyadic fractional seconds (1.2 — not exactly
    /// representable in IEEE-754 binary), the round-trip must be
    /// **bit-stable** so two encode-decode cycles produce identical
    /// objects. We don't require the value to equal the original
    /// literal 1.2; we require encoder/decoder to be self-inverse.
    func testCodable_NonDyadicFraction_StableAcrossSecondRoundTrip() throws {
        var call = InlineToolCall(
            toolName: "terminal",
            preview: nil,
            startedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        call.complete(at: Date(timeIntervalSinceReferenceDate: 101.2),
                      durationSeconds: 1.2,
                      hadError: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let firstPass = try decoder.decode(InlineToolCall.self,
                                           from: try encoder.encode(call))
        let secondPass = try decoder.decode(InlineToolCall.self,
                                            from: try encoder.encode(firstPass))
        XCTAssertEqual(firstPass, secondPass,
                       "encoder/decoder must be self-inverse on the first pass output")
    }

    // MARK: - Status displayName (UI surface)

    func testStatusDisplayName_FourStates() {
        XCTAssertEqual(InlineToolCall.Status.running.displayName, "Running")
        XCTAssertEqual(InlineToolCall.Status.completed.displayName, "Completed")
        XCTAssertEqual(InlineToolCall.Status.interrupted.displayName, "Interrupted")
        XCTAssertEqual(InlineToolCall.Status.alreadyExecuted.displayName, "Already executed")
    }
}
