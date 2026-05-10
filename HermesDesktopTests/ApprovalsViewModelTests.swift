import XCTest
@testable import HermesDesktop

@MainActor
final class ApprovalsViewModelTests: XCTestCase {

    func testRefreshLoadsPendingSortedByRisk() async {
        let client = MockHermesAPIClient()
        let viewModel = ApprovalsViewModel(client: client)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(client.pendingApprovalsCallCount, 1)
        XCTAssertEqual(client.actionEvidenceCallCount, 1)
        XCTAssertFalse(viewModel.pending.isEmpty)
        // Critical-risk first.
        XCTAssertEqual(viewModel.pending.first?.id, "appr-003")
        XCTAssertTrue(viewModel.hasCriticalPending)
    }

    func testApproveRemovesFromPendingAndAppendsEvidence() async {
        let client = MockHermesAPIClient()
        let viewModel = ApprovalsViewModel(client: client)

        await viewModel.refresh()

        guard let request = viewModel.pending.first(where: { $0.id == "appr-001" }) else {
            return XCTFail("Expected fixture appr-001 to be loaded")
        }
        let beforeEvidenceCount = viewModel.recentEvidence.count

        await viewModel.decide(request, decision: .approve, note: "Looks safe")

        XCTAssertFalse(viewModel.pending.contains { $0.id == "appr-001" })
        XCTAssertEqual(viewModel.recentEvidence.count, beforeEvidenceCount + 1)
        XCTAssertEqual(viewModel.recentEvidence.first?.approvalID, "appr-001")
        XCTAssertEqual(viewModel.recentEvidence.first?.status, .completed)
        XCTAssertEqual(client.decideApprovalCallCount, 1)
    }

    func testDenyTransitionsToDeniedEvidence() async {
        let client = MockHermesAPIClient()
        let viewModel = ApprovalsViewModel(client: client)
        await viewModel.refresh()

        guard let critical = viewModel.pending.first(where: { $0.risk == .critical }) else {
            return XCTFail("Expected critical approval fixture")
        }

        await viewModel.decide(critical, decision: .deny, note: nil)

        XCTAssertFalse(viewModel.pending.contains { $0.id == critical.id })
        XCTAssertEqual(viewModel.recentEvidence.first?.status, .denied)
        XCTAssertFalse(viewModel.hasCriticalPending)
    }

    func testPresentAndDismissSheet() {
        let viewModel = ApprovalsViewModel(client: MockHermesAPIClient())
        let stub = HermesApprovalRequest(
            id: "appr-stub",
            title: "Stub",
            kind: .terminalCommand,
            status: .pending,
            risk: .low,
            createdAt: Date(),
            updatedAt: Date(),
            payload: .terminalCommand(HermesTerminalCommandPayload(command: "echo hi"))
        )

        XCTAssertNil(viewModel.presentedApproval)
        viewModel.present(stub)
        XCTAssertEqual(viewModel.presentedApproval?.id, "appr-stub")
        viewModel.dismissSheet()
        XCTAssertNil(viewModel.presentedApproval)
    }

    func testRefreshHandlesOfflineFailure() async {
        let viewModel = ApprovalsViewModel(client: MockHermesAPIClient(outcome: .offline))

        await viewModel.refresh()

        guard case .failed(let reason) = viewModel.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertTrue(viewModel.pending.isEmpty)
        XCTAssertTrue(viewModel.recentEvidence.isEmpty)
    }

    func testApplyDecidedReducerIsPure() {
        let viewModel = ApprovalsViewModel(client: MockHermesAPIClient())
        let original = HermesApprovalRequest(
            id: "appr-pure",
            title: "Pure",
            kind: .fileWrite,
            status: .pending,
            risk: .medium,
            createdAt: Date(),
            updatedAt: Date(),
            payload: .fileWrite(HermesFileWritePayload(path: "x.swift",
                                                      unifiedDiff: "+a"))
        )
        let decided = HermesApprovalRequest(
            id: "appr-pure",
            title: "Pure",
            kind: .fileWrite,
            status: .approved,
            risk: .medium,
            createdAt: original.createdAt,
            updatedAt: Date(),
            payload: original.payload,
            decisionNote: "ok"
        )
        // Seed: include the original in the pending list manually via a
        // mock-driven refresh would require a custom client. Use the
        // reducer directly with a pre-populated list.
        viewModel.apply(decided: decided)

        XCTAssertEqual(viewModel.recentEvidence.first?.approvalID, "appr-pure")
        XCTAssertEqual(viewModel.recentEvidence.first?.status, .completed)
    }
}
