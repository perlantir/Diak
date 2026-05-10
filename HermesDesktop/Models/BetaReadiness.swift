import Foundation

enum BetaReadinessStatus: String, CaseIterable, Identifiable, Codable, Equatable {
    case pass
    case partial
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pass: return "PASS"
        case .partial: return "PARTIAL"
        case .blocked: return "BLOCKED"
        }
    }

    var isBlockingExternalDistribution: Bool {
        self == .blocked
    }
}

struct BetaReadinessGate: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let status: BetaReadinessStatus
    let detail: String

    init(id: String, title: String, status: BetaReadinessStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

struct BetaReadinessSnapshot: Codable, Equatable {
    let version: String
    let gates: [BetaReadinessGate]

    init(version: String = AppBrand.publicBetaVersion, gates: [BetaReadinessGate]) {
        self.version = version
        self.gates = gates
    }

    static let m9Default = BetaReadinessSnapshot(gates: [
        BetaReadinessGate(
            id: "automated-build-test-package",
            title: "Automated build, tests, and package",
            status: .pass,
            detail: "XcodeGen, Debug build, full XCTest suite, Release archive, DMG creation, and bundle identity checks are part of the M9 gate."
        ),
        BetaReadinessGate(
            id: "product-branding",
            title: "Product branding",
            status: .pass,
            detail: "Primary app surfaces use Diak while Hermes Agent / Hermes Engine remains the runtime terminology."
        ),
        BetaReadinessGate(
            id: "first-run-visual-qa",
            title: "First-run visual QA",
            status: .pass,
            detail: "DMG-copy launch was re-run after unrelated macOS prompts were dismissed; unobstructed onboarding shows Diak branding and first-run actions."
        ),
        BetaReadinessGate(
            id: "local-daemon-contract",
            title: "Local daemon contract",
            status: .pass,
            detail: "The Diak-shaped local API contract is reachable on 127.0.0.1:8765 through the QA compatibility daemon; production Hermes execution remains outside this pass."
        ),
        BetaReadinessGate(
            id: "safe-connector-writes",
            title: "Safe connector write validation",
            status: .blocked,
            detail: "Real external sends/posts require Nick-approved safe destinations and must remain blocked by approval previews until then."
        ),
        BetaReadinessGate(
            id: "developer-id-notarization",
            title: "Developer ID signing and notarization",
            status: .blocked,
            detail: "Local ad-hoc packages are available. External distribution requires Developer ID credentials, notarization, stapling, and Gatekeeper assessment."
        )
    ])

    var internalBetaVerdict: BetaReadinessStatus {
        let blocking = gates.filter { $0.status == .blocked }.map(\.id)
        let allowedInternalBlockers: Set<String> = ["safe-connector-writes", "developer-id-notarization"]
        if blocking.contains(where: { !allowedInternalBlockers.contains($0) }) {
            return .blocked
        }
        return gates.contains(where: { $0.status != .pass }) ? .partial : .pass
    }

    var externalDistributionVerdict: BetaReadinessStatus {
        gates.contains(where: { $0.status == .blocked }) ? .blocked : internalBetaVerdict
    }

    var blockingGateTitles: [String] {
        gates.filter { $0.status == .blocked }.map(\.title)
    }

    var partialGateTitles: [String] {
        gates.filter { $0.status == .partial }.map(\.title)
    }
}
