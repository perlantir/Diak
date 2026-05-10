import SwiftUI

/// Title / subtitle / Toggle settings row used across M3 surfaces.
/// Bind directly to the field — view models handle the diff against
/// the saved snapshot for the unsaved-change indicator.
public struct ToggleRow: View {
    public let title: String
    public let subtitle: String?
    public let footnote: String?
    @Binding public var isOn: Bool

    public init(_ title: String,
                subtitle: String? = nil,
                footnote: String? = nil,
                isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.footnote = footnote
        self._isOn = isOn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                }
                Spacer(minLength: HermesSpacing.md)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if let footnote {
                Text(footnote)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.subtle)
            }
        }
        .padding(.vertical, 4)
    }
}
