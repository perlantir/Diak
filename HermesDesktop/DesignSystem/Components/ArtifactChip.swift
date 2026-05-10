import SwiftUI

/// Small placeholder chip representing a file/artifact a session has
/// produced. Used in the inspector "Artifacts" tab and the session
/// detail header. M1 only renders the label — opening artifacts is M2.
public struct ArtifactChip: View {
    public let title: String
    public let kind: Kind

    public enum Kind {
        case file
        case link
        case command
        case other
    }

    public init(title: String, kind: Kind = .file) {
        self.title = title
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: HermesSpacing.xs) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(HermesColors.text)
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, 4)
        .background(HermesColors.field)
        .overlay(
            RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                .strokeBorder(HermesColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
    }

    private var iconName: String {
        switch kind {
        case .file:    return "doc.text"
        case .link:    return "link"
        case .command: return "terminal"
        case .other:   return "square.dashed"
        }
    }
}
