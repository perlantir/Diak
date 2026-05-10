import SwiftUI

/// Single row in the Sessions list (screen 12). Shows the session
/// title, a one-line summary line composed from status/when/model/
/// project, a status badge, and an optional risk pill for sessions
/// with pending high-risk approvals.
public struct SessionRow: View {
    public let session: HermesSession
    public let isSelected: Bool
    public let action: () -> Void

    public init(session: HermesSession,
                isSelected: Bool = false,
                action: @escaping () -> Void) {
        self.session = session
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: HermesSpacing.md) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesColors.muted)
                    .frame(width: 22, height: 22)
                    .background(HermesColors.field)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HermesColors.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesColors.muted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: HermesSpacing.xs) {
                    StatusBadge(session.status.displayName, tone: tone)
                    if session.pendingApprovalsCount > 0 {
                        RiskBadge(.high)
                    }
                }
            }
            .padding(HermesSpacing.md)
            .background(isSelected ? HermesColors.selected : HermesColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous)
                    .strokeBorder(HermesColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: HermesRadius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let summary = session.summary, !summary.isEmpty { parts.append(summary) }
        parts.append(Self.relative.localizedString(for: session.updatedAt, relativeTo: Date()))
        if let model = session.model { parts.append(model) }
        if let project = session.project { parts.append(project.name) }
        return parts.joined(separator: " · ")
    }

    private var tone: HermesStatusTone {
        switch session.status {
        case .completed: return .success
        case .running:   return .info
        case .waiting:   return .warning
        case .failed:    return .danger
        case .cancelled: return .neutral
        case .unknown:   return .neutral
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
