import XCTest
@testable import JamReader

final class RemoteComicCacheModelsTests: XCTestCase {
    func testCacheSummaryClampsNegativeByteCounts() {
        let summary = RemoteComicCacheSummary(
            fileCount: 2,
            totalBytes: -10,
            cachedComicBytes: -20,
            otherCacheBytes: -30
        )

        XCTAssertEqual(summary.totalBytes, 0)
        XCTAssertEqual(summary.cachedComicBytes, 0)
        XCTAssertEqual(summary.otherCacheBytes, 0)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertFalse(summary.hasCachedComics)
        XCTAssertFalse(summary.hasOtherCacheData)
    }

    func testCacheSummaryUsesTotalBytesAsDefaultComicBytes() {
        let summary = RemoteComicCacheSummary(fileCount: 1, totalBytes: 4096)

        XCTAssertEqual(summary.cachedComicBytes, 4096)
        XCTAssertEqual(summary.otherCacheBytes, 0)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.hasCachedComics)
        XCTAssertFalse(summary.hasOtherCacheData)
    }

    func testCacheSummarySupportsLegacyAuxiliaryBytesParameter() {
        let summary = RemoteComicCacheSummary(
            fileCount: 0,
            totalBytes: 2048,
            cachedComicBytes: 0,
            auxiliaryBytes: 512
        )

        XCTAssertEqual(summary.otherCacheBytes, 512)
        XCTAssertFalse(summary.hasCachedComics)
        XCTAssertTrue(summary.hasOtherCacheData)
    }

    func testCachedAvailabilityPresentationFlags() {
        XCTAssertFalse(RemoteComicCachedAvailability.unavailable.hasLocalCopy)
        XCTAssertNil(RemoteComicCachedAvailability.unavailable.badgeTitle)

        let current = RemoteComicCachedAvailability(kind: .current)
        XCTAssertTrue(current.hasLocalCopy)
        XCTAssertEqual(current.badgeTitle, "Offline Ready")

        let stale = RemoteComicCachedAvailability(kind: .stale)
        XCTAssertTrue(stale.hasLocalCopy)
        XCTAssertEqual(stale.badgeTitle, "Older Local Copy")
    }

    func testDownloadResultSourceIsHashable() {
        let first = RemoteComicDownloadResult(
            localFileURL: URL(fileURLWithPath: "/tmp/book.cbz"),
            source: .cachedFallback("/legacy/book.cbz")
        )
        let second = RemoteComicDownloadResult(
            localFileURL: URL(fileURLWithPath: "/tmp/book.cbz"),
            source: .cachedFallback("/legacy/book.cbz")
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }
}
