import Foundation

public enum SidebarNavSection: String, CaseIterable, Identifiable {
    case home
    case sessions
    case automations
    case connectors
    case skills
    case memory
    case projects
    case actionCenter
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home:         return "Home"
        case .sessions:     return "Sessions"
        case .automations:  return "Automations"
        case .connectors:   return "Connectors"
        case .skills:       return "Skills"
        case .memory:       return "Memory"
        case .projects:     return "Projects"
        case .actionCenter: return "Action Center"
        case .settings:     return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home:         return "house"
        case .sessions:     return "bubble.left.and.bubble.right"
        case .automations:  return "clock.arrow.circlepath"
        case .connectors:   return "link"
        case .skills:       return "wand.and.stars"
        case .memory:       return "brain.head.profile"
        case .projects:     return "folder"
        case .actionCenter: return "tray.full"
        case .settings:     return "gearshape"
        }
    }
}
