import XCTest
@testable import HermesDesktop

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    func testStartsAtWelcome() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.step, .welcome)
        XCTAssertFalse(vm.hasCompleted)
    }

    func testNextWalksThroughAllSteps() {
        let vm = OnboardingViewModel()
        vm.next() // engine
        XCTAssertEqual(vm.step, .engineSetup)
        vm.next() // provider
        XCTAssertEqual(vm.step, .modelProvider)
        vm.next() // safety
        XCTAssertEqual(vm.step, .safetyPermissions)
        vm.next() // complete
        XCTAssertEqual(vm.step, .complete)
        vm.next() // marks completed
        XCTAssertTrue(vm.hasCompleted)
    }

    func testBackFromMiddleStep() {
        let vm = OnboardingViewModel()
        vm.next()
        vm.next()
        XCTAssertEqual(vm.step, .modelProvider)
        vm.back()
        XCTAssertEqual(vm.step, .engineSetup)
    }

    func testSkipImmediatelyCompletes() {
        let vm = OnboardingViewModel()
        vm.skip()
        XCTAssertTrue(vm.hasCompleted)
    }
}
