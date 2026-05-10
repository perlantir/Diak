import SwiftUI

public struct DaemonOfflineSheet: View {
    @ObservedObject var viewModel: DaemonStatusViewModel
    @State private var isReconnecting = false

    public init(viewModel: DaemonStatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HermesSpacing.lg) {
            VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                HStack(spacing: HermesSpacing.sm) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(HermesColors.warning)
                    Text("Hermes daemon is offline")
                        .font(HermesTypography.title)
                        .foregroundStyle(HermesColors.text)
                }
                Text(reason)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.muted)
            }

            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    Text("Try this")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    bullet("Make sure the Hermes Agent daemon is running.")
                    bullet("Check that nothing else is bound to the configured port.")
                    bullet("Use Settings > Hermes Engine to point the app at a different endpoint.")
                }
            }

            HStack {
                HermesButton("Dismiss", kind: .ghost) {
                    viewModel.dismissOfflineSheet()
                }
                Spacer()
                HermesButton("Reconnect",
                             kind: .primary,
                             isLoading: isReconnecting) {
                    Task {
                        isReconnecting = true
                        await viewModel.refresh()
                        isReconnecting = false
                    }
                }
            }
        }
        .padding(HermesSpacing.xl)
        .frame(width: 460)
        .background(HermesColors.surface)
    }

    private var reason: String {
        if case .offline(let r) = viewModel.status { return r }
        return "Hermes is not currently reachable."
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: HermesSpacing.sm) {
            Text("•").foregroundStyle(HermesColors.subtle)
            Text(text)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.text)
        }
    }
}
