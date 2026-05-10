import SwiftUI

/// Generic key/value row used in settings and status pages.
public struct StatusRow: View {
    public let label: String
    public let value: String
    public let tone: HermesStatusTone
    public let monospaced: Bool

    public init(label: String,
                value: String,
                tone: HermesStatusTone = .neutral,
                monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.tone = tone
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(monospaced ? HermesTypography.mono : HermesTypography.bodyStrong)
                .foregroundStyle(tone == .neutral ? HermesColors.text : tone.foreground)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
