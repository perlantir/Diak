import XCTest
@testable import HermesDesktop

final class MockHermesAPIClientTests: XCTestCase {

    func testSuccessReturnsHealthAndVersion() async throws {
        let client = MockHermesAPIClient(outcome: .success)
        let health = try await client.health()
        let version = try await client.version()
        XCTAssertEqual(health.status, .ok)
        XCTAssertEqual(version.version, "0.42.0")
        XCTAssertEqual(client.healthCallCount, 1)
        XCTAssertEqual(client.versionCallCount, 1)
    }

    func testUnhealthyReturnsDegraded() async throws {
        let client = MockHermesAPIClient(outcome: .unhealthy)
        let health = try await client.health()
        XCTAssertEqual(health.status, .degraded)
    }

    func testOfflineThrowsNotReachable() async {
        let client = MockHermesAPIClient(outcome: .offline)
        do {
            _ = try await client.health()
            XCTFail("Expected notReachable")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, HermesAPIError.notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
