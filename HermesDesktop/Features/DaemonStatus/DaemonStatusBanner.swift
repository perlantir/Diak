import SwiftUI

public struct DaemonStatusBanner: View {
    @ObservedObject var viewModel: DaemonStatusViewModel

    public init(viewModel: DaemonStatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: HermesSpacing.sm) {
            StatusBadge(label, tone: viewModel.tone)
            Text(viewModel.summaryLabel)
                .font(HermesTypography.caption)
                .foregroundStyle(HermesColors.muted)
            Spacer()
            HermesButton("Reconnect", kind: .ghost) {
                Task { await viewModel.refresh() }
            }
        }
        .padding(.horizontal, HermesSpacing.lg)
        .padding(.vertical, HermesSpacing.sm)
        .background(HermesColors.surface)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HermesColors.border), alignment: .bottom)
    }

    private var label: String {
        switch viewModel.status {
        case .unknown:    return "Idle"
        case .loading:    return "Connecting"
        case .connected:  return "Connected"
        case .offline:    return "Offline"
        }
    }
}
