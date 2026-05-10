import Foundation
import XCTest
@testable import HermesDesktop

final class CompactWindowViewModelTests: XCTestCase {
    @MainActor
    func testToggleFlipsCompactState() {
        let vm = CompactWindowViewModel()
        XCTAssertFalse(vm.isCompact)
        XCTAssertFalse(vm.hidesSidebar)
        XCTAssertFalse(vm.hidesInspector)

        vm.toggle()
        XCTAssertTrue(vm.isCompact)
        XCTAssertTrue(vm.hidesSidebar)
        XCTAssertTrue(vm.hidesInspector)

        vm.toggle()
        XCTAssertFalse(vm.isCompact)
    }

    @MainActor
    func testEnterAndExitAreIdempotent() {
        let vm = CompactWindowViewModel()
        vm.enter()
        vm.enter()
        XCTAssertTrue(vm.isCompact)

        vm.exit()
        vm.exit()
        XCTAssertFalse(vm.isCompact)
    }

    @MainActor
    func testMinSizeShrinksWhenCompact() {
        let vm = CompactWindowViewModel()
        XCTAssertEqual(vm.minSize, CompactWindowViewModel.standardMinSize)
        vm.enter()
        XCTAssertEqual(vm.minSize, CompactWindowViewModel.compactMinSize)
    }

    @MainActor
    func testAdjustForWidthEntersAndExitsCompactBasedOnBreakpoint() {
        let vm = CompactWindowViewModel()
        // Wide window — should remain standard.
        vm.adjust(forWidth: 1280)
        XCTAssertFalse(vm.isCompact)

        // Below the breakpoint — should enter compact.
        vm.adjust(forWidth: 480)
        XCTAssertTrue(vm.isCompact)

        // Resized back to wide — should exit compact.
        vm.adjust(forWidth: 1100)
        XCTAssertFalse(vm.isCompact)
    }
}
