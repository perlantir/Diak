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

    func testSaveResultRestartRequirementSurvivesRefreshWhenSnapshotBitsAreClean() async throws {
        let snapshot = MockHermesData.configSnapshot
        let client = RestartOnlyConfigClient(snapshot: snapshot)
        let viewModel = SettingsViewModel(client: client)
        await viewModel.refresh()

        var draft = try XCTUnwrap(viewModel.draft)
        var profile = try XCTUnwrap(draft.profiles.first(where: { $0.id == snapshot.activeProfileID }))
        profile.displayName = "Restart-only profile"
        let index = try XCTUnwrap(draft.profiles.firstIndex(where: { $0.id == profile.id }))
        draft.profiles[index] = profile
        viewModel.draft = draft

        await viewModel.save()
        XCTAssertTrue(viewModel.savedRequiresRestart)
        XCTAssertEqual(viewModel.saveState, .savedRequiresRestart("Daemon restart queued"))

        await viewModel.refresh()
        XCTAssertTrue(viewModel.savedRequiresRestart)
        XCTAssertEqual(viewModel.saveState, .savedRequiresRestart("Daemon restart queued"))
    }

    func testSaveCanRetryAfterFailureAndCanSaveAdditionalEditsWhileRestartPending() async throws {
        let client = MockHermesAPIClient()
        let viewModel = SettingsViewModel(client: client)
        await viewModel.refresh()

        var draft = try XCTUnwrap(viewModel.draft)
        draft.tools[0].isEnabled.toggle()
        draft.tools[0].restartRequired = true
        viewModel.draft = draft

        client.outcome = .offline
        await viewModel.save()
        XCTAssertEqual(viewModel.saveState, .failed(HermesAPIError.notReachable.userFacingMessage))

        client.outcome = .success
        await viewModel.save()
        XCTAssertEqual(client.updateConfigCallCount, 2)
        XCTAssertTrue(viewModel.savedRequiresRestart)

        var secondDraft = try XCTUnwrap(viewModel.draft)
        secondDraft.profiles[0].displayName = "Second edit before restart"
        viewModel.draft = secondDraft
        await viewModel.save()

        XCTAssertEqual(client.updateConfigCallCount, 3)
        XCTAssertTrue(viewModel.savedRequiresRestart,
                      "A second non-restart edit must not clear a prior pending daemon restart")
        XCTAssertEqual(viewModel.saved?.profiles[0].displayName, "Second edit before restart")
    }

    func testRestartDaemonShowsProgressThenSuccessAndClearsRestartRequirement() async throws {
        let client = MockHermesAPIClient()
        client.daemonLifecycleDelayNanos = 250_000_000
        let viewModel = SettingsViewModel(client: client)
        await viewModel.refresh()

        var draft = try XCTUnwrap(viewModel.draft)
        draft.tools[0].isEnabled.toggle()
        draft.tools[0].restartRequired = true
        viewModel.draft = draft
        await viewModel.save()
        XCTAssertTrue(viewModel.savedRequiresRestart)

        let restartTask = Task { await viewModel.restartDaemon() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(viewModel.saveState, .restartingDaemon)

        await restartTask.value
        XCTAssertEqual(client.restartDaemonCallCount, 1)
        XCTAssertEqual(viewModel.saveState, .daemonRestarted("Restart scheduled."))
        XCTAssertFalse(viewModel.savedRequiresRestart)
    }

    func testProviderDiffDoesNotMutateDaemonOwnedAPIKeyPresence() throws {
        let saved = MockHermesData.configSnapshot
        var draft = saved
        let providerIndex = try XCTUnwrap(draft.providers.firstIndex(where: { $0.needsAPIKey }))
        draft.providers[providerIndex].defaultModel = "claude-sonnet-4-5"
        draft.providers[providerIndex].hasAPIKey.toggle()
        draft.providers[providerIndex].needsAPIKey.toggle()

        let update = SettingsViewModel.diff(saved: saved, draft: draft)
        let provider = try XCTUnwrap(update.providers?.first(where: { $0.id == draft.providers[providerIndex].id }))

        XCTAssertEqual(provider.defaultModel, "claude-sonnet-4-5")
        XCTAssertEqual(provider.hasAPIKey, saved.providers[providerIndex].hasAPIKey)
        XCTAssertEqual(provider.needsAPIKey, saved.providers[providerIndex].needsAPIKey)
    }

    func testDisabledToolPolicyMustMatchDisabledEnabledFlag() throws {
        let tool = HermesToolPermission(
            id: "tool-shell",
            name: "Terminal",
            description: "Run commands",
            canRead: true,
            canWrite: true,
            canDestroy: true,
            policy: .disabled,
            isEnabled: false,
            restartRequired: true
        )

        XCTAssertEqual(tool.policy, .disabled)
        XCTAssertFalse(tool.isEnabled)
        XCTAssertTrue(tool.restartRequired)
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
