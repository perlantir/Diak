import XCTest
@testable import HermesDesktop

final class AppBrandTests: XCTestCase {
    func testPublicAppBrandUsesDiak() {
        XCTAssertEqual(AppBrand.appName, "Diak")
        XCTAssertEqual(AppBrand.windowTitle, "Diak")
        XCTAssertEqual(AppBrand.sidebarTitle, "Diak")
        XCTAssertEqual(AppBrand.quickPromptTitle, "Diak Quick Prompt")
        XCTAssertEqual(AppBrand.copyright, "© 2026 Diak")
    }

    func testHermesRemainsEngineBrand() {
        XCTAssertEqual(AppBrand.engineName, "Hermes Agent")
        XCTAssertEqual(AppBrand.engineShortName, "Hermes")
        XCTAssertTrue(AppBrand.onboardingWelcomeSubtitle.contains("Hermes Agent"))
    }

    func testOnboardingCopyIsReleaseReady() {
        XCTAssertEqual(AppBrand.onboardingWelcomeTitle, "Welcome to Diak")
        XCTAssertTrue(AppBrand.onboardingCompletionMessage.contains("Diak is ready"))
        XCTAssertFalse(AppBrand.onboardingCompletionMessage.contains("milestones land"))
    }
}
