import SwiftUI

public enum RiskLevel: String {
    case low
    case medium
    case high
    case critical

    var label: String {
        switch self {
        case .low:      return "Low risk"
        case .medium:   return "Medium risk"
        case .high:     return "High risk"
        case .critical: return "Critical risk"
        }
    }

    var tone: HermesStatusTone {
        switch self {
        case .low:      return .success
        case .medium:   return .info
        case .high:     return .warning
        case .critical: return .danger
        }
    }
}

public struct RiskBadge: View {
    public let level: RiskLevel

    public init(_ level: RiskLevel) {
        self.level = level
    }

    public var body: some View {
        StatusBadge(level.label, tone: level.tone)
    }
}
