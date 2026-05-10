import SwiftUI

/// Renders a unified diff preview the way screen 38 calls for: a
/// header strip with path + add/remove counts and a monospaced block
/// of colorized lines. Long diffs are clipped to `lineLimit` lines
/// inside cards; the sheet passes a larger limit (or nil) for the
/// full preview.
public struct DiffPreviewView: View {
    public let payload: HermesFileWritePayload
    public let lineLimit: Int?

    public init(payload: HermesFileWritePayload, lineLimit: Int? = nil) {
        self.payload = payload
        self.lineLimit = lineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            header
            diffBlock
            if let truncated = truncatedSuffix {
                Text(truncated)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
    }

    private var header: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(HermesColors.muted)
            Text(payload.path)
                .font(HermesTypography.mono)
                .foregroundStyle(HermesColors.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            HStack(spacing: HermesSpacing.xs) {
                Text("+\(payload.addedLines)")
                    .foregroundStyle(HermesColors.success)
                Text("−\(payload.removedLines)")
                    .foregroundStyle(HermesColors.danger)
            }
            .font(HermesTypography.caption)
        }
    }

    private var diffBlock: some View {
        let lines = visibleLines
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(HermesTypography.mono)
                    .foregroundStyle(color(for: line))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HermesSpacing.sm)
                    .padding(.vertical, 1)
                    .background(background(for: line))
            }
        }
        .padding(.vertical, HermesSpacing.xs)
        .background(HermesColors.field)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }

    private var allLines: [String] {
        payload.unifiedDiff.split(whereSeparator: { $0.isNewline }).map(String.init)
    }

    private var visibleLines: [String] {
        guard let lineLimit, allLines.count > lineLimit else { return allLines }
        return Array(allLines.prefix(lineLimit))
    }

    private var truncatedSuffix: String? {
        guard let lineLimit, allLines.count > lineLimit else { return nil }
        return "+\(allLines.count - lineLimit) more lines — open to review the full diff."
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") { return HermesColors.success }
        if line.hasPrefix("-") || line.hasPrefix("−") { return HermesColors.danger }
        if line.hasPrefix("@@") { return HermesColors.info }
        return HermesColors.text
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") { return HermesColors.successBg }
        if line.hasPrefix("-") || line.hasPrefix("−") { return HermesColors.dangerBg }
        return Color.clear
    }
}
