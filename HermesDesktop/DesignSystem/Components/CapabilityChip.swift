import SwiftUI

/// Compact, tinted chip used to summarize a tool's capability shape
/// (read / write / destructive). Picks tone from the capability so
/// destructive caps always read loud, regardless of policy.
public struct CapabilityChip: View {
    public let capability: HermesToolCapability

    public init(_ capability: HermesToolCapability) {
        self.capability = capability
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: capability.iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(capability.displayName)
                .font(HermesTypography.caption)
        }
        .foregroundStyle(capability.tone.foreground)
        .padding(.horizontal, HermesSpacing.sm)
        .padding(.vertical, 3)
        .background(capability.tone.background)
        .clipShape(Capsule())
    }
}
