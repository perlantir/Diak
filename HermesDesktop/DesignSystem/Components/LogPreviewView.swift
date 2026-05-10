import SwiftUI

/// Read-only, monospaced multi-line viewer used by the Hermes Engine
/// settings to surface the daemon's recent log lines truthfully.
public struct LogPreviewView: View {
    public let lines: [String]
    public let maxHeight: CGFloat

    public init(lines: [String], maxHeight: CGFloat = 200) {
        self.lines = lines
        self.maxHeight = maxHeight
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(HermesTypography.mono)
                        .foregroundStyle(HermesColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(HermesSpacing.md)
        }
        .frame(maxHeight: maxHeight)
        .background(HermesColors.field)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}
