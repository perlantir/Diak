import SwiftUI

/// Renders a connector POST/send preview the way screen 39 calls for: a
/// header strip with the connector + endpoint + recipient, and a body
/// preview block. Long bodies are clipped to `lineLimit` lines for
/// inline use; the sheet renders the full body.
public struct ConnectorSendPreviewView: View {
    public let payload: HermesConnectorSendPayload
    public let lineLimit: Int?

    public init(payload: HermesConnectorSendPayload, lineLimit: Int? = nil) {
        self.payload = payload
        self.lineLimit = lineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.xs) {
            header
            if let body = payload.bodyPreview, !body.isEmpty {
                bodyBlock(body)
            }
        }
    }

    private var header: some View {
        HStack(spacing: HermesSpacing.sm) {
            Image(systemName: payload.connectorIcon ?? "paperplane")
                .foregroundStyle(HermesColors.text)
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.connectorName)
                    .font(HermesTypography.bodyStrong)
                    .foregroundStyle(HermesColors.text)
                HStack(spacing: HermesSpacing.xs) {
                    Text(payload.method)
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.invert)
                        .padding(.horizontal, HermesSpacing.xs)
                        .padding(.vertical, 1)
                        .background(HermesColors.accent)
                        .clipShape(Capsule())
                    Text(payload.endpoint)
                        .font(HermesTypography.mono)
                        .foregroundStyle(HermesColors.muted)
                    if let recipient = payload.recipient {
                        Text("→ \(recipient)")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                }
            }
            Spacer()
        }
    }

    private func bodyBlock(_ body: String) -> some View {
        let lines = body.split(whereSeparator: { $0.isNewline }).map(String.init)
        let shown: [String]
        let truncated: String?
        if let lineLimit, lines.count > lineLimit {
            shown = Array(lines.prefix(lineLimit))
            truncated = "+\(lines.count - lineLimit) more lines — open to review."
        } else {
            shown = lines
            truncated = nil
        }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let truncated {
                Text(truncated)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
        .padding(HermesSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HermesColors.field)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }
}
