import SwiftUI

public struct SectionHeader: View {
    public let title: String
    public let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(HermesTypography.section)
                .foregroundStyle(HermesColors.text)
            if let subtitle {
                Text(subtitle)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
