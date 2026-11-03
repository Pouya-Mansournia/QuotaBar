import XCTest
@testable import QuotaBar

final class ReleaseUpdaterTests: XCTestCase {
    func testReleaseTagVersion() {
        XCTAssertEqual(ReleaseUpdater.version(from: "Windows-v1.0.3"), "1.0.3")
        XCTAssertEqual(ReleaseUpdater.version(from: "v1.2.0"), "1.2.0")
        XCTAssertNil(ReleaseUpdater.version(from: "Windows-v1.2"))
        XCTAssertNil(ReleaseUpdater.version(from: "other"))
    }
}
