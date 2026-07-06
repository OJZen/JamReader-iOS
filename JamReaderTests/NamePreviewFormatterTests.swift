import XCTest
@testable import JamReader

final class NamePreviewFormatterTests: XCTestCase {
    func testPreviewSortsAndDeduplicatesNames() {
        XCTAssertEqual(
            NamePreviewFormatter.preview(from: ["z.cbz", "a.cbz", "z.cbz", "b.cbz"]),
            "a.cbz, b.cbz, z.cbz"
        )
    }

    func testPreviewSummarizesNamesBeyondLimit() {
        XCTAssertEqual(
            NamePreviewFormatter.preview(from: ["d.cbz", "b.cbz", "a.cbz", "c.cbz"]),
            "a.cbz, b.cbz, c.cbz, +1 more"
        )
    }

    func testPreviewSupportsCustomLimit() {
        XCTAssertEqual(
            NamePreviewFormatter.preview(from: ["3.cbz", "1.cbz", "2.cbz"], limit: 2),
            "1.cbz, 2.cbz, +1 more"
        )
    }

    func testPreviewReturnsEmptyStringForEmptyInput() {
        XCTAssertEqual(NamePreviewFormatter.preview(from: []), "")
    }
}
