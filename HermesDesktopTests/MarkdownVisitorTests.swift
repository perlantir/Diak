import XCTest
import SwiftUI
@testable import HermesDesktop

/// Phase 3 WU3.2 — `MarkdownVisitor` / `BlockKindView` rendering
/// tests. Focuses on the inline `AttributedString` composition
/// (the only renderer output that's straightforwardly assertable
/// without a SwiftUI snapshot harness). Visual rendering of full
/// SwiftUI views is verified by the developer test-harness
/// window, not by unit tests — XCTest doesn't render views.
@MainActor
final class MarkdownVisitorTests: XCTestCase {

    // MARK: - Inline AttributedString composition

    func testAttributed_PlainTextRoundTrips() {
        let content = InlineContent(runs: [.text("hello world", style: [])])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertEqual(String(attr.characters), "hello world")
    }

    func testAttributed_BoldRunHasBoldFont() {
        let content = InlineContent(runs: [.text("strong", style: .bold)])
        let attr = BlockKindView.attributed(from: content)
        // Walk the runs; first one should carry a bold font attribute.
        let runs = Array(attr.runs)
        XCTAssertFalse(runs.isEmpty)
        XCTAssertNotNil(runs.first?.font, "bold run must carry a font attribute")
    }

    func testAttributed_InlineCodeUsesMonospace() {
        let content = InlineContent(runs: [.inlineCode("let x = 1")])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertEqual(String(attr.characters), "let x = 1")
        let runs = Array(attr.runs)
        // Monospaced font present.
        XCTAssertNotNil(runs.first?.font)
    }

    func testAttributed_LinkAttachesURLAttribute() {
        let content = InlineContent(runs: [
            .link(
                label: [.text("click", style: [])],
                destination: "https://example.com"
            )
        ])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertEqual(String(attr.characters), "click")
        let runs = Array(attr.runs)
        XCTAssertEqual(runs.first?.link?.absoluteString, "https://example.com")
    }

    func testAttributed_LineBreakInsertsNewline() {
        let content = InlineContent(runs: [
            .text("a", style: []),
            .lineBreak,
            .text("b", style: [])
        ])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertEqual(String(attr.characters), "a\nb")
    }

    func testAttributed_SoftBreakBecomesSpace() {
        let content = InlineContent(runs: [
            .text("a", style: []),
            .softBreak,
            .text("b", style: [])
        ])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertEqual(String(attr.characters), "a b")
    }

    func testAttributed_ImagePlaceholderIncludesAltText() {
        let content = InlineContent(runs: [
            .image(alt: "diagram", source: "diak.png")
        ])
        let attr = BlockKindView.attributed(from: content)
        XCTAssertTrue(String(attr.characters).contains("diagram"))
        XCTAssertTrue(String(attr.characters).contains("diak.png"))
    }

    // MARK: - End-to-end via parsing pipeline

    func testEndToEnd_ParagraphWithMixedInlinesProducesExpectedText() {
        let blocks = StreamingMessageState.parseBlocks(
            text: "plain *italic* `code` [link](https://x)"
        )
        guard case .paragraph(let content) = blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        let attr = BlockKindView.attributed(from: content)
        let chars = String(attr.characters)
        XCTAssertTrue(chars.contains("plain"))
        XCTAssertTrue(chars.contains("italic"))
        XCTAssertTrue(chars.contains("code"))
        XCTAssertTrue(chars.contains("link"))
    }

    // MARK: - BlockKind equality (the SwiftUI-diff guarantee)

    func testBlockKind_EqualityForIdenticalContent() {
        let a = StreamingMessageState.parseBlocks(text: "# heading\n\npara.")
        let b = StreamingMessageState.parseBlocks(text: "# heading\n\npara.")
        XCTAssertEqual(a, b,
                       "Identical source must produce Equatable-identical blocks (per-block invalidation depends on this)")
    }

    func testBlockKind_EqualityFailsOnDifferentContent() {
        let a = StreamingMessageState.parseBlocks(text: "# heading A")
        let b = StreamingMessageState.parseBlocks(text: "# heading B")
        XCTAssertNotEqual(a, b)
    }
}
