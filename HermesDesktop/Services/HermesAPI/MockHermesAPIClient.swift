import Foundation

/// Deterministic in-memory client used for previews and tests.
public final class MockHermesAPIClient: HermesAPIClient, @unchecked Sendable {
    public enum Outcome: Sendable {
        case success
        case offline
        case unhealthy
    }

    public private(set) var outcome: Outcome
    public private(set) var healthCallCount = 0
    public private(set) var versionCallCount = 0

    public init(outcome: Outcome = .success) {
        self.outcome = outcome
    }

    public func setOutcome(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func health() async throws -> HermesHealth {
        healthCallCount += 1
        switch outcome {
        case .success:
            return HermesHealth(status: .ok, uptimeSeconds: 4321, message: "All systems nominal")
        case .unhealthy:
            return HermesHealth(status: .degraded, uptimeSeconds: 99, message: "Provider rate-limited")
        case .offline:
            throw HermesAPIError.notReachable
        }
    }

    public func version() async throws -> HermesVersion {
        versionCallCount += 1
        switch outcome {
        case .success, .unhealthy:
            return HermesVersion(version: "0.42.0", build: "2026.05.09", profile: "local-dev")
        case .offline:
            throw HermesAPIError.notReachable
        }
    }
}
