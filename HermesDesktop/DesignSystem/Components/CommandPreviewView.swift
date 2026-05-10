import SwiftUI

/// Renders a terminal command preview the way screen 37 calls for: a
/// monospaced command line with a context strip showing working
/// directory + shell. Used inside `ApprovalCard` and `ApprovalSheet`.
public struct CommandPreviewView: View {
    public let payload: HermesTerminalCommandPayload

    public init(payload: HermesTerminalCommandPayload) {
        self.payload = payload
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Text("$")
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.muted)
                Text(payload.command)
                    .font(HermesTypography.mono)
                    .foregroundStyle(HermesColors.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HermesSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesColors.field)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
            contextStrip
        }
    }

    private var contextStrip: some View {
        HStack(spacing: HermesSpacing.md) {
            if let cwd = payload.workingDirectory, !cwd.isEmpty {
                Label(cwd, systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            if let shell = payload.shell, !shell.isEmpty {
                Label(shell, systemImage: "terminal")
            }
            if let estimated = payload.estimatedDurationSeconds {
                Label("~\(estimated)s", systemImage: "clock")
            }
            Spacer()
        }
        .font(HermesTypography.caption)
        .foregroundStyle(HermesColors.muted)
    }
}
