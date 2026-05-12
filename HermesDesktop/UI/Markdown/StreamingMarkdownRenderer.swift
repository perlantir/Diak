import SwiftUI

/// Top-level view that renders a `StreamingMessageState` as
/// incrementally-updating Markdown.
///
/// **Per-block invalidation.** The `ForEach` is keyed by
/// `IdentifiedBlock.id` (the block's position in the document).
/// Combined with `BlockKind`'s `Equatable` conformance, SwiftUI's
/// diff reuses View identity for blocks whose `kind` hasn't
/// changed. During a streaming append at 20–50 Hz, this means
/// only the trailing block (where new content is landing)
/// re-renders per chunk; earlier blocks stay structurally
/// identical and SwiftUI skips them.
///
/// **Scroll preservation.** The renderer ALONE does not auto-
/// scroll — that's a containing-view responsibility (the chat
/// transcript view will own the `ScrollView`). However, this
/// view exposes an `onContentChange:` callback so a parent can
/// observe block-level mutations and decide whether to scroll-
/// follow. SCOPE.md acceptance: "new tokens appending below
/// should NOT jerk the scroll back to bottom" — the parent
/// decides whether to scroll based on the user's current scroll
/// position, NOT on whether the content changed.
///
/// **Streaming caret.** While `state.phase == .running`, a
/// subtle caret indicator is appended after the last block to
/// signal "more content coming." Removed when phase transitions
/// out of `.running`.
public struct StreamingMarkdownRenderer: View {

    @ObservedObject public var state: StreamingMessageState
    public let highlighter: CodeBlockHighlighter
    public let showStreamingCaret: Bool

    /// Optional notification when the rendered block list changes.
    /// Parent views (chat transcript) use this for scroll-position
    /// decisions.
    public let onContentChange: (() -> Void)?

    public init(state: StreamingMessageState,
                highlighter: CodeBlockHighlighter = .shared,
                showStreamingCaret: Bool = true,
                onContentChange: (() -> Void)? = nil) {
        self.state = state
        self.highlighter = highlighter
        self.showStreamingCaret = showStreamingCaret
        self.onContentChange = onContentChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.blocks) { block in
                BlockKindView(block: block.kind, highlighter: highlighter)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showStreamingCaret, state.phase == .running, !state.blocks.isEmpty {
                StreamingCaret()
                    .padding(.leading, 2)
            }
            if case .interrupted(let reason) = state.phase {
                interruptedBanner(reason: reason)
            }
            if case .errored(let reason) = state.phase {
                erroredBanner(reason: reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: state.blocks) { _ in
            onContentChange?()
        }
        .accessibilityIdentifier("md.renderer")
    }

    @ViewBuilder
    private func interruptedBanner(reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Stream interrupted: \(reason)")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityIdentifier("md.interrupted")
    }

    @ViewBuilder
    private func erroredBanner(reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text("Error: \(reason)")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityIdentifier("md.errored")
    }
}

/// Subtle pulsing rectangle the user reads as a streaming caret.
/// Cheaper than relying on `Text` cursor manipulation.
struct StreamingCaret: View {
    @State private var isVisible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 7, height: 14)
            .opacity(isVisible ? 0.8 : 0.0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                       value: isVisible)
            .onAppear { isVisible.toggle() }
            .accessibilityIdentifier("md.caret")
    }
}

// MARK: - Scroll-preserving wrapper

/// Embedded chat-transcript-style ScrollView that keeps the user's
/// current scroll position when new content arrives, UNLESS the
/// user is already pinned to the bottom (in which case it auto-
/// scrolls to follow).
///
/// SCOPE.md acceptance: "new tokens appending below should NOT
/// jerk the scroll back to bottom" when the user has scrolled up.
/// Detection strategy: a sentinel view at the bottom whose
/// `onAppear` / `onDisappear` toggles a "user is at bottom"
/// `@State`. Auto-scroll fires only when at-bottom.
///
/// Phase 3 WU3.3 will use a similar mechanism in the real chat
/// transcript view. This wrapper is the standalone version for
/// the test harness + any future single-message renderer (e.g.,
/// the inspector pane's live activity preview).
public struct ScrollPreservingMarkdownView: View {

    @ObservedObject public var state: StreamingMessageState
    public let highlighter: CodeBlockHighlighter
    @State private var isAtBottom: Bool = true

    public init(state: StreamingMessageState,
                highlighter: CodeBlockHighlighter = .shared) {
        self.state = state
        self.highlighter = highlighter
    }

    private static let bottomSentinelID = "diak.md.bottomSentinel"

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                StreamingMarkdownRenderer(
                    state: state,
                    highlighter: highlighter,
                    onContentChange: {
                        if isAtBottom {
                            withAnimation(.linear(duration: 0.12)) {
                                proxy.scrollTo(Self.bottomSentinelID,
                                               anchor: .bottom)
                            }
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomSentinelID)
                    .onAppear { isAtBottom = true }
                    .onDisappear { isAtBottom = false }
            }
        }
    }
}
