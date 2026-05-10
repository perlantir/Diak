import Foundation
import XCTest
@testable import HermesDesktop

final class HermesMemoryDecodingTests: XCTestCase {
    func testMemoryItemDecodesSnakeCaseAndUnknownEnumCases() throws {
        let data = Data("""
        {
          "id": "mem-mystery",
          "title": "Mystery",
          "body": "A note from a future daemon.",
          "scope": "interdimensional",
          "source": "telekinesis",
          "confidence": "vibes",
          "tags": ["weird", "future"],
          "session_id": "sess-x",
          "created_at": "2026-05-09T22:00:00Z",
          "updated_at": "2026-05-09T22:30:14Z",
          "is_pinned": true
        }
        """.utf8)

        let item = try JSONDecoder().decode(HermesMemoryItem.self, from: data)

        XCTAssertEqual(item.scope, .unknown)
        XCTAssertEqual(item.source, .unknown)
        XCTAssertEqual(item.confidence, .unknown)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.tags, ["weird", "future"])
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotNil(item.updatedAt)
    }

    func testDashboardDecodesSnakeCaseCounts() throws {
        let data = Data("""
        {
          "items": [
            {
              "id": "mem-1",
              "title": "User role",
              "body": "Senior eng",
              "scope": "user",
              "source": "manual",
              "confidence": "high",
              "is_pinned": true
            }
          ],
          "boundary_note": "Daemon-owned indexing.",
          "pinned_count": 1,
          "total_count": 1
        }
        """.utf8)

        let dashboard = try JSONDecoder().decode(HermesMemoryDashboard.self, from: data)
        XCTAssertEqual(dashboard.items.count, 1)
        XCTAssertEqual(dashboard.pinnedCount, 1)
        XCTAssertEqual(dashboard.totalCount, 1)
        XCTAssertEqual(dashboard.boundaryNote, "Daemon-owned indexing.")
    }

    func testMemoryUpdateRejectsEmpty() {
        let empty = HermesMemoryUpdate(id: "mem-1", acknowledgedReview: true)
        XCTAssertTrue(empty.isEmpty)

        let withScope = HermesMemoryUpdate(id: "mem-1", scope: .project, acknowledgedReview: true)
        XCTAssertFalse(withScope.isEmpty)
    }

    func testRoundTripPreservesScopeAndPinned() throws {
        let item = HermesMemoryItem(
            id: "mem-1",
            title: "Project policy",
            body: "Do not commit derived data.",
            scope: .project,
            source: .manual,
            confidence: .high,
            tags: ["policy"],
            projectRef: HermesProjectRef(id: "proj-x", name: "Project X"),
            sessionID: nil,
            createdAt: Date(timeIntervalSince1970: 1_778_716_800),
            updatedAt: Date(timeIntervalSince1970: 1_778_716_900),
            isPinned: true
        )

        let data = try JSONEncoder().encode(item)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["is_pinned"] as? Bool, true)
        XCTAssertEqual(object["scope"] as? String, "project")
        XCTAssertEqual(object["source"] as? String, "manual")
        let projectRef = try XCTUnwrap(object["project_ref"] as? [String: Any])
        XCTAssertEqual(projectRef["id"] as? String, "proj-x")

        let decoded = try JSONDecoder().decode(HermesMemoryItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    func testSupportsDeleteMatchesSourcePolicy() {
        let manual = HermesMemoryItem(
            id: "m1", title: "x", body: "y",
            scope: .user, source: .manual, confidence: .high
        )
        let imported = HermesMemoryItem(
            id: "m2", title: "x", body: "y",
            scope: .global, source: .importedReference, confidence: .high
        )
        XCTAssertTrue(manual.supportsDelete)
        XCTAssertFalse(imported.supportsDelete,
                       "Imported references must not be deletable from the desktop boundary.")
    }
}
