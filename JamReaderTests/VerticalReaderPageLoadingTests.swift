import UIKit
import XCTest
@testable import JamReader

@MainActor
final class VerticalReaderPageLoadingTests: XCTestCase {
    func testCancelledPrefetchRestartsWhenPreparedCellAppears() async throws {
        let source = ControlledVerticalPageSource()
        defer { Task { await source.close() } }
        let (coordinator, controller) = makeReader(source: source, visible: false)
        let indexPath = IndexPath(item: 0, section: 0)
        let cell = VerticalReaderPageCell(frame: .zero)
        cell.configurePlaceholder(pageNumber: 1)
        cell.setImage(makeImage(width: 24), isPreview: true)

        coordinator.collectionView(controller.collectionView, prefetchItemsAt: [indexPath])
        await waitUntil { await source.requestCount == 1 }
        coordinator.collectionView(controller.collectionView, cancelPrefetchingForItemsAt: [indexPath])
        coordinator.collectionView(controller.collectionView, willDisplay: cell, forItemAt: indexPath)
        await waitUntil { await source.requestCount == 2 }

        // A cancelled request may finish after its replacement has started.
        await source.complete(request: 0, data: try XCTUnwrap(makeImage(width: 24).pngData()))
        await source.complete(request: 1, data: try XCTUnwrap(makeImage(width: 640).pngData()))
        await waitUntil {
            coordinator.collectionView(controller.collectionView, willDisplay: cell, forItemAt: indexPath)
            return cell.hasPageImage
        }

        XCTAssertEqual(displayedImage(in: cell)?.size.width, 640)
        let requestCount = await source.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testMemoryWarningKeepsVisibleLoadAndLatePreviewCannotReplacePage() async throws {
        let source = ControlledVerticalPageSource()
        defer { Task { await source.close() } }
        let (coordinator, controller) = makeReader(source: source, visible: true)
        let cell = try XCTUnwrap(
            controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? VerticalReaderPageCell
        )
        let namespace = ReaderPageCache.namespace(for: coordinator.document.url)
        let previewStore = ReaderPagePreviewStore.shared
        defer { previewStore.clear() }
        await waitUntil { await source.requestCount == 1 }
        previewStore.store(makeImage(width: 24), namespace: namespace, pageIndex: 0)
        XCTAssertFalse(cell.hasPageImage)
        XCTAssertEqual(displayedImage(in: cell)?.size.width, 24)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        await source.complete(request: 0, data: try XCTUnwrap(makeImage(width: 640).pngData()))
        await waitUntil { cell.hasPageImage }
        XCTAssertEqual(displayedImage(in: cell)?.size.width, 640)

        // The cell still owns its page image after both caches have been evicted.
        previewStore.clear()
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        previewStore.store(makeImage(width: 24), namespace: namespace, pageIndex: 0)
        XCTAssertTrue(cell.hasPageImage)
        XCTAssertEqual(displayedImage(in: cell)?.size.width, 640)
    }

    func testPageImageRejectsPreviewUntilCellIsReused() {
        let cell = VerticalReaderPageCell(frame: .zero)
        cell.setImage(makeImage(width: 640))
        cell.setImage(makeImage(width: 24), isPreview: true)
        XCTAssertEqual(displayedImage(in: cell)?.size.width, 640)

        cell.prepareForReuse()
        cell.configurePlaceholder(pageNumber: 2)
        cell.setImage(makeImage(width: 24), isPreview: true)
        XCTAssertFalse(cell.hasPageImage)
        XCTAssertEqual(displayedImage(in: cell)?.size.width, 24)
    }

    private func makeReader(
        source: ControlledVerticalPageSource,
        visible: Bool
    ) -> (VerticalImageSequenceReaderContainerView.Coordinator, VerticalReaderViewController) {
        let document = ImageSequenceComicDocument(
            url: URL(fileURLWithPath: "/vertical-reader-test-\(UUID().uuidString).cbz"),
            pageNames: ["page.png"],
            pageSource: source
        )
        let coordinator = VerticalImageSequenceReaderContainerView.Coordinator(
            document: document,
            layout: ReaderDisplayLayout(pagingMode: .verticalContinuous),
            currentPageIndex: 0,
            onPageChanged: { _ in },
            onReaderTap: { _ in },
            onZoomStateChanged: nil
        )
        let controller = VerticalReaderViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = visible ? CGRect(x: 0, y: 0, width: 390, height: 600) : .zero
        coordinator.attach(to: controller)
        if visible {
            controller.view.layoutIfNeeded()
            controller.collectionView.layoutIfNeeded()
        }
        return (coordinator, controller)
    }

    private func makeImage(width: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: width * 1.5), format: format).image {
            UIColor.white.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: width * 1.5))
        }
    }

    private func displayedImage(in cell: VerticalReaderPageCell) -> UIImage? {
        cell.contentView.subviews.compactMap { $0 as? UIImageView }.first?.image
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Reader did not reach the expected loading state", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ControlledVerticalPageSource: ComicPageDataSource {
    private(set) var requestCount = 0
    private var requests: [Int: CheckedContinuation<Data, Error>] = [:]

    func dataForPage(at index: Int) async throws -> Data {
        let request = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { requests[request] = $0 }
    }

    func complete(request: Int, data: Data) {
        requests.removeValue(forKey: request)?.resume(returning: data)
    }

    func close() async {
        for continuation in requests.values {
            continuation.resume(throwing: CancellationError())
        }
        requests.removeAll()
    }
}
