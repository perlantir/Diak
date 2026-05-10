import SwiftUI

/// One row in the inspector activity / artifacts pane (screens 09–10)
/// or the Action Center history list. Renders a status icon, the title
/// of the side effect, a concise summary, and any artifact chips.
public struct ActionEvidenceRow: View {
    public let evidence: HermesActionEvidence

    public init(evidence: HermesActionEvidence) {
        self.evidence = evidence
    }

    public var body: some View {
        HermesCard(padding: HermesSpacing.md) {
            HStack(alignment: .top, spacing: HermesSpacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(iconTone.foreground)
                    .frame(width: 22, height: 22)
                    .background(iconTone.background)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(evidence.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HermesColors.text)
                        Spacer()
                        Text(Self.relative.localizedString(for: evidence.occurredAt,
                                                           relativeTo: Date()))
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                    }
                    if let summary = evidence.summary, !summary.isEmpty {
                        Text(summary)
                            .font(HermesTypography.body)
                            .foregroundStyle(HermesColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    metaRow
                    if !evidence.artifacts.isEmpty {
                        artifactChips
                    }
                }
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: HermesSpacing.sm) {
            StatusBadge(evidence.status.displayName, tone: badgeTone)
            if let actor = evidence.actor {
                Text("by \(actor)")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            if let tool = evidence.toolName {
                Text("· \(tool)")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
        }
    }

    private var artifactChips: some View {
        FlowingChips {
            ForEach(evidence.artifacts) { artifact in
                ArtifactChip(title: artifact.title, kind: artifact.kind.designKind)
            }
        }
    }

    private var iconName: String {
        switch evidence.status {
        case .completed: return "checkmark.circle"
        case .denied:    return "xmark.octagon"
        case .failed:    return "exclamationmark.triangle"
        case .cancelled: return "minus.circle"
        case .running:   return "bolt.fill"
        case .unknown:   return "questionmark.circle"
        }
    }

    private var iconTone: HermesStatusTone {
        switch evidence.status {
        case .completed: return .success
        case .denied:    return .danger
        case .failed:    return .danger
        case .cancelled: return .neutral
        case .running:   return .info
        case .unknown:   return .neutral
        }
    }

    private var badgeTone: HermesStatusTone {
        iconTone
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

private extension HermesArtifactRef.Kind {
    var designKind: ArtifactChip.Kind {
        switch self {
        case .file:    return .file
        case .link:    return .link
        case .command: return .command
        case .message: return .other
        case .generated: return .other
        case .other:   return .other
        case .unknown: return .other
        }
    }
}

/// Lightweight flowing/wrapping HStack used for artifact chip stacks.
private struct FlowingChips<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        // SwiftUI doesn't ship a true wrapping HStack on macOS 13. The
        // chip count here is small (≤ ~6 in practice), so a horizontal
        // ScrollView with disabled indicators reads as a tag row and
        // keeps the layout single-row even with long file paths.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HermesSpacing.xs) { content() }
        }
    }
}
