import SwiftUI

struct SettingsView: View {
    @ObservedObject var daemon: DaemonStatusViewModel
    @ObservedObject var engineViewModel: HermesEngineViewModel
    @State private var selection: Tab = .hermesEngine

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case hermesEngine
        case modelsProviders
        case toolsPermissions
        case securityPrivacy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:           return "General"
            case .hermesEngine:      return "Hermes Engine"
            case .modelsProviders:   return "Models & Providers"
            case .toolsPermissions:  return "Tools & Permissions"
            case .securityPrivacy:   return "Security & Privacy"
            }
        }

        var icon: String {
            switch self {
            case .general:           return "gearshape"
            case .hermesEngine:      return "bolt.horizontal.circle"
            case .modelsProviders:   return "cpu"
            case .toolsPermissions:  return "wrench.and.screwdriver"
            case .securityPrivacy:   return "lock.shield"
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
            }
            .padding(HermesSpacing.sm)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
            .background(HermesColors.sidebar)

            Group {
                switch selection {
                case .general:
                    EmptyStateView(icon: "gearshape",
                                   title: "General",
                                   message: "Appearance, hotkeys, startup, and updates land in later milestones.")
                case .hermesEngine:
                    HermesEngineSettingsView(daemon: daemon, viewModel: engineViewModel)
                case .modelsProviders:
                    EmptyStateView(icon: "cpu",
                                   title: "Models & Providers",
                                   message: "Configure which providers Hermes routes to. Coming in M3.")
                case .toolsPermissions:
                    EmptyStateView(icon: "wrench.and.screwdriver",
                                   title: "Tools & Permissions",
                                   message: "Per-tool approval policies and capability scopes. Coming in M3.")
                case .securityPrivacy:
                    EmptyStateView(icon: "lock.shield",
                                   title: "Security & Privacy",
                                   message: "Logs, redaction, and trust folders. Coming in M3.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColors.canvas)
        }
    }
}
