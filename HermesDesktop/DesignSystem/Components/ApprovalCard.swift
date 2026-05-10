import SwiftUI

/// Inline approval card rendered inside chat (screen 08), the inspector
/// activity pane (screen 09), and the Action Center list (screen 11).
/// The card surfaces the kind of side effect, a one-line summary, the
/// risk level, and "Review" / "Deny" affordances. Tapping the card
/// (or "Review") is what opens the full `ApprovalSheet` modal.
public struct ApprovalCard: View {
    public let request: HermesApprovalRequest
    public let onReview: () -> Void
    public let onDeny: () -> Void

    public init(request: HermesApprovalRequest,
                onReview: @escaping () -> Void,
                onDeny: @escaping () -> Void) {
        self.request = request
        self.onReview = onReview
        self.onDeny = onDeny
    }

    public var body: some View {
        HermesCard(padding: HermesSpacing.md) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                header
                if let summary = request.summary, !summary.isEmpty {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                        .padding(.leading, 26)
                }
                preview
                if request.status == .pending {
                    actions
                } else {
                    decided
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Image(systemName: request.kind.iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HermesColors.text)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesColors.text)
                Text(request.kind.displayName)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            RiskBadge(request.displayRisk)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let inset = EdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 0)
        switch request.payload {
        case .terminalCommand(let payload):
            CommandPreviewView(payload: payload).padding(inset)
        case .fileWrite(let payload):
            DiffPreviewView(payload: payload, lineLimit: 6).padding(inset)
        case .connectorSend(let payload):
            ConnectorSendPreviewView(payload: payload, lineLimit: 4).padding(inset)
        case .unknown:
            Text("This action is not previewable in the app.")
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .padding(inset)
        }
    }

    private var actions: some View {
        HStack(spacing: HermesSpacing.sm) {
            Spacer()
            HermesButton("Deny", kind: .destructive, action: onDeny)
            HermesButton("Review", kind: .primary, action: onReview)
        }
        .padding(.top, HermesSpacing.xs)
    }

    private var decided: some View {
        HStack(spacing: HermesSpacing.xs) {
            Image(systemName: request.status == .approved ? "checkmark.seal" : "xmark.seal")
                .foregroundStyle(request.status == .approved ? HermesColors.success : HermesColors.danger)
            Text(request.status.displayName)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            if let note = request.decisionNote, !note.isEmpty {
                Text("· \(note)")
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.top, HermesSpacing.xs)
    }
}
