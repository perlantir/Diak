import SwiftUI

struct SettingsView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @ObservedObject var settings: SettingsViewModel
    @State private var selection: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case hermesEngine
        case modelsProviders
        case toolsPermissions
        case securityPrivacy
        case betaReadiness

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:           return "General"
            case .hermesEngine:      return "Hermes Engine"
            case .modelsProviders:   return "Models & Providers"
            case .toolsPermissions:  return "Tools & Permissions"
            case .securityPrivacy:   return "Security & Privacy"
            case .betaReadiness:     return "Beta Readiness"
            }
        }

        var icon: String {
            switch self {
            case .general:           return "gearshape"
            case .hermesEngine:      return "bolt.horizontal.circle"
            case .modelsProviders:   return "cpu"
            case .toolsPermissions:  return "wrench.and.screwdriver"
            case .securityPrivacy:   return "lock.shield"
            case .betaReadiness:     return "checkmark.seal"
            }
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: HermesSpacing.xs) {
                SectionHeader("Settings")
                    .padding(.horizontal, HermesSpacing.sm)
                    .padding(.bottom, HermesSpacing.sm)
                ForEach(Tab.allCases) { tab in
                    SidebarItem(icon: tab.icon,
                                title: tab.title,
                                isSelected: selection == tab) {
                        selection = tab
                    }
                }
                Spacer()
                if settings.savedRequiresRestart {
                    Text("Daemon restart required")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.warning)
                        .padding(.horizontal, HermesSpacing.sm)
                        .padding(.bottom, HermesSpacing.sm)
                }
            }
            .padding(HermesSpacing.sm)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
            .background(HermesColors.sidebar)

            Group {
                switch selection {
                case .general:
                    ProfileSettingsView(viewModel: settings)
                case .hermesEngine:
                    HermesEngineSettingsView(daemon: daemon,
                                             viewModel: engineViewModel,
                                             settings: settings)
                case .modelsProviders:
                    ModelsProvidersView(viewModel: settings)
                case .toolsPermissions:
                    ToolsPermissionsView(viewModel: settings)
                case .securityPrivacy:
                    SecurityPrivacyView(viewModel: settings)
                case .betaReadiness:
                    BetaReadinessView(viewModel: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
        .task { await settings.refresh() }
    }
}
