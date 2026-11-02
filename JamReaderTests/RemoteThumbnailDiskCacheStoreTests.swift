import UIKit
import XCTest
@testable import JamReader

final class RemoteThumbnailDiskCacheStoreTests: XCTestCase {
    private var workspaceURL: URL!

    private var cacheRootURL: URL {
        workspaceURL.appendingPathComponent("Cache", isDirectory: true)
    }

    override func setUpWithError() throws {
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: workspaceURL)
    }

    func testGenerationStaysReadableDuringASlowDiskScan() async {
        let scanStarted = expectation(description: "The summary scan is holding the file lock")
        let fileManager = GatedFileManager(gatedPath: cacheRootURL.path, reached: scanStarted)
        let store = makeStore(fileManager: fileManager)

        let scan = Task.detached { await store.cacheSummaryAsync() }
        await fulfillment(of: [scanStarted], timeout: 5)

        let generationRead = expectation(description: "The generation is available during the scan")
        DispatchQueue.global().async {
            XCTAssertEqual(store.currentGeneration(), 0)
            generationRead.fulfill()
        }
        await fulfillment(of: [generationRead], timeout: 1)

        fileManager.open()
        _ = await scan.value
    }

    func testDecodingACachedImageDoesNotHoldBackStores() async throws {
        // Outside the cache root, so the summary scan after a store never reaches the gate.
        let coverURL = workspaceURL.appendingPathComponent("cover.png")
        let otherURL = cacheRootURL.appendingPathComponent("other.png")
        let cover = try XCTUnwrap(makeCover().pngData())
        try cover.write(to: coverURL)

        let decodeStarted = expectation(description: "The cached image is being read")
        let fileManager = GatedFileManager(gatedPath: coverURL.path, reached: decodeStarted)
        let store = makeStore(fileManager: fileManager)

        let load = Task.detached { await store.loadCachedImageAsync(at: coverURL) }
        await fulfillment(of: [decodeStarted], timeout: 5)

        let stored = expectation(description: "The store finishes during the decode")
        DispatchQueue.global().async {
            try? store.storeEncodedThumbnailData(cover, at: otherURL, generation: 0)
            stored.fulfill()
        }
        await fulfillment(of: [stored], timeout: 1)

        fileManager.open()
        let image = await load.value
        XCTAssertNotNil(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path))
    }

    private func makeStore(fileManager: FileManager) -> RemoteThumbnailDiskCacheStore {
        RemoteThumbnailDiskCacheStore(
            fileManager: fileManager,
            cacheRootURL: cacheRootURL,
            maximumCachedThumbnailCount: 100,
            maximumTotalCacheBytes: 1_024 * 1_024
        )
    }

    private func makeCover() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
    }
}

/// Holds `fileExists` for one path, so a test can pause the store mid-operation.
nonisolated private final class GatedFileManager: FileManager {
    private let gatedPath: String
    private let reached: XCTestExpectation
    private let gate = DispatchGroup()

    init(gatedPath: String, reached: XCTestExpectation) {
        self.gatedPath = gatedPath
        self.reached = reached
        reached.assertForOverFulfill = false
        gate.enter()
        super.init()
    }

    func open() {
        gate.leave()
    }

    override func fileExists(atPath path: String) -> Bool {
        if path == gatedPath {
            reached.fulfill()
            _ = gate.wait(timeout: .now() + 5)
        }
        return super.fileExists(atPath: path)
    }
}
