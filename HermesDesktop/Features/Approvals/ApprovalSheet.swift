import SwiftUI

/// Modal sheet shell used by every approval kind. Mirrors the approval
/// modal direction in screens 37 (terminal command), 38 (file diff),
/// and 39 (connector send/post). Lays out a clear "what / why / where"
/// header, a full preview, an optional decision note field, and the
/// Deny / Approve buttons. Risk is repeated twice — header chip and
/// the destructive-styled approve button — so destructive choices
/// never look like a casual click.
public struct ApprovalSheet: View {
    public let request: HermesApprovalRequest
    @ObservedObject var viewModel: ApprovalsViewModel
    @State private var note: String = ""

    public init(request: HermesApprovalRequest, viewModel: ApprovalsViewModel) {
        self.request = request
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: HermesSpacing.lg) {
                    contextSection
                    previewSection
                    noteSection
                    if case .failed(let reason) = viewModel.decisionState {
                        errorBanner(reason: reason)
                    }
                }
                .padding(HermesSpacing.xl)
            }
            footer
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 600)
        .background(HermesColors.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HermesSpacing.md) {
            Image(systemName: request.kind.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HermesColors.text)
                .frame(width: 32, height: 32)
                .background(HermesColors.field)
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control,
                                            style: .continuous))
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                Text(request.title)
                    .font(HermesTypography.title)
                    .foregroundStyle(HermesColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = request.summary, !summary.isEmpty {
                    Text(summary)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: HermesSpacing.xs) {
                RiskBadge(request.displayRisk)
                StatusBadge(request.kind.displayName, tone: .neutral)
            }
        }
        .padding(HermesSpacing.xl)
        .background(HermesColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HermesColors.border).frame(height: 1)
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Where it’s coming from")
            HermesCard(padding: HermesSpacing.md) {
                VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                    contextRow(label: "Session",
                               value: request.sessionTitle ?? request.sessionID ?? "—")
                    contextRow(label: "Tool",
                               value: request.toolName ?? "—")
                    contextRow(label: "Requested by",
                               value: request.requester ?? "Hermes Agent")
                    contextRow(label: "Requested",
                               value: Self.dateFormatter.string(from: request.createdAt))
                }
            }
        }
    }

    private func contextRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
                .textSelection(.enabled)
            Spacer()
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("What Hermes will do",
                          subtitle: "Read the full preview before approving.")
            HermesCard(padding: HermesSpacing.md) {
                switch request.payload {
                case .terminalCommand(let payload):
                    CommandPreviewView(payload: payload)
                case .fileWrite(let payload):
                    DiffPreviewView(payload: payload)
                case .connectorSend(let payload):
                    ConnectorSendPreviewView(payload: payload)
                case .unknown:
                    Text("Diak doesn’t know how to preview this action yet. Approve only if you trust the agent in this session.")
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.sm) {
            SectionHeader("Decision note",
                          subtitle: "Optional — saved with the audit trail.")
            TextEditor(text: $note)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
                .frame(minHeight: 56, maxHeight: 96)
                .padding(HermesSpacing.sm)
                .background(HermesColors.field)
                .overlay(
                    RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous)
                        .strokeBorder(HermesColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.control, style: .continuous))
        }
    }

    private func errorBanner(reason: String) -> some View {
        HermesCard(padding: HermesSpacing.md) {
            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(HermesColors.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn’t submit your decision")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text(reason)
                        .font(HermesTypography.body)
                        .foregroundStyle(HermesColors.muted)
                }
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: HermesSpacing.md) {
            HermesButton("Cancel", kind: .ghost) {
                viewModel.dismissSheet()
            }
            Spacer()
            HermesButton("Deny",
                         kind: .destructive,
                         isLoading: isSubmitting) {
                Task { await viewModel.decide(request,
                                              decision: .deny,
                                              note: trimmedNote) }
            }
            HermesButton(approveLabel,
                         kind: .primary,
                         isLoading: isSubmitting) {
                Task { await viewModel.decide(request,
                                              decision: .approve,
                                              note: trimmedNote) }
            }
        }
        .padding(HermesSpacing.lg)
        .background(HermesColors.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(HermesColors.border).frame(height: 1)
        }
    }

    private var isSubmitting: Bool {
        if case .submitting(let id) = viewModel.decisionState, id == request.id { return true }
        return false
    }

    private var approveLabel: String {
        switch request.displayRisk {
        case .low:      return "Approve"
        case .medium:   return "Approve once"
        case .high:     return "Approve — high risk"
        case .critical: return "Approve — critical risk"
        }
    }

    private var trimmedNote: String? {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
