import XCTest
@testable import HermesDesktop

final class HermesAPIDecodingTests: XCTestCase {

    func testHealthDecodesOk() throws {
        let json = #"""
        { "status": "ok", "uptime_seconds": 12345, "message": "fine" }
        """#.data(using: .utf8)!

        let h = try JSONDecoder().decode(HermesHealth.self, from: json)
        XCTAssertEqual(h.status, .ok)
        XCTAssertEqual(h.uptimeSeconds, 12345)
        XCTAssertEqual(h.message, "fine")
    }

    func testHealthDecodesUnknownStatus() throws {
        let json = #"{ "status": "FROBNICATING" }"#.data(using: .utf8)!
        let h = try JSONDecoder().decode(HermesHealth.self, from: json)
        XCTAssertEqual(h.status, .unknown)
    }

    func testHealthDecodesCaseInsensitively() throws {
        let json = #"{ "status": "Degraded" }"#.data(using: .utf8)!
        let h = try JSONDecoder().decode(HermesHealth.self, from: json)
        XCTAssertEqual(h.status, .degraded)
    }

    func testVersionDecodes() throws {
        let json = #"""
        { "version": "0.42.0", "build": "2026.05.09", "profile": "local-dev" }
        """#.data(using: .utf8)!
        let v = try JSONDecoder().decode(HermesVersion.self, from: json)
        XCTAssertEqual(v.version, "0.42.0")
        XCTAssertEqual(v.build, "2026.05.09")
        XCTAssertEqual(v.profile, "local-dev")
    }

    func testVersionTolerantOfMissingOptionalFields() throws {
        let json = #"{ "version": "0.42.0" }"#.data(using: .utf8)!
        let v = try JSONDecoder().decode(HermesVersion.self, from: json)
        XCTAssertEqual(v.version, "0.42.0")
        XCTAssertNil(v.build)
        XCTAssertNil(v.profile)
    }
}
