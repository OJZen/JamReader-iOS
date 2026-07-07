import XCTest
@testable import JamReader

final class AppLogSanitizerTests: XCTestCase {
    func testTruncatedLimitsLongTextAndReportsOriginalLength() {
        let value = String(repeating: "a", count: 12)

        XCTAssertEqual(
            AppLogSanitizer.truncated(value, limit: 5),
            "aaaaa...(truncated, 12 chars)"
        )
    }

    func testURLRedactsCredentialsQueryAndFragment() throws {
        let url = try XCTUnwrap(
            URL(string: "https://user:secret@example.com/dav/books.cbz?token=abc#page")
        )

        XCTAssertEqual(
            AppLogSanitizer.url(url),
            "https://example.com/dav/books.cbz"
        )
    }

    func testPathPreservesOnlyTrailingComponents() {
        XCTAssertEqual(
            AppLogSanitizer.path("/Volumes/User/Private/Comics/Series/Book.cbz", preservingLastComponents: 3),
            ".../Comics/Series/Book.cbz"
        )
    }

    func testNamesPreviewLimitsItemCount() {
        XCTAssertEqual(
            AppLogSanitizer.namesPreview(["A.cbz", "B.cbz", "C.cbz", "D.cbz"], maxItems: 2),
            "A.cbz, B.cbz, ...(+2 more)"
        )
    }
}
