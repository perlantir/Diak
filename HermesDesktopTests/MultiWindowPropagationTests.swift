import XCTest
import Combine
@testable import HermesDesktop

/// Phase 2 SCOPE.md acceptance #1 + WU2.3+2.4 acceptance #1:
/// "A UI action in one window reflects in a second window within
/// 2 seconds."
///
/// Two view models bound to the same `HermesState` instance
/// simulate two `WindowGroup`s. A dispatch from one observes via
/// the other's `@Published` properties within the SLA.
///
/// All assertions are local (no network, no supervisor process)
/// and complete in milliseconds — the 2-second SLA is enforced
/// with an explicit `XCTNSPredicateExpectation` so a regression
/// that introduces a 2-second-plus delay would flag as a failure.
@MainActor
final class MultiWindowPropagationTests: XCTestCase {

    private static let propagationSLA: TimeInterval = 2.0

    /// Helper: build a `HermesDashboardSkill` via JSON decode
    /// (the struct's memberwise init is internal/synthesized).
    private func skill(name: String, enabled: Bool) -> HermesDashboardSkill {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(
            HermesDashboardSkill.self,
            from: Data(#"{"name":"\#(name)","description":"x","enabled":\#(enabled)}"#.utf8)
        )
    }

    // MARK: - Two SkillsViewModels, same HermesState

    func testDispatch_FromOneSkillsVM_PropagatesToOtherSkillsVM() async throws {
        let state = HermesState()
        let stub = StubURLProtocol.self
        stub.handler = { _ in (200, [:], Data("[]".utf8)) }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [stub]
        let client = HermesDashboardClient(
            baseURL: HermesDashboardClient.defaultBaseURL,
            requestTimeout: 2,
            tokenProvider: { _ in "tok" },
            session: URLSession(configuration: sessionConfig)
        )

        // "Window A" view model and "Window B" view model, both
        // pointed at the same HermesState.
        let viewA = SkillsViewModel(hermesState: state, dashboardClient: client)
        let viewB = SkillsViewModel(hermesState: state, dashboardClient: client)

        // Initial state — both views empty.
        XCTAssertTrue(viewA.skills.isEmpty)
        XCTAssertTrue(viewB.skills.isEmpty)

        // Dispatch a skills observation as if from a poll.
        let s1 = skill(name: "writer", enabled: true)
        state.dispatch(.skillsObserved([s1], epoch: 0, source: .poll))

        // Both view models must reflect the new data — well under
        // the 2 s SLA because the Combine bridge fires
        // synchronously when @Published emits.
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                viewA.skills.first?.name == "writer"
                    && viewB.skills.first?.name == "writer"
            },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: Self.propagationSLA)
    }

    // MARK: - SessionsVM + SkillsVM observing different slices of same state

    func testDispatch_FromAnyEndpoint_ReachesAnyObserverWithinSLA() async throws {
        let state = HermesState()
        let stub = StubURLProtocol.self
        stub.handler = { _ in (200, [:], Data("[]".utf8)) }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [stub]
        let client = HermesDashboardClient(
            baseURL: HermesDashboardClient.defaultBaseURL,
            requestTimeout: 2,
            tokenProvider: { _ in "tok" },
            session: URLSession(configuration: sessionConfig)
        )

        let sessionsVM = SessionsViewModel(hermesState: state, dashboardClient: client)
        let skillsVM = SkillsViewModel(hermesState: state, dashboardClient: client)

        // Dispatch on skills slice — sessions slice must remain
        // untouched (cross-slice isolation), but skills must update.
        let s = skill(name: "researcher", enabled: false)
        state.dispatch(.skillsObserved([s], epoch: 0, source: .poll))

        let skillsExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                skillsVM.skills.first?.name == "researcher"
            },
            object: nil
        )
        await fulfillment(of: [skillsExpectation], timeout: Self.propagationSLA)
        XCTAssertTrue(sessionsVM.sessions.isEmpty,
                      "cross-slice isolation: skills dispatch must not touch sessions")
    }

    // MARK: - Diak-owned propagation (SwiftData store → HermesState → VMs)

    @available(macOS 14.0, *)
    func testDiakSessionCreate_PropagatesToHermesStateWithinSLA() async throws {
        let state = HermesState()
        let store = try DiakSessionStore(inMemory: true)
        store.attach(hermesState: state)

        // Subscribe via Combine (simulating an observer in a
        // separate window).
        var receivedIDs: [UUID] = []
        let cancellable = state.$diakSessions.sink { ids in
            receivedIDs = ids
        }

        let session = try store.createSession(title: "From Window A")

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                receivedIDs == [session.id]
            },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: Self.propagationSLA)
        cancellable.cancel()
    }
}
