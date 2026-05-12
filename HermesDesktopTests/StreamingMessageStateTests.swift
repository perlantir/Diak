import XCTest
@testable import HermesDesktop

/// Phase 3 WU3.2 — `StreamingMessageState` correctness tests.
///
/// SCOPE.md acceptance criteria for the renderer surface:
/// 1. Per-block-element rendering for every block type.
/// 2. Streaming-correctness: byte-by-byte and whole-document feeds
///    produce identical final state.
/// 3. Code-fence handling: an unclosed fence does NOT cause the
///    trailing text to render as Markdown.
///
/// These tests exercise the value-layer (`text → [BlockKind]`)
/// directly. SwiftUI rendering tests live in
/// `MarkdownVisitorTests.swift` (this file's sibling) and only
/// check that block-kind variations resolve to distinct view
/// trees. Visual correctness is verified manually via the test
/// harness window.
@MainActor
final class StreamingMessageStateTests: XCTestCase {

    // MARK: - Block-type coverage

    func testParseBlocks_ParagraphProducesParagraphBlock() {
        let blocks = StreamingMessageState.parseBlocks(text: "Hello, world.")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let content) = blocks[0].kind else {
            XCTFail("Expected .paragraph, got \(blocks[0].kind)")
            return
        }
        guard case .text(let s, _) = content.runs.first else {
            XCTFail("Expected leading text run, got \(content.runs)")
            return
        }
        XCTAssertEqual(s, "Hello, world.")
    }

    func testParseBlocks_HeadingsProduceLevels1Through6() {
        let source = """
        # h1
        ## h2
        ### h3
        #### h4
        ##### h5
        ###### h6
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 6)
        for (idx, expectedLevel) in (1...6).enumerated() {
            guard case .heading(let level, _) = blocks[idx].kind else {
                XCTFail("Block \(idx) expected .heading, got \(blocks[idx].kind)")
                return
            }
            XCTAssertEqual(level, expectedLevel)
        }
    }

    func testParseBlocks_FencedCodeBlockClosedHasIsClosedTrue() {
        let source = """
        ```swift
        let x = 1
        ```
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let lang, let body, let isClosed) = blocks[0].kind else {
            XCTFail("Expected .codeBlock, got \(blocks[0].kind)")
            return
        }
        XCTAssertEqual(lang, "swift")
        XCTAssertEqual(body.trimmingCharacters(in: .whitespacesAndNewlines), "let x = 1")
        XCTAssertTrue(isClosed)
    }

    func testParseBlocks_UnorderedListProducesItems() {
        let source = """
        - a
        - b
        - c
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .unorderedList(let items) = blocks[0].kind else {
            XCTFail("Expected .unorderedList, got \(blocks[0].kind)")
            return
        }
        XCTAssertEqual(items.count, 3)
    }

    func testParseBlocks_OrderedListExposesStartIndex() {
        let source = """
        5. five
        6. six
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .orderedList(let items, let startIndex) = blocks[0].kind else {
            XCTFail("Expected .orderedList, got \(blocks[0].kind)")
            return
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(startIndex, 5,
                       "OrderedList.startIndex must reflect the source's first index")
    }

    func testParseBlocks_BlockQuoteWrapsChildren() {
        let source = "> quoted paragraph"
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let children) = blocks[0].kind else {
            XCTFail("Expected .blockQuote, got \(blocks[0].kind)")
            return
        }
        XCTAssertEqual(children.count, 1)
        guard case .paragraph = children[0] else {
            XCTFail("Expected paragraph child, got \(children[0])")
            return
        }
    }

    func testParseBlocks_ThematicBreakRecognized() {
        let blocks = StreamingMessageState.parseBlocks(text: "---")
        XCTAssertEqual(blocks.count, 1)
        guard case .thematicBreak = blocks[0].kind else {
            XCTFail("Expected .thematicBreak, got \(blocks[0].kind)")
            return
        }
    }

    func testParseBlocks_TableHeadersAndRows() {
        let source = """
        | a | b |
        |---|---|
        | 1 | 2 |
        | 3 | 4 |
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let headers, let rows) = blocks[0].kind else {
            XCTFail("Expected .table, got \(blocks[0].kind)")
            return
        }
        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2)
    }

    // MARK: - Inline runs

    func testParseBlocks_EmphasisAndStrongTagInlineRuns() {
        let source = "plain *italic* **bold** ***boldItalic*** `code`"
        let blocks = StreamingMessageState.parseBlocks(text: source)
        guard case .paragraph(let content) = blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        // Find the runs with non-empty styles.
        let italicRun = content.runs.first {
            if case .text(_, let style) = $0, style == .italic { return true }
            return false
        }
        XCTAssertNotNil(italicRun, "italic run missing in \(content.runs)")
        let boldRun = content.runs.first {
            if case .text(_, let style) = $0, style == .bold { return true }
            return false
        }
        XCTAssertNotNil(boldRun, "bold run missing")
        let inlineCodeRun = content.runs.first {
            if case .inlineCode = $0 { return true }
            return false
        }
        XCTAssertNotNil(inlineCodeRun, "inline-code run missing")
    }

    func testParseBlocks_StrikethroughSurfacesGFMExtension() {
        let blocks = StreamingMessageState.parseBlocks(text: "~~struck~~")
        guard case .paragraph(let content) = blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        let strikeRun = content.runs.first {
            if case .text(_, let style) = $0, style.contains(.strikethrough) { return true }
            return false
        }
        XCTAssertNotNil(strikeRun, "strikethrough run missing in \(content.runs)")
    }

    func testParseBlocks_LinkPreservesDestination() {
        let blocks = StreamingMessageState.parseBlocks(text: "click [here](https://example.com).")
        guard case .paragraph(let content) = blocks[0].kind else {
            XCTFail("Expected paragraph")
            return
        }
        let linkRun = content.runs.first {
            if case .link(_, let dest) = $0, dest == "https://example.com" { return true }
            return false
        }
        XCTAssertNotNil(linkRun, "link run with correct destination missing in \(content.runs)")
    }

    // MARK: - Open code fence detection

    func testHasOpenCodeFence_DetectsOpenFence() {
        // Open with no close.
        XCTAssertTrue(StreamingMessageState.hasOpenCodeFence("```swift\nlet x = 1"))
    }

    func testHasOpenCodeFence_ClosedFenceReturnsFalse() {
        XCTAssertFalse(StreamingMessageState.hasOpenCodeFence("```\nfoo\n```"))
    }

    func testHasOpenCodeFence_NoFenceReturnsFalse() {
        XCTAssertFalse(StreamingMessageState.hasOpenCodeFence("just paragraph text"))
    }

    func testHasOpenCodeFence_TildeFenceAlsoDetected() {
        XCTAssertTrue(StreamingMessageState.hasOpenCodeFence("~~~python\nprint('hi')"))
        XCTAssertFalse(StreamingMessageState.hasOpenCodeFence("~~~python\nprint('hi')\n~~~"))
    }

    func testParseBlocks_OpenFenceMarksCodeBlockUnclosed() {
        let source = """
        ```swift
        let x = 1
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(_, _, let isClosed) = blocks[0].kind else {
            XCTFail("Expected .codeBlock, got \(blocks[0].kind)")
            return
        }
        XCTAssertFalse(isClosed,
                       "Open code fence MUST mark the trailing code block as not closed")
    }

    // MARK: - Streaming correctness (load-bearing for SCOPE.md acceptance)

    func testStreamingCorrectness_ByteByByteMatchesWholeDocument() {
        let documents = [
            "# Hello\n\nA paragraph with *italic* and **bold**.",
            """
            # Title

            - item one
            - item two with *emphasis*
            - item three

            > quote block

            ```swift
            let x = 1
            ```

            Plain paragraph.
            """,
            """
            Paragraph one.

            | a | b |
            |---|---|
            | 1 | 2 |

            ---

            Paragraph two.
            """,
        ]
        for source in documents {
            let stateA = StreamingMessageState(text: "")
            for scalar in source.unicodeScalars {
                stateA.append(String(scalar))
            }
            let stateB = StreamingMessageState(text: source)
            XCTAssertEqual(
                stateA.blocks, stateB.blocks,
                "Byte-by-byte feed must produce identical final blocks for source:\n\(source)"
            )
        }
    }

    func testStreamingCorrectness_HalfFenceDoesNotRenderTrailingAsMarkdown() {
        // Halfway through a code block, the trailing prose ('## not a heading')
        // must be captured as code body, NOT promoted to a heading block.
        let source = """
        ```swift
        let x = 1
        ## not a heading inside fence
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertEqual(
            blocks.count, 1,
            "Open fence must hold the trailing text inside the code block — no separate heading should appear"
        )
        guard case .codeBlock(_, let body, let isClosed) = blocks[0].kind else {
            XCTFail("Expected .codeBlock, got \(blocks[0].kind)")
            return
        }
        XCTAssertFalse(isClosed)
        XCTAssertTrue(body.contains("## not a heading inside fence"),
                      "Open code block body must include the trailing text verbatim")
    }

    func testStreamingCorrectness_TwoCodeBlocksClosedThenOpen() {
        // First fence closed, second open. Only the second should be
        // marked as open.
        let source = """
        ```js
        a
        ```

        Text.

        ```py
        b
        """
        let blocks = StreamingMessageState.parseBlocks(text: source)
        XCTAssertGreaterThanOrEqual(blocks.count, 3)
        // First code block is closed.
        guard case .codeBlock(_, _, let firstClosed) = blocks[0].kind else {
            XCTFail("Expected first block .codeBlock")
            return
        }
        XCTAssertTrue(firstClosed)
        // Last block is the second code block — should be open.
        guard case .codeBlock(_, _, let lastClosed) = blocks.last!.kind else {
            XCTFail("Expected last block .codeBlock")
            return
        }
        XCTAssertFalse(lastClosed)
    }

    func testStreamingCorrectness_EarlierBlocksUnchangedAsTextAppends() {
        // Per SCOPE.md WU3.2 invariant: only the trailing block changes
        // under streaming append. Verify Equatable shows earlier blocks
        // are identical across appends.
        let state = StreamingMessageState(text: "# heading\n\nparagraph one.")
        let blocksBefore = state.blocks
        state.append("\n\nparagraph two.")
        let blocksAfter = state.blocks
        XCTAssertGreaterThan(blocksAfter.count, blocksBefore.count,
                             "Appending a new block should grow the block list")
        // First two blocks (heading + paragraph one) should be
        // unchanged.
        for i in 0..<blocksBefore.count {
            XCTAssertEqual(blocksBefore[i], blocksAfter[i],
                           "Block \(i) must be Equatable-equal across the append (Phase 3 SwiftUI-diff guarantee)")
        }
    }

    func testStreamingCorrectness_FinishTransitionsPhase() {
        let state = StreamingMessageState(text: "hi")
        XCTAssertEqual(state.phase, .running)
        state.finish(.completed)
        XCTAssertEqual(state.phase, .completed)
    }

    func testStreamingCorrectness_ResetClearsTextAndBlocks() {
        let state = StreamingMessageState(text: "")
        state.append("# Heading\n\nparagraph.")
        XCTAssertFalse(state.blocks.isEmpty)
        state.reset()
        XCTAssertTrue(state.blocks.isEmpty)
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.phase, .running)
    }
}
