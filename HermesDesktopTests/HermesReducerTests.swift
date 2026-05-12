import XCTest
@testable import HermesDesktop

/// Phase 2 WU2.2 — exhaustive reducer tests.
///
/// Each `HermesAction` case has at least one test verifying it
/// mutates the expected slice (and nothing else). The race policies
/// from `HermesReducer.reduce(_:_:)` have dedicated tests proving
/// the policy holds — these are the load-bearing safety properties
/// WU2.3 (polling coordinator) and WU2.4 (view-model rewire) rely
/// on without reimplementing.
@MainActor
final class HermesReducerTests: XCTestCase {

    // MARK: - Decode helpers

    /// Decoder mirroring `HermesDashboardClient`'s real one:
    /// snake_case → camelCase, ISO8601 dates. Tests construct
    /// dashboard payloads by decoding small JSON literals, which
    /// keeps them in lock-step with the production decode path.
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // swiftlint:disable:next force_try
        try! Self.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func makeStatus(version: String = "0.13.0",
                            pid: Int = 12345) -> HermesDashboardStatus {
        decode(HermesDashboardStatus.self, """
            {"version":"\(version)","gateway_pid":\(pid),"gateway_running":true,
             "gateway_state":"running","active_sessions":0}
            """)
    }

    private func makeSession(id: String = "sess-1") -> HermesDashboardSession {
        decode(HermesDashboardSession.self, """
            {"id":"\(id)","is_active":true,"message_count":3}
            """)
    }

    private func makeSkill(name: String = "skill-a") -> HermesDashboardSkill {
        decode(HermesDashboardSkill.self, """
            {"name":"\(name)","description":"x","enabled":true}
            """)
    }

    private func makeConfig() -> HermesDashboardConfig {
        decode(HermesDashboardConfig.self, """
            {"model":"hermes-agent","timezone":"UTC"}
            """)
    }

    private func makeCronJob(id: String = "cron-1") -> HermesDashboardCronJob {
        decode(HermesDashboardCronJob.self, """
            {"id":"\(id)","name":"daily","prompt":"hello"}
            """)
    }

    private func makeProfile(name: String = "default") -> HermesDashboardProfile {
        decode(HermesDashboardProfile.self, """
            {"name":"\(name)","is_default":true,"model":"hermes-agent"}
            """)
    }

    private func makeModelInfo() -> HermesDashboardModelInfo {
        decode(HermesDashboardModelInfo.self, """
            {"model":"hermes-agent","provider":"openai"}
            """)
    }

    private func makeOAuthProvider(id: String = "openai") -> HermesDashboardOAuthProvider {
        decode(HermesDashboardOAuthProvider.self, """
            {"id":"\(id)","name":"OpenAI"}
            """)
    }

    // MARK: - One test per HermesAction case

    func testDashboardStatusObserved_UpdatesDashboardSlice() {
        let status = makeStatus()
        let after = HermesReducer.reduce(
            .initial,
            .dashboardStatusObserved(status, epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.dashboard.version, "0.13.0")
        XCTAssertEqual(after.dashboard.gatewayPid, 12345)
    }

    func testSessionsObserved_ReplacesSessionsList() {
        let s1 = makeSession(id: "a")
        let s2 = makeSession(id: "b")
        let after = HermesReducer.reduce(
            .initial,
            .sessionsObserved([s1, s2], epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.sessions.map(\.id), ["a", "b"])
    }

    func testSkillsObserved_ReplacesSkillsList() {
        let skill = makeSkill(name: "writer")
        let after = HermesReducer.reduce(
            .initial,
            .skillsObserved([skill], epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.skills.map(\.name), ["writer"])
    }

    func testConfigObserved_SetsConfig() {
        let cfg = makeConfig()
        let after = HermesReducer.reduce(
            .initial,
            .configObserved(cfg, epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.config?.model, "hermes-agent")
    }

    func testCronJobsObserved_ReplacesCronJobsList() {
        let job = makeCronJob()
        let after = HermesReducer.reduce(
            .initial,
            .cronJobsObserved([job], epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.cronJobs.map(\.id), ["cron-1"])
    }

    func testProfilesObserved_ReplacesProfilesList() {
        let prof = makeProfile()
        let after = HermesReducer.reduce(
            .initial,
            .profilesObserved([prof], epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.profiles.map(\.name), ["default"])
    }

    func testModelInfoObserved_SetsModelInfo() {
        let info = makeModelInfo()
        let after = HermesReducer.reduce(
            .initial,
            .modelInfoObserved(info, epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.modelInfo?.model, "hermes-agent")
    }

    func testOAuthProvidersObserved_ReplacesProvidersList() {
        let provider = makeOAuthProvider()
        let after = HermesReducer.reduce(
            .initial,
            .oauthProvidersObserved([provider], epoch: 0, source: .poll)
        )
        XCTAssertEqual(after.oauthProviders.map(\.id), ["openai"])
    }

    func testUserInitiatedRefresh_AddsToPendingSet() {
        let after = HermesReducer.reduce(
            .initial,
            .userInitiatedRefresh(endpoint: .skills)
        )
        XCTAssertEqual(after.pendingUserRefresh, [.skills])
    }

    func testUserRefreshFailed_ClearsPendingAndRecordsError() {
        var initial = HermesStateSnapshot.initial
        initial.pendingUserRefresh = [.config]

        let after = HermesReducer.reduce(
            initial,
            .userRefreshFailed(endpoint: .config, reason: "boom")
        )

        XCTAssertFalse(after.pendingUserRefresh.contains(.config))
        XCTAssertEqual(after.phase2Errors.count, 1)
        XCTAssertEqual(after.phase2Errors.first?.endpoint, .config)
        XCTAssertEqual(after.phase2Errors.first?.reason, "boom")
    }

    func testSupervisorHealthChanged_UpdatesHealth() {
        let after = HermesReducer.reduce(
            .initial,
            .supervisorHealthChanged(.starting)
        )
        XCTAssertEqual(after.supervisorHealth, .starting)
    }

    func testTokenRotated_IncrementsEpoch() {
        let after = HermesReducer.reduce(
            .initial,
            .tokenRotated(newEpoch: 7)
        )
        XCTAssertEqual(after.currentEpoch, 7)
    }

    func testTokenRotated_IgnoresRegression() {
        var initial = HermesStateSnapshot.initial
        initial.currentEpoch = 5

        let after = HermesReducer.reduce(initial, .tokenRotated(newEpoch: 3))

        XCTAssertEqual(after.currentEpoch, 5, "epoch must only advance")
        XCTAssertEqual(after, initial, "regression must be a complete no-op")
    }

    func testDiakSessionCreated_AppendsID() {
        let id = UUID()
        let after = HermesReducer.reduce(.initial, .diakSessionCreated(id))
        XCTAssertEqual(after.diakSessions, [id])
    }

    func testDiakSessionCreated_IsIdempotent() {
        let id = UUID()
        var initial = HermesStateSnapshot.initial
        initial.diakSessions = [id]

        let after = HermesReducer.reduce(initial, .diakSessionCreated(id))
        XCTAssertEqual(after, initial, "duplicate create must be no-op")
    }

    func testDiakSessionDeleted_RemovesID() {
        let id = UUID()
        let other = UUID()
        var initial = HermesStateSnapshot.initial
        initial.diakSessions = [id, other]

        let after = HermesReducer.reduce(initial, .diakSessionDeleted(id))

        XCTAssertEqual(after.diakSessions, [other])
    }

    func testDiakSessionDeleted_MissingIDIsNoOp() {
        let absent = UUID()
        let after = HermesReducer.reduce(.initial, .diakSessionDeleted(absent))
        XCTAssertEqual(after, .initial)
    }

    func testPollError_AppendsToErrorRing() {
        let after = HermesReducer.reduce(
            .initial,
            .pollError(endpoint: .skills, reason: "timeout", epoch: 0)
        )
        XCTAssertEqual(after.phase2Errors.count, 1)
        XCTAssertEqual(after.phase2Errors.first?.endpoint, .skills)
        XCTAssertEqual(after.phase2Errors.first?.reason, "timeout")
    }

    func testPollError_BoundedRingDropsOldestPastCapacity() {
        // Hammer beyond capacity and verify only the last N survive.
        var snap = HermesStateSnapshot.initial
        for index in 0..<(phase2ErrorRingCapacity + 5) {
            snap = HermesReducer.reduce(
                snap,
                .pollError(endpoint: .skills, reason: "err\(index)", epoch: 0)
            )
        }
        XCTAssertEqual(snap.phase2Errors.count, phase2ErrorRingCapacity)
        // First 5 entries (err0..err4) should be dropped — first
        // surviving entry is err5.
        XCTAssertEqual(snap.phase2Errors.first?.reason, "err5")
        XCTAssertEqual(snap.phase2Errors.last?.reason, "err\(phase2ErrorRingCapacity + 4)")
    }

    // MARK: - Race policy 1: token epoch on actions

    func testRacePolicy_StaleEpochAction_IsDropped() {
        var initial = HermesStateSnapshot.initial
        initial.currentEpoch = 5

        let staleStatus = makeStatus(version: "STALE")
        let after = HermesReducer.reduce(
            initial,
            .dashboardStatusObserved(staleStatus, epoch: 3, source: .poll)
        )

        XCTAssertEqual(after, initial,
                       "observation with epoch < currentEpoch must be a complete no-op")
        XCTAssertNil(after.dashboard.version,
                     "stale observation must not leak into the dashboard slice")
    }

    func testRacePolicy_FreshEpochAction_IsApplied() {
        var initial = HermesStateSnapshot.initial
        initial.currentEpoch = 5

        let fresh = makeStatus(version: "FRESH")
        let after = HermesReducer.reduce(
            initial,
            .dashboardStatusObserved(fresh, epoch: 5, source: .poll)
        )

        XCTAssertEqual(after.dashboard.version, "FRESH")
    }

    // MARK: - Race policy 2: user-initiated wins over poll for same
    // endpoint

    func testRacePolicy_UserPending_SuppressesPollForSameEndpoint() {
        // User clicks refresh → endpoint marked pending.
        let s1 = HermesReducer.reduce(
            .initial,
            .userInitiatedRefresh(endpoint: .status)
        )
        XCTAssertTrue(s1.pendingUserRefresh.contains(.status))

        // Concurrent poll arrives → must be dropped.
        let pollStatus = makeStatus(version: "POLL")
        let s2 = HermesReducer.reduce(
            s1,
            .dashboardStatusObserved(pollStatus, epoch: 0, source: .poll)
        )
        XCTAssertEqual(s2, s1, "poll for pending endpoint must be dropped")
        XCTAssertNil(s2.dashboard.version, "poll payload must not be applied")
    }

    func testRacePolicy_UserInitiatedObservation_AppliesAndClearsPending() {
        let s1 = HermesReducer.reduce(
            .initial,
            .userInitiatedRefresh(endpoint: .status)
        )

        let userPayload = makeStatus(version: "USER")
        let s2 = HermesReducer.reduce(
            s1,
            .dashboardStatusObserved(userPayload, epoch: 0, source: .userInitiated)
        )

        XCTAssertEqual(s2.dashboard.version, "USER",
                       "user-initiated observation must be applied")
        XCTAssertFalse(s2.pendingUserRefresh.contains(.status),
                       "user-initiated arrival must clear the pending flag")
    }

    func testRacePolicy_UserPending_DoesNotSuppressOtherEndpoints() {
        // User-pending on .status must not block a poll on .skills.
        let s1 = HermesReducer.reduce(
            .initial,
            .userInitiatedRefresh(endpoint: .status)
        )

        let skill = makeSkill(name: "ok")
        let s2 = HermesReducer.reduce(
            s1,
            .skillsObserved([skill], epoch: 0, source: .poll)
        )

        XCTAssertEqual(s2.skills.map(\.name), ["ok"],
                       "user-pending on one endpoint must not block polls on others")
    }

    // MARK: - Race policy 3: Diak-owned IDs preserved across stale
    // polls

    func testRacePolicy_DiakSessions_UnaffectedByHermesSessionsPoll() {
        let diakID = UUID()
        var initial = HermesStateSnapshot.initial
        initial.diakSessions = [diakID]

        // A Hermes-side sessions observation arrives — possibly an
        // empty list, possibly an unrelated set.
        let hermesSession = makeSession(id: "hermes-sess-A")
        let after = HermesReducer.reduce(
            initial,
            .sessionsObserved([hermesSession], epoch: 0, source: .poll)
        )

        XCTAssertEqual(after.diakSessions, [diakID],
                       "Diak-owned IDs must survive Hermes session polls")
        XCTAssertEqual(after.sessions.map(\.id), ["hermes-sess-A"],
                       "Hermes-side slice updates normally")
    }

    func testRacePolicy_DiakSessions_EmptyHermesPollDoesNotEraseDiakIDs() {
        let diakID = UUID()
        var initial = HermesStateSnapshot.initial
        initial.diakSessions = [diakID]

        let after = HermesReducer.reduce(
            initial,
            .sessionsObserved([], epoch: 0, source: .poll)
        )

        XCTAssertEqual(after.diakSessions, [diakID],
                       "empty Hermes poll must not collapse the Diak ID list")
    }

    // MARK: - Race policy 4: duplicate supervisorHealthChanged
    // deduped

    func testRacePolicy_DuplicateCrashedHealth_IsDeduped() {
        let s1 = HermesReducer.reduce(
            .initial,
            .supervisorHealthChanged(.crashed(reason: "exit-code-1"))
        )
        XCTAssertEqual(s1.supervisorHealth, .crashed(reason: "exit-code-1"))

        // Second emission with identical payload — should be a
        // complete no-op (snapshot equal to s1).
        let s2 = HermesReducer.reduce(
            s1,
            .supervisorHealthChanged(.crashed(reason: "exit-code-1"))
        )

        XCTAssertEqual(s2, s1, "duplicate health change must produce no-op snapshot")
    }

    func testRacePolicy_DistinctCrashedReasons_AreNotDeduped() {
        // Different reasons must NOT be merged — the reducer dedup
        // is strict equality.
        let s1 = HermesReducer.reduce(
            .initial,
            .supervisorHealthChanged(.crashed(reason: "first"))
        )
        let s2 = HermesReducer.reduce(
            s1,
            .supervisorHealthChanged(.crashed(reason: "second"))
        )

        XCTAssertEqual(s2.supervisorHealth, .crashed(reason: "second"))
        XCTAssertNotEqual(s2, s1)
    }
}
