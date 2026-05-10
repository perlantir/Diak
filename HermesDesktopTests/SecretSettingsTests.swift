import Foundation
import XCTest
@testable import HermesDesktop

final class SecretSettingsTests: XCTestCase {

    // MARK: - Model decoding / encoding safety

    func testSecretCatalogDecodesSnakeCasePayload() throws {
        let json = Data("""
        {
          "descriptors": [
            {
              "id": "composio",
              "kind": "composio",
              "display_name": "Composio",
              "help_text": "stored in keychain",
              "fields": [
                { "id": "api_key", "kind": "api_key", "label": "API key", "is_required": true },
                { "id": "base_url", "kind": "plain_text", "label": "Base URL", "is_required": false }
              ],
              "test_action_available": true
            }
          ],
          "statuses": [
            {
              "id": "composio",
              "presence": "saved",
              "validity": "valid",
              "last_saved_at": "2026-05-10T12:00:00Z",
              "last_tested_at": "2026-05-10T12:01:00Z",
              "last_test_message": "ok",
              "saved_non_sensitive_field_ids": ["base_url"]
            }
          ],
          "boundary_note": "stored in keychain"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(HermesSecretCatalog.self, from: json)

        XCTAssertEqual(catalog.descriptors.count, 1)
        let composio = try XCTUnwrap(catalog.descriptors.first)
        XCTAssertEqual(composio.kind, .composio)
        XCTAssertEqual(composio.displayName, "Composio")
        XCTAssertEqual(composio.fields.count, 2)
        XCTAssertEqual(composio.fields[0].kind, .apiKey)
        XCTAssertTrue(composio.fields[0].kind.isSensitive)
        XCTAssertFalse(composio.fields[1].kind.isSensitive)

        let status = try XCTUnwrap(catalog.status(for: "composio"))
        XCTAssertEqual(status.presence, .saved)
        XCTAssertEqual(status.validity, .valid)
        XCTAssertEqual(status.savedNonSensitiveFieldIDs, ["base_url"])
        XCTAssertNotNil(status.lastSavedAt)
    }

    func testSecretStatusDoesNotCarryRawValues() throws {
        let status = HermesSecretStatus(
            id: "composio",
            presence: .saved,
            validity: .valid,
            savedNonSensitiveFieldIDs: ["base_url"]
        )
        let encoded = try JSONEncoder().encode(status)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let json = try XCTUnwrap(object)
        XCTAssertNil(json["value"], "Status payloads must not echo raw secret values")
        XCTAssertNil(json["api_key"], "Status payloads must not echo sensitive field values")
        XCTAssertNil(json["fields"], "Status payloads must not embed raw field arrays")
    }

    func testSecretDescriptorDoesNotCarryRawValues() throws {
        let descriptor = HermesSecretDescriptor.composio
        let encoded = try JSONEncoder().encode(descriptor)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let json = try XCTUnwrap(object)
        let fields = try XCTUnwrap(json["fields"] as? [[String: Any]])
        for field in fields {
            XCTAssertNil(field["value"],
                         "Field descriptors must not carry raw values")
        }
    }

    func testUnknownSecretKindFallsBackToUnknown() throws {
        let json = Data("""
        { "descriptors": [], "statuses": [
          { "id": "x", "presence": "weird", "validity": "weird" }
        ] }
        """.utf8)
        let catalog = try JSONDecoder().decode(HermesSecretCatalog.self, from: json)
        let status = try XCTUnwrap(catalog.statuses.first)
        XCTAssertEqual(status.presence, .unknown)
        XCTAssertEqual(status.validity, .unknown)
    }

    func testComposioDescriptorHasPrimarySensitiveField() {
        XCTAssertEqual(HermesSecretDescriptor.composio.primarySensitiveFieldID, "api_key")
        XCTAssertEqual(HermesSecretDescriptor.composio.fields.first?.kind, .apiKey)
    }

    func testSecretSaveRequestIsEmptyForBlankFields() {
        let blank = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "")],
            acknowledgedKeychainStorage: true
        )
        XCTAssertTrue(blank.isEmpty)

        let filled = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "secret")],
            acknowledgedKeychainStorage: true
        )
        XCTAssertFalse(filled.isEmpty)
        XCTAssertEqual(filled.value(for: "api_key"), "secret")
    }

    // MARK: - Mock client behavior

    func testMockSecretsReturnsDescriptorsAndMissingStatusByDefault() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let catalog = try await client.secrets()
        XCTAssertEqual(catalog.descriptors.map(\.id), ["composio"])
        let status = try XCTUnwrap(catalog.status(for: "composio"))
        XCTAssertEqual(status.presence, .missing)
        XCTAssertEqual(status.validity, .untested)
        XCTAssertEqual(client.secretsCallCount, 1)
    }

    func testMockSaveSecretRequiresAcknowledgement() async {
        let client = MockHermesAPIClient()
        let request = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
            acknowledgedKeychainStorage: false
        )
        do {
            _ = try await client.saveSecret(request)
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockSaveSecretRejectsEmptyValues() async {
        let client = MockHermesAPIClient()
        let request = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "")],
            acknowledgedKeychainStorage: true
        )
        do {
            _ = try await client.saveSecret(request)
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockSaveSecretFlipsPresenceAndDoesNotEchoValues() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let request = HermesSecretSaveRequest(
            id: "composio",
            fields: [
                HermesSecretFieldValue(fieldID: "api_key", value: "comp_live_xyz"),
                HermesSecretFieldValue(fieldID: "base_url", value: "https://example.invalid")
            ],
            acknowledgedKeychainStorage: true
        )
        let result = try await client.saveSecret(request)
        XCTAssertEqual(result.status.presence, .saved)
        XCTAssertEqual(result.status.validity, .untested)
        XCTAssertTrue(result.requiresBridgeRestart)
        XCTAssertEqual(result.status.savedNonSensitiveFieldIDs, ["base_url"])

        // Catalog re-read must not leak the raw value back.
        let catalog = try await client.secrets()
        let encoded = try JSONEncoder().encode(catalog)
        let stringified = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(stringified.contains("comp_live_xyz"),
                       "Secret catalog must never echo raw API key material")

        // Saved values are observable via the test affordance, not the boundary.
        let saved = client._debugSavedSecretValues(forID: "composio")
        XCTAssertEqual(saved["api_key"], "comp_live_xyz")
        XCTAssertEqual(saved["base_url"], "https://example.invalid")
    }

    func testMockTestSecretReportsValidWhenSaved() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        _ = try await client.saveSecret(
            HermesSecretSaveRequest(
                id: "composio",
                fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
                acknowledgedKeychainStorage: true
            )
        )
        let result = try await client.testSecret(id: "composio")
        XCTAssertTrue(result.isOK)
        XCTAssertEqual(result.validity, .valid)
        XCTAssertEqual(client.testSecretCallCount, 1)
    }

    func testMockTestSecretReportsInvalidWhenMissing() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        let result = try await client.testSecret(id: "composio")
        XCTAssertFalse(result.isOK)
        XCTAssertEqual(result.validity, .invalid)
    }

    func testMockDeleteSecretClearsValuesAndStatus() async throws {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        _ = try await client.saveSecret(
            HermesSecretSaveRequest(
                id: "composio",
                fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
                acknowledgedKeychainStorage: true
            )
        )
        let result = try await client.deleteSecret(id: "composio")
        XCTAssertEqual(result.status.presence, .missing)
        XCTAssertTrue(client._debugSavedSecretValues(forID: "composio").isEmpty)
    }

    func testMockSecretsThrowsWhenOffline() async {
        let client = MockHermesAPIClient(outcome: .offline)
        do {
            _ = try await client.secrets()
            XCTFail("Expected notReachable")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .notReachable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockSaveSecretReturns404ForUnknownSlot() async {
        let client = MockHermesAPIClient()
        client.resetSecretState()
        do {
            _ = try await client.saveSecret(
                HermesSecretSaveRequest(
                    id: "no-such-slot",
                    fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
                    acknowledgedKeychainStorage: true
                )
            )
            XCTFail("Expected http(404)")
        } catch let error as HermesAPIError {
            if case .http(let status, _) = error {
                XCTAssertEqual(status, 404)
            } else {
                XCTFail("Expected http(404), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Keychain store behavior

    func testInMemorySecretStoreSetGetDeleteCycle() throws {
        let store = InMemorySecretStore()
        XCTAssertFalse(try store.exists(account: "composio.api_key"))
        try store.setSecret("comp_live", account: "composio.api_key")
        XCTAssertTrue(try store.exists(account: "composio.api_key"))
        XCTAssertEqual(try store.getSecret(account: "composio.api_key"), "comp_live")

        try store.setSecret("comp_live_v2", account: "composio.api_key")
        XCTAssertEqual(try store.getSecret(account: "composio.api_key"), "comp_live_v2")

        try store.deleteSecret(account: "composio.api_key")
        XCTAssertFalse(try store.exists(account: "composio.api_key"))
        XCTAssertNil(try store.getSecret(account: "composio.api_key"))
    }

    func testInMemorySecretStoreRejectsBlankAccount() {
        let store = InMemorySecretStore()
        XCTAssertThrowsError(try store.setSecret("v", account: " ")) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .emptyAccount)
        }
        XCTAssertThrowsError(try store.deleteSecret(account: "")) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .emptyAccount)
        }
    }

    func testInMemorySecretStoreRejectsBlankValue() {
        let store = InMemorySecretStore()
        XCTAssertThrowsError(try store.setSecret("", account: "composio.api_key")) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .emptyValue)
        }
    }

    func testKeychainSecretStoreRoundTripsWithEphemeralService() throws {
        // Use a unique ephemeral service id so the test cannot collide
        // with the developer's real Diak entries or with previous runs.
        let service = "com.uberkiwi.diak.secrets.test.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let account = "composio.api_key"

        // Best-effort cleanup if the test was previously interrupted.
        try? store.deleteSecret(account: account)

        do {
            try store.setSecret("comp_live_keychain", account: account)
        } catch let error as KeychainSecretStoreError {
            // CI sandboxes / locked keychains cannot complete this test.
            // Skip rather than fail the suite when the environment
            // refuses to host the item.
            if case .unhandled(let status) = error,
               status == errSecMissingEntitlement || status == errSecNotAvailable
                || status == errSecInteractionNotAllowed {
                throw XCTSkip("Keychain unavailable in this environment (OSStatus \(status))")
            }
            throw error
        }

        do {
            XCTAssertTrue(try store.exists(account: account))
            XCTAssertEqual(try store.getSecret(account: account), "comp_live_keychain")

            try store.setSecret("comp_live_keychain_v2", account: account)
            XCTAssertEqual(try store.getSecret(account: account), "comp_live_keychain_v2")

            let accounts = try store.listAccounts()
            XCTAssertTrue(accounts.contains(account))

            try store.deleteSecret(account: account)
            XCTAssertFalse(try store.exists(account: account))
            XCTAssertNil(try store.getSecret(account: account))
        } catch let error as KeychainSecretStoreError {
            if case .unhandled(let status) = error,
               status == errSecMissingEntitlement || status == errSecNotAvailable
                || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                try? store.deleteSecret(account: account)
                throw XCTSkip("Keychain read/list unavailable in this environment (OSStatus \(status))")
            }
            throw error
        }
    }

    // MARK: - URLSession wire shape

    func testURLSessionSecretsListEndpointShape() async throws {
        let response = Data("""
        { "descriptors": [], "statuses": [], "boundary_note": "stored in keychain" }
        """.utf8)
        let client = makeURLClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/settings/secrets")
            return (200, response)
        }

        let catalog = try await client.secrets()
        XCTAssertEqual(catalog.boundaryNote, "stored in keychain")
        XCTAssertEqual(SecretURLProtocolStub.requestCount, 1)
    }

    func testURLSessionSaveSecretWiresSnakeCaseBody() async throws {
        let response = Data("""
        {
          "status": {
            "id": "composio",
            "presence": "saved",
            "validity": "untested",
            "saved_non_sensitive_field_ids": []
          },
          "requires_bridge_restart": true,
          "note": "ok"
        }
        """.utf8)
        let client = makeURLClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/settings/secrets/composio")
            let body = try XCTUnwrap(request.httpBodyStream?.readAllSecretsTestData())
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["id"] as? String, "composio")
            XCTAssertEqual(object["acknowledged_keychain_storage"] as? Bool, true)
            let fields = try XCTUnwrap(object["fields"] as? [[String: Any]])
            XCTAssertEqual(fields.first?["field_id"] as? String, "api_key")
            XCTAssertEqual(fields.first?["value"] as? String, "k")
            return (200, response)
        }

        let request = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
            acknowledgedKeychainStorage: true
        )
        let result = try await client.saveSecret(request)
        XCTAssertEqual(result.status.presence, .saved)
        XCTAssertTrue(result.requiresBridgeRestart)
    }

    func testURLSessionSaveSecretRejectsUnacknowledgedRequestLocally() async {
        let client = makeURLClient { _ in
            XCTFail("Unacknowledged saves must not hit the daemon")
            return (500, Data())
        }
        let request = HermesSecretSaveRequest(
            id: "composio",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
            acknowledgedKeychainStorage: false
        )
        do {
            _ = try await client.saveSecret(request)
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(SecretURLProtocolStub.requestCount, 0)
    }

    func testURLSessionSaveSecretRejectsBlankIDLocally() async {
        let client = makeURLClient { _ in
            XCTFail("Blank ids must not hit the daemon")
            return (500, Data())
        }
        let request = HermesSecretSaveRequest(
            id: " ",
            fields: [HermesSecretFieldValue(fieldID: "api_key", value: "k")],
            acknowledgedKeychainStorage: true
        )
        do {
            _ = try await client.saveSecret(request)
            XCTFail("Expected invalidURL")
        } catch let error as HermesAPIError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(SecretURLProtocolStub.requestCount, 0)
    }

    func testURLSessionDeleteSecretEndpointShape() async throws {
        let response = Data("""
        {
          "status": { "id": "composio", "presence": "missing", "validity": "untested", "saved_non_sensitive_field_ids": [] },
          "requires_bridge_restart": true,
          "note": "removed"
        }
        """.utf8)
        let client = makeURLClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/settings/secrets/composio")
            return (200, response)
        }
        let result = try await client.deleteSecret(id: "composio")
        XCTAssertEqual(result.status.presence, .missing)
    }

    func testURLSessionTestSecretEndpointShape() async throws {
        let response = Data("""
        {
          "id": "composio",
          "is_ok": true,
          "validity": "valid",
          "message": "ok",
          "tested_at": "2026-05-10T12:00:00Z"
        }
        """.utf8)
        let client = makeURLClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/settings/secrets/composio/test")
            return (200, response)
        }
        let decoder = ISO8601DateFormatter()
        decoder.formatOptions = [.withInternetDateTime]
        let result = try await client.testSecret(id: "composio")
        XCTAssertTrue(result.isOK)
        XCTAssertEqual(result.validity, .valid)
        XCTAssertEqual(result.message, "ok")
    }

    // MARK: - Helpers

    override func tearDown() {
        super.tearDown()
        SecretURLProtocolStub.reset()
    }

    private func makeURLClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> URLSessionHermesAPIClient {
        SecretURLProtocolStub.reset()
        SecretURLProtocolStub.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SecretURLProtocolStub.self]
        let session = URLSession(configuration: config)
        let client = URLSessionHermesAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            session: session
        )
        // ISO8601 dates appear in `tested_at` / `last_tested_at` payloads.
        return client
    }
}

// MARK: - URLProtocol stub (test-private)

private final class SecretURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        handler = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension InputStream {
    func readAllSecretsTestData() throws -> Data {
        open()
        defer { close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw streamError ?? HermesAPIError.transport("Could not read HTTP body stream")
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
