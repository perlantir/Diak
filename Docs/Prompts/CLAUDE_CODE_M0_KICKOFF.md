You are working on Hermes Desktop at `/Users/perlantir/Projects/HermesDesktop`.

Kick off the build by executing M0 only.

Important current state:

- This directory contains docs/design assets but may not yet contain an Xcode project or git repo.
- Xcode is installed.
- `xcodegen` is installed at `/opt/homebrew/bin/xcodegen` and may be used if useful.
- If there is no git repo, initialize one locally.
- Create a normal SwiftUI macOS app structure that can be built/tested with `xcodebuild`.
- Do not commit unless explicitly asked; just leave working tree changes.

Read and follow this prompt exactly:

`Docs/Prompts/CLAUDE_CODE_M0_PROMPT.md`

Additional constraints:

- M0 only. Do not implement full chat, automations, connectors, OAuth, skills, memory, or menu bar yet.
- Keep Hermes as external/updatable engine via API boundary.
- No destructive commands.
- No secrets.
- Prefer XcodeGen/project.yml if creating a project from scratch because it is easier to review than hand-authored `.pbxproj`.
- If you need to make a scaffolding decision, choose the simplest maintainable SwiftUI macOS app that builds on this machine.
- Run verification commands before finalizing:
  - `xcodebuild -list`
  - the appropriate macOS app build command
  - the appropriate tests command
  - `git status --short`

At the end, report:

1. What you built.
2. Files changed.
3. Exact verification commands and results.
4. Any blockers/risks.
5. Suggested next prompt for M1.
