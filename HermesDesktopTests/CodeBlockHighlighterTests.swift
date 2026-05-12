import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.2 — `CodeBlockHighlighter` integration tests.
///
/// Highlightr is third-party so we don't unit-test its
/// correctness — we test the cache contract (same input returns
/// same output, no re-highlight cost) and the resilience
/// contract (unknown language and nil-language paths produce
/// valid output or nil, never crash).
@MainActor
final class CodeBlockHighlighterTests: XCTestCase {

    func testHighlight_KnownLanguageReturnsAttributedString() {
        let highlighter = CodeBlockHighlighter()
        let result = highlighter.highlight(language: "swift", body: "let x = 1")
        XCTAssertNotNil(result, "swift is a well-known Highlightr language; should return attributed output")
    }

    func testHighlight_UnknownLanguageDoesNotCrash() {
        let highlighter = CodeBlockHighlighter()
        // Doesn't crash, may or may not return nil — Highlightr's
        // policy is to auto-detect if language is unknown.
        _ = highlighter.highlight(language: "totally-not-a-real-language", body: "foo")
    }

    func testHighlight_NilLanguageIsHandled() {
        let highlighter = CodeBlockHighlighter()
        // nil language asks Highlightr to auto-detect. Should not
        // crash regardless of whether detection succeeds.
        _ = highlighter.highlight(language: nil, body: "plain text body")
    }

    func testHighlight_EmptyLanguageStringTreatedAsNil() {
        // Common Markdown shape: ` ``` ` (no language hint) parses to
        // CodeBlock with language="" or language=nil depending on the
        // parser. CodeBlockHighlighter should treat both equivalently.
        let highlighter = CodeBlockHighlighter()
        let withEmpty = highlighter.highlight(language: "", body: "code")
        let withNil = highlighter.highlight(language: nil, body: "code")
        XCTAssertEqual(
            String((withEmpty ?? AttributedString("")).characters),
            String((withNil ?? AttributedString("")).characters),
            "Empty language string and nil language must produce equivalent output"
        )
    }

    func testHighlight_CacheReturnsSameResultForRepeatedKey() {
        let highlighter = CodeBlockHighlighter()
        let body = "let answer = 42"
        let first = highlighter.highlight(language: "swift", body: body)
        let second = highlighter.highlight(language: "swift", body: body)
        XCTAssertEqual(
            String((first ?? AttributedString("")).characters),
            String((second ?? AttributedString("")).characters),
            "Cache hit must return identical output (per-block-body memoization is what makes streaming fast)"
        )
    }

    func testClearCache_DropsEntries() {
        // No observable side-effect from clearing the cache; just
        // verify it doesn't crash.
        let highlighter = CodeBlockHighlighter()
        _ = highlighter.highlight(language: "swift", body: "let x = 1")
        highlighter.clearCache()
        // Re-highlight after clear works.
        let result = highlighter.highlight(language: "swift", body: "let x = 1")
        XCTAssertNotNil(result)
    }
}
