import Foundation
import XCTest
@testable import HermesDesktop

final class HermesSkillDecodingTests: XCTestCase {
    func testSkillDecodesSnakeCaseAndUnknownEnumCases() throws {
        let data = Data("""
        {
          "id": "skill-mystery",
          "name": "Wormhole skill",
          "summary": "An unrecognised category from a future daemon.",
          "status": "vibing",
          "category": "necromancy",
          "source": "spectral",
          "risk_style": "untyped",
          "version": "9.9.9",
          "trigger_summary": "When the user mentions wormholes.",
          "usage_notes": "Daemon-only.",
          "artifacts": [
            { "id": "art-mystery", "kind": "ouija_board", "title": "Mystery artifact" }
          ],
          "is_enabled": true,
          "source_session_id": "sess-mystery",
          "updated_at": "2026-05-09T22:30:14Z",
          "installed_by": "Daemon"
        }
        """.utf8)

        let skill = try JSONDecoder().decode(HermesSkill.self, from: data)

        XCTAssertEqual(skill.status, .unknown, "Unknown statuses must decode to .unknown.")
        XCTAssertEqual(skill.category, .unknown)
        XCTAssertEqual(skill.source, .unknown)
        XCTAssertEqual(skill.riskStyle, .unknown)
        XCTAssertEqual(skill.artifacts.first?.kind, .unknown)
        XCTAssertTrue(skill.isEnabled)
        XCTAssertEqual(skill.sourceSessionID, "sess-mystery")
        XCTAssertNotNil(skill.updatedAt)
    }

    func testSkillCatalogDecodesSnakeCaseBoundaryNote() throws {
        let data = Data("""
        {
          "skills": [
            {
              "id": "skill-x",
              "name": "PR review",
              "summary": "Reviews PRs",
              "status": "active",
              "category": "coding",
              "source": "built_in",
              "risk_style": "safe",
              "version": "1.0.0",
              "trigger_summary": "On PR url",
              "is_enabled": true
            }
          ],
          "boundary_note": "Daemon-owned execution."
        }
        """.utf8)

        let catalog = try JSONDecoder().decode(HermesSkillCatalog.self, from: data)
        XCTAssertEqual(catalog.skills.count, 1)
        XCTAssertEqual(catalog.skills.first?.category, .coding)
        XCTAssertEqual(catalog.skills.first?.source, .builtIn)
        XCTAssertEqual(catalog.skills.first?.riskStyle, .safe)
        XCTAssertEqual(catalog.boundaryNote, "Daemon-owned execution.")
    }

    func testDraftReviewDecodesSnakeCaseAndUnknownReadiness() throws {
        let data = Data("""
        {
          "session_id": "sess-x",
          "suggested_name": "Skill",
          "suggested_summary": "Summary",
          "suggested_trigger_summary": "Trigger",
          "suggested_category": "writing",
          "suggested_risk_style": "requires_approval",
          "safety_highlights": ["Reads only"],
          "readiness": "stargate_alignment",
          "message": "Realigning."
        }
        """.utf8)

        let review = try JSONDecoder().decode(HermesSkillDraftReview.self, from: data)
        XCTAssertEqual(review.readiness, .unknown,
                       "Unknown readiness must decode to .unknown so the sheet still renders.")
        XCTAssertEqual(review.suggestedCategory, .writing)
        XCTAssertEqual(review.suggestedRiskStyle, .requiresApproval)
        XCTAssertEqual(review.safetyHighlights.count, 1)
    }

    func testRoundTripPreservesArtifactsAndCategory() throws {
        let skill = HermesSkill(
            id: "skill-x",
            name: "PR review",
            summary: "Reviews PRs",
            status: .active,
            category: .coding,
            source: .builtIn,
            riskStyle: .safe,
            version: "1.0.0",
            triggerSummary: "On PR url",
            usageNotes: "Read-only",
            artifacts: [
                HermesSkillArtifact(id: "art-1", kind: .promptTemplate, title: "Prompt")
            ],
            isEnabled: true
        )

        let data = try JSONEncoder().encode(skill)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["risk_style"] as? String, "safe")
        XCTAssertEqual(object["trigger_summary"] as? String, "On PR url")
        XCTAssertEqual(object["is_enabled"] as? Bool, true)
        let artifacts = try XCTUnwrap(object["artifacts"] as? [[String: Any]])
        XCTAssertEqual(artifacts.first?["kind"] as? String, "prompt_template")

        let decoded = try JSONDecoder().decode(HermesSkill.self, from: data)
        XCTAssertEqual(decoded, skill)
    }
}
