import Combine
import UIKit
import XCTest
import zlib
@testable import JamReader

@MainActor
final class ReaderVerticalRailPreviewTests: XCTestCase {
    func testLocalDirectoryFillsWholeRailWithoutCachingFullPages() async throws {
        let root = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            ReaderPagePreviewStore.shared.clear()
        }
        let image = makeImage()
        let data = try XCTUnwrap(image.pngData())
        for index in 0..<20 {
            try data.write(to: root.appendingPathComponent("\(index).png"))
        }
        let document = try DirectoryImageSequenceReader().loadDocument(at: root)
        let namespace = ReaderPageCache.namespace(for: root)
        ReaderPagePreviewStore.shared.store(image, namespace: namespace, pageIndex: 0)
        try FileManager.default.removeItem(at: root.appendingPathComponent(document.pageNames[0]))

        let coordinator = ReaderVerticalRailPreviewCoordinator()
        defer { coordinator.reset() }
        coordinator.configure(namespace: namespace, pageSource: document.pageSource, pageCount: 20, maxPixelSize: 36)
        await waitUntil { coordinator.railPreviewImages.count == 20 }
        XCTAssertEqual(Set(coordinator.railPreviewImages.keys), Set(0..<20))

        for thumbnail in coordinator.railPreviewImages.values {
            XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale, 36)
        }
        let fullPageCache = await ReaderPageCache.shared.data(for: ReaderPageCacheKey(
            namespace: namespace,
            pageIdentifier: document.pageNames[19]
        ))
        XCTAssertNil(fullPageCache)
        XCTAssertNil(ReaderPagePreviewStore.shared.image(namespace: namespace, pageIndex: 19))
    }

    func testRemoteLocalReadsUsePageCacheAndCompletedDownloadWithoutNetwork() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pageData = try XCTUnwrap(makeImage().pngData())
        let archive = makeZIP(pages: [pageData, pageData])
        let url = root.appendingPathComponent("download.cbz")
        let reader = CountingArchiveReader(data: archive)
        let document = try await RemoteZIPArchiveReader().loadDocument(from: reader, documentURL: url)
        let initialReadCount = reader.readCount
        let missing = try await document.pageSource.localDataForPage(at: 1)
        XCTAssertNil(missing)
        XCTAssertEqual(reader.readCount, initialReadCount)

        let loaded = try await document.pageSource.dataForPage(at: 0)
        XCTAssertEqual(loaded, pageData)
        await ReaderPageCache.shared.clearMemoryCache()
        let reopened = try await RemoteZIPArchiveReader().loadDocument(from: reader, documentURL: url)
        let cachedReadCount = reader.readCount
        let cached = try await reopened.pageSource.localDataForPage(at: 0)
        XCTAssertEqual(cached, pageData)
        XCTAssertEqual(reader.readCount, cachedReadCount)

        // A streaming source still uses its local file after the background download completes.
        try archive.write(to: url, options: .atomic)
        let downloaded = try await reopened.pageSource.localDataForPage(at: 1)
        let downloadedPage = try await reopened.pageSource.dataForPage(at: 1)
        let invalid = try await reopened.pageSource.localDataForPage(at: 2)
        XCTAssertEqual(downloaded, pageData)
        XCTAssertEqual(downloadedPage, pageData)
        XCTAssertNil(invalid)
        XCTAssertEqual(reader.readCount, cachedReadCount)

        let localZIP = try ZIPArchiveReader().loadDocument(at: url)
        let localLibArchive = try LibArchiveReader().loadDocument(at: url)
        for source in [localZIP.pageSource, localLibArchive.pageSource] {
            let local = try await source.localDataForPage(at: 1)
            XCTAssertEqual(local, pageData)
        }
        await document.pageSource.close()
        await reopened.pageSource.close()
    }

    func testResetRejectsLateScanResultAndNeverStartsNormalPageLoad() async throws {
        let source = SuspendedLocalPageSource()
        let coordinator = ReaderVerticalRailPreviewCoordinator()
        coordinator.configure(namespace: UUID().uuidString, pageSource: source, pageCount: 20, maxPixelSize: 36)
        await waitUntil { await source.localReadCount == 1 }
        coordinator.reset()

        let lateUpdate = expectation(description: "Cancelled scan must not repopulate the rail")
        lateUpdate.isInverted = true
        let subscription = coordinator.$railPreviewImages.sink {
            if !$0.isEmpty { lateUpdate.fulfill() }
        }
        await source.complete(try XCTUnwrap(makeImage().pngData()))
        await fulfillment(of: [lateUpdate], timeout: 0.2)
        subscription.cancel()
        let localReadCount = await source.localReadCount
        let normalReadCount = await source.normalReadCount
        XCTAssertEqual(localReadCount, 1)
        XCTAssertEqual(normalReadCount, 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                return XCTFail("Preview scan did not reach the expected state")
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeZIP(pages: [Data]) -> Data {
        var result = Data()
        var directory = Data()
        for (index, page) in pages.enumerated() {
            let name = Data("\(index).png".utf8)
            let checksum = page.withUnsafeBytes {
                UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(page.count)))
            }
            var local = Data(repeating: 0, count: 30)
            put(0x04034b50, in: &local, at: 0)
            put(20, in: &local, at: 4, bytes: 2)
            put(checksum, in: &local, at: 14)
            put(UInt32(page.count), in: &local, at: 18)
            put(UInt32(page.count), in: &local, at: 22)
            put(UInt32(name.count), in: &local, at: 26, bytes: 2)
            var central = Data(repeating: 0, count: 46)
            put(0x02014b50, in: &central, at: 0)
            put(20, in: &central, at: 4, bytes: 2)
            put(20, in: &central, at: 6, bytes: 2)
            put(checksum, in: &central, at: 16)
            put(UInt32(page.count), in: &central, at: 20)
            put(UInt32(page.count), in: &central, at: 24)
            put(UInt32(name.count), in: &central, at: 28, bytes: 2)
            put(UInt32(result.count), in: &central, at: 42)
            result.append(local + name + page)
            directory.append(central + name)
        }
        var end = Data(repeating: 0, count: 22)
        put(0x06054b50, in: &end, at: 0)
        put(UInt32(pages.count), in: &end, at: 8, bytes: 2)
        put(UInt32(pages.count), in: &end, at: 10, bytes: 2)
        put(UInt32(directory.count), in: &end, at: 12)
        put(UInt32(result.count), in: &end, at: 16)
        return result + directory + end
    }

    private func put(_ value: UInt32, in data: inout Data, at offset: Int, bytes: Int = 4) {
        for index in 0..<bytes {
            data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
        }
    }
}

private final class CountingArchiveReader: RemoteRandomAccessFileReader {
    let data: Data
    private(set) var readCount = 0

    init(data: Data) { self.data = data }
    var fileSize: UInt64 { get async throws { UInt64(data.count) } }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        readCount += 1
        return data.subdata(in: Int(offset)..<(Int(offset) + Int(length)))
    }
    func close() async throws {}
}

private actor SuspendedLocalPageSource: ComicPageDataSource {
    private(set) var localReadCount = 0
    private(set) var normalReadCount = 0
    private var continuation: CheckedContinuation<Data?, Never>?

    func dataForPage(at index: Int) async throws -> Data {
        normalReadCount += 1
        return Data()
    }

    func localDataForPage(at index: Int) async throws -> Data? {
        localReadCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func complete(_ data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
