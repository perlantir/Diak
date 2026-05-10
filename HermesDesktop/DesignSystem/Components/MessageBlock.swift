import SwiftUI

/// Single message in a chat transcript. Layout matches screens 06/07:
/// a label ("You" / "Hermes"), an optional avatar for the assistant,
/// the body text, an optional streaming indicator, and an optional
/// stack of `ToolCallCard`s for any tool activity attached to the
/// message.
public struct MessageBlock: View {
    public let message: HermesMessage

    public init(message: HermesMessage) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            avatar
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text(message.role.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesColors.muted)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(HermesColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if message.isStreaming {
                    StreamingIndicator()
                        .padding(.top, HermesSpacing.xs)
                }
                if !message.toolActivities.isEmpty {
                    VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                        ForEach(message.toolActivities) { activity in
                            ToolCallCard(activity: activity)
                        }
                    }
                    .padding(.top, HermesSpacing.sm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, HermesSpacing.sm)
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.role {
        case .assistant:
            Text("H")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(HermesColors.invert)
                .frame(width: 22, height: 22)
                .background(HermesColors.accent)
                .clipShape(Circle())
        case .user:
            Color.clear.frame(width: 22, height: 22)
        case .system, .tool, .unknown:
            Image(systemName: "circle.dashed")
                .foregroundStyle(HermesColors.muted)
                .frame(width: 22, height: 22)
        }
    }
}

private struct StreamingIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: HermesSpacing.xs) {
            Circle()
                .fill(HermesColors.muted)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            Text("Writing…")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HermesColors.muted)
        }
        .onAppear { pulse = true }
    }
}
