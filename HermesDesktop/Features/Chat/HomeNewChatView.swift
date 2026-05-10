import SwiftUI

/// Inline empty-state content shown above the composer in the chat
/// workspace when no messages exist yet. Renders the centered hero
/// and three quick-action prompt cards from screen 05. Tapping a
/// prompt fills the composer draft so the user can edit and send.
///
/// This view is intentionally just content — the surrounding
/// `ChatWorkspacePane` owns the chat header and composer so the
/// empty-state never hides the primary chat entry point.
struct ChatEmptyHero: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: HermesSpacing.xl) {
            hero
            quickActions
        }
        .frame(maxWidth: .infinity)
    }

    private var hero: some View {
        VStack(spacing: HermesSpacing.md) {
            Text("H")
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(HermesColors.text)
                .frame(width: 80, height: 80)
                .background(HermesColors.field)
                .clipShape(RoundedRectangle(cornerRadius: HermesRadius.panel,
                                            style: .continuous))
            Text("Ask Hermes to do work on your Mac")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(HermesColors.text)
                .multilineTextAlignment(.center)
            Text("Connect tools, use selected project context, and keep risky actions visible before they happen.")
                .font(.system(size: 13))
                .foregroundStyle(HermesColors.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(.top, HermesSpacing.lg)
    }

    private var quickActions: some View {
        HStack(alignment: .top, spacing: HermesSpacing.lg) {
            QuickActionCard(
                title: "Work on a project",
                prompts: [
                    "Summarize this project and suggest next steps.",
                    "Find brittle tests and draft a fix plan."
                ],
                onTap: { fill($0) }
            )
            QuickActionCard(
                title: "Automate a task",
                prompts: [
                    "Check my open GitHub PRs every weekday morning.",
                    "Every Friday, review stale Linear issues."
                ],
                onTap: { fill($0) }
            )
            QuickActionCard(
                title: "Connect a tool",
                prompts: [
                    "Draft a reply to this email, but ask before sending.",
                    "Turn this workflow into a reusable skill."
                ],
                onTap: { fill($0) }
            )
        }
        .frame(maxWidth: 1080)
    }

    private func fill(_ prompt: String) {
        viewModel.draft = prompt
    }
}

private struct QuickActionCard: View {
    let title: String
    let prompts: [String]
    let onTap: (String) -> Void

    var body: some View {
        HermesCard {
            VStack(alignment: .leading, spacing: HermesSpacing.md) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HermesColors.text)
                VStack(alignment: .leading, spacing: HermesSpacing.sm) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            onTap(prompt)
                        } label: {
                            HStack(alignment: .top, spacing: HermesSpacing.sm) {
                                Text("•")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(HermesColors.text)
                                Text(prompt)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(HermesColors.text)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
