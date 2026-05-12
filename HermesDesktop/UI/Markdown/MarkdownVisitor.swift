import SwiftUI
import AppKit

/// SwiftUI renderer for the AST visitor's `BlockKind` intermediate.
///
/// The visitor pattern is split into two halves in this module:
///
///   1. `StreamingMessageState.parseBlocks(text:)` walks the
///      apple/swift-markdown `Document` AST and produces an array
///      of `IdentifiedBlock` value types (`BlockKind` + index id).
///      This is the "AST visitor" half — visits every block and
///      inline node, projects to a value type whose `Equatable`
///      conformance is structural.
///
///   2. This file's `BlockKindView` is the "produces SwiftUI views,
///      one per block element" half — a `View` that switches on
///      `BlockKind` and returns the appropriate Markdown element.
///
/// Splitting visitation from rendering is what gives us the
/// streaming-stability guarantee: blocks that haven't changed
/// produce identical `BlockKind` values, SwiftUI's `ForEach`
/// short-circuits via `Equatable`, and only the trailing block
/// (where streaming append is happening) re-renders per chunk.
public struct BlockKindView: View {

    public let block: BlockKind
    public let highlighter: CodeBlockHighlighter

    public init(block: BlockKind,
                highlighter: CodeBlockHighlighter = .shared) {
        self.block = block
        self.highlighter = highlighter
    }

    public var body: some View {
        switch block {

        case .paragraph(let content):
            inlineText(content)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("md.paragraph")

        case .heading(let level, let content):
            inlineText(content)
                .font(headingFont(level: level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 8 : 4)
                .padding(.bottom, 2)
                .accessibilityIdentifier("md.heading.\(level)")

        case .codeBlock(let language, let body, let isClosed):
            codeBlockView(language: language, body: body, isClosed: isClosed)

        case .unorderedList(let items):
            listView(items: items, ordered: false, startIndex: 1)
                .accessibilityIdentifier("md.list.unordered")

        case .orderedList(let items, let startIndex):
            listView(items: items, ordered: true, startIndex: startIndex)
                .accessibilityIdentifier("md.list.ordered")

        case .blockQuote(let children):
            blockQuoteView(children: children)
                .accessibilityIdentifier("md.blockquote")

        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)
                .accessibilityIdentifier("md.hrule")

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
                .accessibilityIdentifier("md.table")

        case .htmlBlock(let html):
            // No HTML rendering. Show as plain monospace per WU3.1
            // finding — anything outside the rendered Markdown
            // surface is shown literally.
            Text(html)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("md.html")

        case .unsupported(_, let fallbackText):
            Text(fallbackText)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("md.unsupported")
        }
    }

    // MARK: - Helpers

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:  return .system(.largeTitle, design: .default)
        case 2:  return .system(.title, design: .default)
        case 3:  return .system(.title2, design: .default)
        case 4:  return .system(.title3, design: .default)
        case 5:  return .system(.headline, design: .default)
        default: return .system(.subheadline, design: .default)
        }
    }

    @ViewBuilder
    private func codeBlockView(language: String?, body: String, isClosed: Bool) -> some View {
        // Build attributed content. When closed, run Highlightr; when
        // open, fall back to plain monospaced text so we don't pay
        // highlight cost per streaming chunk.
        let attributed: AttributedString = {
            if isClosed, let highlighted = highlighter.highlight(language: language, body: body) {
                return highlighted
            }
            // Plain monospace fallback for either open code blocks
            // or Highlightr failures.
            var fallback = AttributedString(body)
            fallback.font = .system(.callout, design: .monospaced)
            return fallback
        }()

        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
            }
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .accessibilityIdentifier(isClosed ? "md.code.closed" : "md.code.open")
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("md.codeblock")
    }

    @ViewBuilder
    private func listView(items: [ListItemContent],
                          ordered: Bool,
                          startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ordered ? "\(startIndex + pair.offset)." : "•")
                        .font(.system(.body, design: .default))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pair.element.blocks.enumerated()), id: \.offset) { childPair in
                            BlockKindView(block: childPair.element, highlighter: highlighter)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockQuoteView(children: [BlockKind]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(children.enumerated()), id: \.offset) { pair in
                    BlockKindView(block: pair.element, highlighter: highlighter)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func tableView(headers: [InlineContent], rows: [[InlineContent]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !headers.isEmpty {
                tableRow(cells: headers, isHeader: true)
                Divider()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                tableRow(cells: pair.element, isHeader: false)
                if pair.offset < rows.count - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tableRow(cells: [InlineContent], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { pair in
                inlineText(pair.element)
                    .fontWeight(isHeader ? .semibold : .regular)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pair.offset < cells.count - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
    }

    /// Build one SwiftUI `Text` for an inline run sequence. Uses
    /// `AttributedString` composition so all styling lives in a
    /// single Text view — this minimizes the number of SwiftUI
    /// view nodes per paragraph/heading.
    private func inlineText(_ content: InlineContent) -> Text {
        Text(Self.attributed(from: content))
    }

    /// Public for tests + future view-types that need to bake
    /// inline content into an AttributedString without going
    /// through the SwiftUI View layer.
    public static func attributed(from content: InlineContent) -> AttributedString {
        var output = AttributedString()
        for run in content.runs {
            appendRun(run, to: &output)
        }
        return output
    }

    private static func appendRun(_ run: InlineRun, to output: inout AttributedString) {
        switch run {
        case .text(let s, let style):
            var fragment = AttributedString(s)
            applyStyle(style, to: &fragment)
            output.append(fragment)
        case .inlineCode(let code):
            var fragment = AttributedString(code)
            fragment.font = .system(.callout, design: .monospaced)
            // Subtle background tint via .backgroundColor (renders
            // as a span on macOS Text rendering).
            fragment.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.1)
            output.append(fragment)
        case .link(let labelRuns, let destination):
            var labelString = AttributedString()
            for child in labelRuns {
                appendRun(child, to: &labelString)
            }
            if let destination, let url = URL(string: destination) {
                labelString.link = url
                labelString.foregroundColor = .accentColor
                labelString.underlineStyle = .single
            } else {
                labelString.foregroundColor = .accentColor
            }
            output.append(labelString)
        case .image(let alt, let source):
            // Phase 3 doesn't fetch images. Render alt text with
            // a leading 🖼 marker so the user knows the message
            // referenced an image without asynchronously loading
            // anything.
            let label = source.map { "🖼 \(alt) (\($0))" } ?? "🖼 \(alt)"
            var fragment = AttributedString(label)
            fragment.foregroundColor = .secondary
            output.append(fragment)
        case .lineBreak:
            output.append(AttributedString("\n"))
        case .softBreak:
            // CommonMark: soft breaks render as a single space in
            // flowing text. Phase 3 follows this.
            output.append(AttributedString(" "))
        }
    }

    private static func applyStyle(_ style: InlineRun.TextStyle,
                                   to fragment: inout AttributedString) {
        if style.contains(.bold) && style.contains(.italic) {
            fragment.font = .system(.body).bold().italic()
        } else if style.contains(.bold) {
            fragment.font = .system(.body).bold()
        } else if style.contains(.italic) {
            fragment.font = .system(.body).italic()
        }
        if style.contains(.strikethrough) {
            fragment.strikethroughStyle = .single
        }
    }
}
