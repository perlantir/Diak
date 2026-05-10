import Foundation
import SwiftUI

public enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case engineSetup
    case modelProvider
    case safetyPermissions
    case complete

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .welcome:           return "Welcome"
        case .engineSetup:       return "Hermes Engine"
        case .modelProvider:     return "Model Provider"
        case .safetyPermissions: return "Safety & Permissions"
        case .complete:          return "Ready"
        }
    }

    var stepIndex: Int { rawValue + 1 }
    static var totalSteps: Int { OnboardingStep.allCases.count - 1 }
}

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var step: OnboardingStep = .welcome
    @Published public var hasCompleted: Bool = false

    public init() {}

    public func next() {
        switch step {
        case .welcome:           step = .engineSetup
        case .engineSetup:       step = .modelProvider
        case .modelProvider:     step = .safetyPermissions
        case .safetyPermissions: step = .complete
        case .complete:          hasCompleted = true
        }
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    public func skip() {
        hasCompleted = true
    }
}
