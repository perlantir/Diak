import SwiftUI

/// Renders an in-flight assistant message: a sequence of text
/// segments (each via `StreamingMarkdownRenderer` from WU3.2) and
/// inline `ToolCallCardView`s, interleaved in event-arrival order.
///
/// **Why the interleaved layout and not a sidebar group:** WU3.1
/// Finding 5 documented the convergent Cursor / Claude / ChatGPT
/// pattern of inline tool cards. The user reads "the model said X,
/// then ran tool Y, then continued with Z" in document order, which
/// matches how the events arrive and how the StreamingAssistantMessage
/// maintains its segments array.
///
/// **Per-token painting via the StreamingMarkdownRenderer.** Each
/// `.text` segment owns its own `StreamingMessageState`; updates from
/// the upstream `RunStreamCoordinator` mutate the state directly and
/// SwiftUI's per-segment ForEach diff isolates re-renders to the
/// trailing segment (where new content is landing).
///
/// **Caret suppression for non-trailing text segments.** When a
/// tool card opens between two text segments, the FIRST text
/// segment is "frozen" (no more deltas will land in it) so the
/// streaming caret should disappear there. We suppress the caret
/// on every text segment except the last, regardless of phase.
public struct StreamingAssistantMessageView: View {

    @ObservedObject public var message: StreamingAssistantMessage
    public let highlighter: CodeBlockHighlighter

    public init(message: StreamingAssistantMessage,
                highlighter: CodeBlockHighlighter = .shared) {
        self.message = message
        self.highlighter = highlighter
    }

    public var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            assistantAvatar
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text(HermesRole.assistant.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesColors.muted)
                segmentStack
                phaseBanner
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, HermesSpacing.sm)
        .accessibilityIdentifier("stream.assistant.\(message.id.uuidString)")
    }

    @ViewBuilder
    private var segmentStack: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            ForEach(Array(message.segments.enumerated()), id: \.element.id) { offset, segment in
                segmentView(segment, isLast: offset == message.segments.count - 1)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: StreamingAssistantMessage.Segment,
                             isLast: Bool) -> some View {
        switch segment {
        case .text(let textSegment):
            StreamingMarkdownRenderer(
                state: textSegment.state,
                highlighter: highlighter,
                showStreamingCaret: isLast && message.phase == .running
            )
        case .tool(let call):
            ToolCallCardView(call: call)
        }
    }

    @ViewBuilder
    private var phaseBanner: some View {
        switch message.phase {
        case .running, .completed:
            EmptyView()
        case .cancelled(let reason):
            phaseBannerRow(icon: "stop.circle.fill",
                           tint: HermesColors.warning,
                           message: "Stopped — \(reason)")
        case .interrupted(let reason):
            phaseBannerRow(icon: "exclamationmark.triangle.fill",
                           tint: HermesColors.warning,
                           message: "Stream interrupted — \(reason)")
        case .failed(let reason):
            phaseBannerRow(icon: "xmark.octagon.fill",
                           tint: HermesColors.danger,
                           message: reason)
        }
    }

    private func phaseBannerRow(icon: String, tint: Color, message: String) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HermesColors.muted)
            Spacer()
        }
        .padding(.top, HermesSpacing.xs)
    }

    private var assistantAvatar: some View {
        Text("H")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(HermesColors.invert)
            .frame(width: 22, height: 22)
            .background(HermesColors.accent)
            .clipShape(Circle())
    }
}
