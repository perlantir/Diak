import SwiftUI

/// Bottom-of-chat composer (screens 05/06/07). Owns the text input,
/// the contextual chip rail (attach/screenshot/voice/project/skill),
/// and the primary action button which toggles between Send and Stop
/// depending on whether a stream is in flight.
public struct ChatComposer: View {
    @Binding public var text: String
    public let placeholder: String
    public let isStreaming: Bool
    public let canSend: Bool
    public let onSend: () -> Void
    public let onStop: () -> Void

    public init(text: Binding<String>,
                placeholder: String = "Ask Hermes to do something…",
                isStreaming: Bool = false,
                canSend: Bool = true,
                onSend: @escaping () -> Void,
                onStop: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.isStreaming = isStreaming
        self.canSend = canSend
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: HermesSpacing.sm) {
            inputField
            chipRow
        }
        .padding(HermesSpacing.md)
        .background(HermesColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.panel, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.panel, style: .continuous))
    }

    private var inputField: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(HermesColors.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .foregroundStyle(HermesColors.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36, maxHeight: 96)
                    .accessibilityLabel("Chat message input")
                    .accessibilityHint("Type a request for Hermes")
                    .accessibilityIdentifier("chat-composer-input")
            }
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isStreaming {
            HermesButton("Stop", kind: .secondary, action: onStop)
                .accessibilityLabel("Stop streaming")
                .accessibilityIdentifier("chat-composer-stop")
        } else {
            HermesButton("Send", kind: .primary, action: onSend)
                .opacity(canSend ? 1 : 0.5)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Send message")
                .accessibilityHint(canSend ? "Send the current chat message" : "Enter a message before sending")
                .accessibilityIdentifier("chat-composer-send")
        }
    }

    private var chipRow: some View {
        HStack(spacing: HermesSpacing.sm) {
            ComposerChip(icon: "paperclip", label: "Attach")
            ComposerChip(icon: "camera.viewfinder", label: "Screenshot")
            ComposerChip(icon: "mic", label: "Voice")
            ComposerChip(icon: "folder", label: "Project")
            ComposerChip(icon: "wand.and.stars", label: "Skill")
            Spacer()
            Text(isStreaming ? "Streaming…" : "⌘↵ to send")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HermesColors.muted)
        }
    }
}

private struct ComposerChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(HermesColors.muted)
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, 4)
        .background(HermesColors.field)
        .clipShape(Capsule())
    }
}
