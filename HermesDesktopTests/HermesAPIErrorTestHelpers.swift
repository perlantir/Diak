import XCTest
@testable import HermesDesktop

func XCTAssertInvalidRequest(_ error: HermesAPIError,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
    guard case .invalidRequest(let reason) = error else {
        XCTFail("Expected invalidRequest, got \(error)", file: file, line: line)
        return
    }
    XCTAssertFalse(reason.isEmpty, file: file, line: line)
}
