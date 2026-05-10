import XCTest
@testable import HermesDesktop

@MainActor
final class SettingsViewModelTests: XCTestCase {

    func testRefreshLoadsConfigSnapshot() async throws {
        let client = MockHermesAPIClient()
        let viewModel = SettingsViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(client.configCallCount, 1)
        XCTAssertEqual(viewModel.saved?.activeProfileID, "prof-default")
        XCTAssertEqual(viewModel.draft?.providers.count, MockHermesData.providers.count)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testDraftToolToggleCreatesUnsavedChangeAndSaveUpdatesMock() async throws {
        let client = MockHermesAPIClient()
        let viewModel = SettingsViewModel(client: client)
        await viewModel.refresh()

        guard var tool = viewModel.draft?.tools.first(where: { $0.id == "tool-connectors" }) else {
            return XCTFail("Expected connector tool fixture")
        }
        tool.isEnabled = true
        tool.policy = .autoReadOnly
        tool.restartRequired = true
        var draft = try XCTUnwrap(viewModel.draft)
        let index = try XCTUnwrap(draft.tools.firstIndex(where: { $0.id == tool.id }))
        draft.tools[index] = tool
        viewModel.draft = draft

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.draftRequiresRestart)

        await viewModel.save()

        XCTAssertEqual(client.updateConfigCallCount, 1)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.saved?.tools.first(where: { $0.id == "tool-connectors" })?.isEnabled, true)
        XCTAssertEqual(viewModel.saved?.tools.first(where: { $0.id == "tool-connectors" })?.policy, .autoReadOnly)
        XCTAssertEqual(viewModel.saveState, .savedRequiresRestart("Some changes will take effect after a daemon restart."))
    }

    func testProfileEditDiffSendsOnlyActiveProfile() async throws {
        let saved = MockHermesData.configSnapshot
        var draft = saved
        guard var profile = draft.profiles.first(where: { $0.id == saved.activeProfileID }) else {
            return XCTFail("Expected active profile fixture")
        }
        profile.displayName = "Nick — QA"
        let index = try XCTUnwrap(draft.profiles.firstIndex(where: { $0.id == profile.id }))
        draft.profiles[index] = profile

        let update = SettingsViewModel.diff(saved: saved, draft: draft)

        XCTAssertEqual(update.activeProfile?.displayName, "Nick — QA")
        XCTAssertNil(update.providers)
        XCTAssertNil(update.tools)
        XCTAssertNil(update.security)
    }

    func testRestartDaemonClearsRestartRequiredBits() async throws {
        let client = MockHermesAPIClient()
        let viewModel = SettingsViewModel(client: client)
        await viewModel.refresh()

        var draft = try XCTUnwrap(viewModel.draft)
        var provider = try XCTUnwrap(draft.providers.first)
        provider.restartRequired = true
        draft.providers[0] = provider
        viewModel.draft = draft
        await viewModel.save()

        XCTAssertTrue(viewModel.savedRequiresRestart)

        await viewModel.restartDaemon()

        XCTAssertEqual(client.restartDaemonCallCount, 1)
        XCTAssertFalse(viewModel.savedRequiresRestart)
        XCTAssertFalse(viewModel.saved?.providers.contains(where: { $0.restartRequired }) ?? true)
    }

    func testToolApprovalPolicyExplainsWriteAndDestructiveSafety() {
        let terminal = HermesToolPermission(
            id: "tool-shell",
            name: "Terminal",
            description: "Run commands",
            canRead: true,
            canWrite: true,
            canDestroy: true,
            policy: .alwaysAsk,
            isEnabled: true
        )

        XCTAssertEqual(terminal.capabilities, [.read, .write, .destructive])
        XCTAssertEqual(terminal.policy.displayName, "Always ask")
        XCTAssertTrue(terminal.policy.explanation.localizedCaseInsensitiveContains("ask"))
    }
}
