import SwiftUI

public struct HermesCard<Content: View>: View {
    private let padding: CGFloat
    private let radius: CGFloat
    private let content: () -> Content

    public init(padding: CGFloat = HermesSpacing.lg,
                radius: CGFloat = HermesRadius.card,
                @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(HermesColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
