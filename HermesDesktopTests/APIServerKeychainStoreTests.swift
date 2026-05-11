import XCTest
@testable import HermesDesktop

/// Tests for `APIServerKeychainStore`. These hit the real macOS Keychain,
/// using a per-test unique account name so concurrent test runs do not
/// race. The store is deleted in `tearDown` even on failure so test runs
/// don't leak Keychain items.
@MainActor
final class APIServerKeychainStoreTests: XCTestCase {

    /// Unique per-test account so multiple test methods can run without
    /// interfering. The test service is the same across the suite so the
    /// real Keychain treats them as related items but distinct entries.
    private let testService = "com.uberkiwi.diak.tests.api-server-keychain"
    private var account: String = ""

    override func setUp() async throws {
        try await super.setUp()
        account = "test-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        // Best-effort cleanup so accumulated tests don't pollute the
        // real Keychain over time. Ignores errors.
        let store = APIServerKeychainStore(service: testService, account: account)
        try? store.deleteKey()
        try await super.tearDown()
    }

    func testStoreThenLoad_RoundTripsTheValue() throws {
        let store = APIServerKeychainStore(service: testService, account: account)
        try store.store(key: "sk-test-roundtrip")
        let loaded = try store.loadKey()
        XCTAssertEqual(loaded, "sk-test-roundtrip")
    }

    func testLoad_WhenNoEntryStored_ReturnsNil() throws {
        let store = APIServerKeychainStore(service: testService, account: account)
        let loaded = try store.loadKey()
        XCTAssertNil(loaded)
    }

    /// SCOPE.md WU4 acceptance #4: "Keychain stores and retrieves the
    /// API Server key correctly across app restarts." We approximate
    /// "across restarts" by constructing two distinct store instances
    /// — they're separate Swift values but address the same Keychain
    /// item by (service, account).
    func testStore_PersistsAcrossInstances() throws {
        let writer = APIServerKeychainStore(service: testService, account: account)
        try writer.store(key: "sk-cross-instance")

        let reader = APIServerKeychainStore(service: testService, account: account)
        let loaded = try reader.loadKey()
        XCTAssertEqual(loaded, "sk-cross-instance")
    }

    func testStore_OverwritesPriorValue() throws {
        let store = APIServerKeychainStore(service: testService, account: account)
        try store.store(key: "old")
        try store.store(key: "new")
        XCTAssertEqual(try store.loadKey(), "new")
    }

    func testDelete_RemovesTheEntry() throws {
        let store = APIServerKeychainStore(service: testService, account: account)
        try store.store(key: "to-be-deleted")
        try store.deleteKey()
        XCTAssertNil(try store.loadKey())
    }

    func testDelete_OnNonexistentEntry_IsIdempotent() throws {
        let store = APIServerKeychainStore(service: testService, account: account)
        // Should not throw even though the entry doesn't exist.
        try store.deleteKey()
    }
}
