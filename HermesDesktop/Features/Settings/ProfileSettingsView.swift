import SwiftUI

struct ProfileSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainerView("General",
                              subtitle: "Identity, role, and default workspace.",
                              viewModel: viewModel) {
            content
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let activeBinding = viewModel.activeProfileBinding(),
           let draft = viewModel.draft {
            HermesCard {
                VStack(alignment: .leading, spacing: HermesSpacing.md) {
                    Text("Active profile")
                        .font(HermesTypography.bodyStrong)
                        .foregroundStyle(HermesColors.text)
                    Text("This is what shows in the menu bar and the new chat header.")
                        .font(HermesTypography.caption)
                        .foregroundStyle(HermesColors.muted)
                    Divider().background(HermesColors.border)

                    LabeledField("Display name") {
                        TextField("Display name",
                                  text: Binding(
                                    get: { activeBinding.wrappedValue.displayName },
                                    set: { var v = activeBinding.wrappedValue; v.displayName = $0; activeBinding.wrappedValue = v }
                                  ))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField("Role") {
                        Picker("", selection: Binding(
                            get: { activeBinding.wrappedValue.role },
                            set: { var v = activeBinding.wrappedValue; v.role = $0; activeBinding.wrappedValue = v }
                        )) {
                            ForEach(Self.roleOptions, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    LabeledField("Default project") {
                        TextField("Workspace label (optional)",
                                  text: Binding(
                                    get: { activeBinding.wrappedValue.defaultProjectLabel ?? "" },
                                    set: { new in
                                        var v = activeBinding.wrappedValue
                                        v.defaultProjectLabel = new.isEmpty ? nil : new
                                        activeBinding.wrappedValue = v
                                    }
                                  ))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if draft.profiles.count > 1 {
                HermesCard {
                    VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                        Text("Other profiles")
                            .font(HermesTypography.bodyStrong)
                            .foregroundStyle(HermesColors.text)
                        Text("Switching profiles is a single setting Hermes hands to the daemon.")
                            .font(HermesTypography.caption)
                            .foregroundStyle(HermesColors.muted)
                        Divider().background(HermesColors.border)
                        ForEach(draft.profiles) { profile in
                            ProfileRow(profile: profile,
                                       isActive: profile.id == draft.activeProfileID,
                                       onSelect: { switchActive(to: profile) })
                        }
                    }
                }
            }
        } else if viewModel.state == .loading || viewModel.state == .idle {
            HermesCard {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity)
                    .padding(HermesSpacing.lg)
            }
        }
    }

    private static let roleOptions: [HermesProfileRole] = [
        .engineer, .operator_, .researcher, .generalist
    ]

    private func switchActive(to profile: HermesProfile) {
        guard var draft = viewModel.draft else { return }
        draft.activeProfileID = profile.id
        draft.profiles = draft.profiles.map {
            var copy = $0
            copy.isActive = ($0.id == profile.id)
            return copy
        }
        viewModel.draft = draft
    }
}

private struct ProfileRow: View {
    let profile: HermesProfile
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: HermesSpacing.md) {
            Image(systemName: isActive ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isActive ? HermesColors.accent : HermesColors.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(HermesTypography.body)
                    .foregroundStyle(HermesColors.text)
                Text(profile.role.displayName)
                    .font(HermesTypography.caption)
                    .foregroundStyle(HermesColors.muted)
            }
            Spacer()
            if isActive {
                StatusBadge("Active", tone: .success)
            } else {
                HermesButton("Make active", kind: .ghost, action: onSelect)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LabeledField<Field: View>: View {
    let label: String
    let field: () -> Field

    init(_ label: String, @ViewBuilder field: @escaping () -> Field) {
        self.label = label
        self.field = field
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(HermesTypography.body)
                .foregroundStyle(HermesColors.muted)
                .frame(width: 140, alignment: .leading)
            field()
        }
    }
}
