import XCTest
@testable import HermesDesktop

final class DeepLinkParserTests: XCTestCase {
    func testParseReturnsNilForRegisteredSchemePlaceholder() {
        let url = URL(string: "diak://test")!
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func testParseReturnsNilForOAuthLikeCallbackUntilPhaseFour() {
        let url = URL(string: "diak://oauth/callback?code=abc&state=xyz")!
        XCTAssertNil(DeepLinkParser.parse(url))
    }

    func testParseReturnsNilForNonDiakURL() {
        let url = URL(string: "https://example.com/path")!
        XCTAssertNil(DeepLinkParser.parse(url))
    }
}
