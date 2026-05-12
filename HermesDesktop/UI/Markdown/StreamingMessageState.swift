import Foundation
import Combine
import Markdown

/// Per-message accumulating text + parsed Markdown AST, decomposed
/// into identified block units for stable SwiftUI rendering identity.
///
/// **Why this lives outside `HermesState`** (per Decision #8's
/// streaming exception clause and PROJECT_STATE.md Known Behaviors):
/// streaming chat dispatches one append per token at 20–50 Hz (WU3.1
/// finding 6). Routing each append through the global reducer would
/// force O(n²) snapshot equality work plus full-tree SwiftUI diffs.
/// Instead, the streaming "fast lane" runs entirely on this
/// `ObservableObject`; only at stream completion does the finalized
/// message dispatch into `HermesState` via the normal Diak-owned
/// action path.
///
/// **Block identity strategy.** Top-level blocks use index-based
/// identity (`IdentifiedBlock.id == position in document.blockChildren`).
/// Under pure streaming-append, earlier blocks never change — only
/// the last block receives new content. `IdentifiedBlock` is
/// `Equatable`, so SwiftUI's `ForEach` diff reuses View identity for
/// unchanged blocks and only re-renders the changing one. This is
/// the key to keeping per-chunk render cost bounded.
///
/// **Open-fence detection.** When the source text ends with an odd
/// number of code-fence delimiters (``` or `~~~`), the trailing
/// CodeBlock is "open" — its content is still streaming and we
/// must NOT pass it to Highlightr (per SCOPE.md acceptance #3:
/// "syntax highlighting fires on close-fence detection. No per-token
/// highlight cost.") The closed/open status is published on each
/// block.
@MainActor
public final class StreamingMessageState: ObservableObject, Identifiable {

    public let id: UUID

    /// Accumulating message text. Append-only during a stream.
    @Published public private(set) var text: String

    /// Top-level blocks, derived from `text` on every change. SwiftUI
    /// views observe this for rendering.
    @Published public private(set) var blocks: [IdentifiedBlock]

    /// Stream phase. View can dim / overlay based on this.
    public enum Phase: Equatable, Sendable {
        case running
        case completed
        case interrupted(reason: String)
        case errored(reason: String)
    }
    @Published public private(set) var phase: Phase

    public init(id: UUID = UUID(), text: String = "", phase: Phase = .running) {
        self.id = id
        self.text = text
        self.phase = phase
        self.blocks = StreamingMessageState.parseBlocks(text: text)
    }

    /// Append a token to the message. Triggers a re-parse and
    /// `blocks` update. Phase 3 streaming hot path; called at
    /// 20–50 Hz during a fast generation.
    public func append(_ token: String) {
        guard !token.isEmpty else { return }
        text.append(token)
        blocks = StreamingMessageState.parseBlocks(text: text)
    }

    /// Mark the stream finished. UI can finalize highlighting, drop
    /// the streaming-cursor caret, etc.
    public func finish(_ outcome: Phase = .completed) {
        phase = outcome
        // Final re-parse so any half-fence got closed (or stays open
        // and renders as such).
        blocks = StreamingMessageState.parseBlocks(text: text)
    }

    /// Reset to empty + running. Used by the test harness's
    /// "Reset" button so that a single `@StateObject` instance can
    /// be reused across multiple replay runs.
    public func reset() {
        text = ""
        phase = .running
        blocks = []
    }

    // MARK: - Parsing pipeline

    /// Pure: parse `text` into identified blocks. Exposed
    /// `static` so tests can call it directly without constructing
    /// a state object.
    public static func parseBlocks(text: String) -> [IdentifiedBlock] {
        guard !text.isEmpty else { return [] }
        let trailingFenceOpen = hasOpenCodeFence(text)
        let document = Document(parsing: text)
        var out: [IdentifiedBlock] = []
        out.reserveCapacity(document.childCount)
        let lastIndex = document.childCount - 1
        for (i, child) in document.children.enumerated() {
            guard let block = child as? BlockMarkup else { continue }
            let isLast = i == lastIndex
            // Only the trailing block can be "open" — fences earlier
            // in the document are closed by definition.
            let codeBlockOpen = isLast && trailingFenceOpen
            out.append(IdentifiedBlock(
                id: i,
                kind: BlockKind(from: block, codeBlockOpen: codeBlockOpen)
            ))
        }
        return out
    }

    /// Scan `source` to detect whether the document ends inside an
    /// unclosed fenced code block. CommonMark §4.5: a fenced code
    /// block is opened by a line whose first non-space chars are
    /// at least three of ``` or `~~~`; it's closed by a matching
    /// fence line of the same character. The closing fence must
    /// use the SAME character as the opening one and may not have
    /// non-space content after it.
    ///
    /// Algorithm: line-based scan. Track whether we're currently
    /// inside an open fence and which character opened it. A line
    /// that starts (after up to 3 spaces) with ≥3 of the SAME fence
    /// character closes the current fence; outside a fence, such a
    /// line opens a new one.
    ///
    /// Phase 3 SCOPE.md WU3.2 acceptance: "a half-finished code
    /// block (open fence, no close fence yet) must NOT render as
    /// Markdown of the following text." This function is the
    /// detector — when it returns true, `parseBlocks` marks the
    /// trailing CodeBlock as `isClosed: false` and the renderer
    /// skips Highlightr.
    public static func hasOpenCodeFence(_ source: String) -> Bool {
        var inFence = false
        var openingChar: Character = "`"
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if let fenceChar = leadingFenceCharacter(rawLine) {
                if inFence {
                    if fenceChar == openingChar {
                        inFence = false
                    }
                    // A different fence character inside an open
                    // fence is just code body — ignore.
                } else {
                    inFence = true
                    openingChar = fenceChar
                }
            }
        }
        return inFence
    }

    /// Returns the fence character (``` ` ``` or `~`) if the line is
    /// a fence line (≥3 consecutive same-char markers after up to
    /// 3 leading spaces and only whitespace/info-string after the
    /// run). `nil` otherwise.
    private static func leadingFenceCharacter(_ line: Substring) -> Character? {
        var idx = line.startIndex
        var spaceCount = 0
        while idx < line.endIndex && line[idx] == " " && spaceCount < 4 {
            spaceCount += 1
            idx = line.index(after: idx)
        }
        if spaceCount >= 4 { return nil }
        guard idx < line.endIndex else { return nil }
        let first = line[idx]
        guard first == "`" || first == "~" else { return nil }
        var runLength = 0
        while idx < line.endIndex && line[idx] == first {
            runLength += 1
            idx = line.index(after: idx)
        }
        guard runLength >= 3 else { return nil }
        // Per CommonMark: the opening fence line may have an "info
        // string" after the run (e.g. "```swift"). The closing
        // fence line must contain only the fence run plus optional
        // trailing spaces — we accept both for the purposes of
        // open/close counting. Conservatively: anything goes after
        // the run for opens; for closes, only spaces. The streaming-
        // detector treats any fence line as a toggle.
        return first
    }
}

// MARK: - Identified block

public struct IdentifiedBlock: Identifiable, Equatable, Sendable {
    public let id: Int
    public var kind: BlockKind
}

/// Phase 3 SCOPE.md acceptance #2 + SwiftUI diff-stability goal:
/// the renderer's per-block invalidation scope is governed by
/// this enum's `Equatable` semantics. If a block's `kind` is
/// unchanged across a re-parse, the SwiftUI `ForEach` short-
/// circuits the body call — only blocks that *actually changed*
/// re-render.
public enum BlockKind: Equatable, Sendable {
    case paragraph(InlineContent)
    case heading(level: Int, content: InlineContent)
    case codeBlock(language: String?, body: String, isClosed: Bool)
    case unorderedList(items: [ListItemContent])
    case orderedList(items: [ListItemContent], startIndex: Int)
    case blockQuote(children: [BlockKind])
    case thematicBreak
    case table(headers: [InlineContent], rows: [[InlineContent]])
    case htmlBlock(rawHTML: String)
    case unsupported(typeName: String, fallbackText: String)

    init(from markup: BlockMarkup, codeBlockOpen: Bool = false) {
        switch markup {
        case let paragraph as Paragraph:
            self = .paragraph(InlineContent(children: Array(paragraph.inlineChildren)))
        case let heading as Heading:
            self = .heading(
                level: max(1, min(6, heading.level)),
                content: InlineContent(children: Array(heading.inlineChildren))
            )
        case let codeBlock as CodeBlock:
            self = .codeBlock(
                language: codeBlock.language,
                body: codeBlock.code,
                isClosed: !codeBlockOpen
            )
        case let unordered as UnorderedList:
            self = .unorderedList(
                items: Array(unordered.listItems).map { ListItemContent(item: $0) }
            )
        case let ordered as OrderedList:
            self = .orderedList(
                items: Array(ordered.listItems).map { ListItemContent(item: $0) },
                startIndex: Int(ordered.startIndex)
            )
        case let blockQuote as BlockQuote:
            self = .blockQuote(children: Array(blockQuote.blockChildren).map {
                BlockKind(from: $0)
            })
        case _ as ThematicBreak:
            self = .thematicBreak
        case let table as Table:
            let headerCells: [InlineContent] = Array(table.head.cells).map { cell in
                InlineContent(children: Array(cell.inlineChildren))
            }
            let bodyRows: [[InlineContent]] = Array(table.body.rows).map { row in
                Array(row.cells).map { cell in
                    InlineContent(children: Array(cell.inlineChildren))
                }
            }
            self = .table(headers: headerCells, rows: bodyRows)
        case let html as HTMLBlock:
            self = .htmlBlock(rawHTML: html.rawHTML)
        default:
            self = .unsupported(
                typeName: String(describing: type(of: markup)),
                fallbackText: markup.format()
            )
        }
    }
}

/// One list item, including any nested block content. Lists may
/// contain paragraphs, sub-lists, code blocks, etc. — we recurse
/// into `BlockKind` for each child block.
public struct ListItemContent: Equatable, Sendable {
    public let blocks: [BlockKind]

    init(item: ListItem) {
        self.blocks = Array(item.blockChildren).map { BlockKind(from: $0) }
    }
}

/// Sequence of inline tokens within a single block (paragraph,
/// heading, list item, table cell). `Equatable` so the
/// containing `BlockKind`'s equality is also block-level
/// structural.
public struct InlineContent: Equatable, Sendable {
    public let runs: [InlineRun]

    init(children: [InlineMarkup]) {
        var out: [InlineRun] = []
        for child in children {
            out.append(contentsOf: InlineRun.runs(from: child))
        }
        self.runs = out
    }

    public init(runs: [InlineRun]) {
        self.runs = runs
    }
}

/// One styled run within an inline content sequence. Represented
/// as an explicit value (not an `AttributedString`) so equality
/// is cheap and SwiftUI's diff has a stable hash to compare on.
public enum InlineRun: Equatable, Sendable {
    case text(String, style: TextStyle)
    case lineBreak
    case softBreak
    case inlineCode(String)
    case link(label: [InlineRun], destination: String?)
    case image(alt: String, source: String?)

    public struct TextStyle: OptionSet, Equatable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let bold        = TextStyle(rawValue: 1 << 0)
        public static let italic      = TextStyle(rawValue: 1 << 1)
        public static let strikethrough = TextStyle(rawValue: 1 << 2)
    }

    static func runs(from inline: InlineMarkup, inheriting style: TextStyle = []) -> [InlineRun] {
        switch inline {
        case let text as Markdown.Text:
            return [.text(text.string, style: style)]
        case let emphasis as Emphasis:
            return Array(emphasis.inlineChildren).flatMap {
                InlineRun.runs(from: $0, inheriting: style.union(.italic))
            }
        case let strong as Strong:
            return Array(strong.inlineChildren).flatMap {
                InlineRun.runs(from: $0, inheriting: style.union(.bold))
            }
        case let strike as Strikethrough:
            return Array(strike.inlineChildren).flatMap {
                InlineRun.runs(from: $0, inheriting: style.union(.strikethrough))
            }
        case _ as LineBreak:
            return [.lineBreak]
        case _ as SoftBreak:
            return [.softBreak]
        case let code as InlineCode:
            return [.inlineCode(code.code)]
        case let link as Link:
            let labelRuns: [InlineRun] = Array(link.inlineChildren).flatMap {
                InlineRun.runs(from: $0, inheriting: style)
            }
            return [.link(label: labelRuns, destination: link.destination)]
        case let image as Image:
            return [.image(alt: image.plainText, source: image.source)]
        case let inlineHTML as InlineHTML:
            // Render raw HTML as literal text. Phase 3 does not
            // attempt to render embedded HTML; users see the source.
            return [.text(inlineHTML.rawHTML, style: style)]
        default:
            // Fallback: render the inline's plain text. Covers
            // Symbol/CustomInline and any future additions.
            return [.text(inline.plainText, style: style)]
        }
    }
}
