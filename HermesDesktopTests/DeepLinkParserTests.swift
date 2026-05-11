import XCTest
@testable import HermesDesktop

final class DeepLinkParserTests: XCTestCase {
    func testParseReturnsUnknownForRegisteredSchemePlaceholder() {
        let url = URL(string: "diak://test")!
        // Phase 0 chooses `.unknown` rather than nil for recognized-but-unparsed
        // URLs so Phase 4 can fill parsing cases without changing call sites.
        XCTAssertEqual(DeepLinkParser.parse(url), .unknown(url))
    }

    func testParseReturnsUnknownForOAuthLikeCallbackUntilPhaseFour() {
        let url = URL(string: "diak://oauth/callback?code=abc&state=xyz")!
        XCTAssertEqual(DeepLinkParser.parse(url), .unknown(url))
    }

    func testParseReturnsUnknownForNonDiakURL() {
        let url = URL(string: "https://example.com/path")!
        XCTAssertEqual(DeepLinkParser.parse(url), .unknown(url))
    }
}
