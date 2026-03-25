import CoreGraphics
import Foundation
import UIKit

enum RemotePDFThumbnailExtractionError: Error {
    case invalidDocument
    case invalidPageGeometry
    case truncatedRead
}

struct RemotePDFThumbnailExtractor {
    let fileReader: any RemoteRandomAccessFileReader

    func extractThumbnail(maxPixelSize: Int) async throws -> UIImage {
        let fileSize = try await fileReader.fileSize
        let dataSource = RemotePDFRandomAccessDataSource(
            fileReader: fileReader,
            fileSize: fileSize
        )

        guard let provider = dataSource.makeDataProvider(),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            throw RemotePDFThumbnailExtractionError.invalidDocument
        }

        return try renderThumbnail(for: page, maxPixelSize: maxPixelSize)
    }

    private func renderThumbnail(for page: CGPDFPage, maxPixelSize: Int) throws -> UIImage {
        let pageBounds = page.getBoxRect(.mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            throw RemotePDFThumbnailExtractionError.invalidPageGeometry
        }

        let targetSize = scaledTargetSize(for: pageBounds.size, maxPixelSize: maxPixelSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            let canvas = CGRect(origin: .zero, size: targetSize)
            UIColor.white.setFill()
            context.fill(canvas)

            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.concatenate(
                page.getDrawingTransform(
                    .mediaBox,
                    rect: canvas,
                    rotate: 0,
                    preserveAspectRatio: true
                )
            )
            cgContext.drawPDFPage(page)
            cgContext.restoreGState()
        }
    }

    private func scaledTargetSize(for sourceSize: CGSize, maxPixelSize: Int) -> CGSize {
        let largestDimension = max(sourceSize.width, sourceSize.height)
        guard largestDimension > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let maximumDimension = CGFloat(max(maxPixelSize, 1))
        let scaleRatio = min(1, maximumDimension / largestDimension)

        return CGSize(
            width: max(1, floor(sourceSize.width * scaleRatio)),
            height: max(1, floor(sourceSize.height * scaleRatio))
        )
    }
}

private final class RemotePDFRandomAccessDataSource {
    private let readerProxy: RemotePDFFileReaderProxy
    private let fileSize: UInt64
    private let blockCache = RemotePDFBlockCache()
    private let blockSize = 128 * 1_024

    init(fileReader: any RemoteRandomAccessFileReader, fileSize: UInt64) {
        self.readerProxy = RemotePDFFileReaderProxy(fileReader: fileReader)
        self.fileSize = fileSize
    }

    func makeDataProvider() -> CGDataProvider? {
        guard fileSize <= UInt64(Int.max) else {
            return nil
        }

        let retainedSelf = Unmanaged.passRetained(self)
        var callbacks = Self.directCallbacks
        guard let provider = CGDataProvider(
            directInfo: retainedSelf.toOpaque(),
            size: off_t(fileSize),
            callbacks: &callbacks
        ) else {
            retainedSelf.release()
            return nil
        }

        return provider
    }

    private func readBytes(
        into buffer: UnsafeMutableRawPointer,
        offset: UInt64,
        count: Int
    ) -> Int {
        guard count > 0, offset < fileSize else {
            return 0
        }

        let readableByteCount = Int(min(UInt64(count), fileSize - offset))
        guard readableByteCount > 0 else {
            return 0
        }

        var remainingBytes = readableByteCount
        var currentOffset = offset
        var writtenBytes = 0

        while remainingBytes > 0 {
            let blockOffset = alignedBlockOffset(for: currentOffset)
            guard let block = try? blockData(at: blockOffset) else {
                break
            }

            let blockRelativeOffset = Int(currentOffset - blockOffset)
            guard blockRelativeOffset < block.count else {
                break
            }

            let chunkLength = min(remainingBytes, block.count - blockRelativeOffset)
            block.withUnsafeBytes { bytes in
                guard let sourceBaseAddress = bytes.baseAddress else {
                    return
                }

                let sourcePointer = sourceBaseAddress.advanced(by: blockRelativeOffset)
                let destinationPointer = buffer.advanced(by: writtenBytes)
                destinationPointer.copyMemory(from: sourcePointer, byteCount: chunkLength)
            }

            remainingBytes -= chunkLength
            writtenBytes += chunkLength
            currentOffset += UInt64(chunkLength)
        }

        return writtenBytes
    }

    private func alignedBlockOffset(for offset: UInt64) -> UInt64 {
        (offset / UInt64(blockSize)) * UInt64(blockSize)
    }

    private func blockData(at blockOffset: UInt64) throws -> Data {
        if let cachedBlock = blockCache.block(at: blockOffset) {
            return cachedBlock
        }

        let remainingBytes = fileSize - blockOffset
        let requestedByteCount = Int(min(UInt64(blockSize), remainingBytes))
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = RemotePDFReadResultBox()

        Task.detached(priority: .utility) { [readerProxy] in
            defer {
                semaphore.signal()
            }

            do {
                let data = try await readerProxy.fileReader.read(
                    offset: blockOffset,
                    length: UInt32(requestedByteCount)
                )
                resultBox.result = .success(data)
            } catch {
                resultBox.result = .failure(error)
            }
        }

        semaphore.wait()
        let blockData = try resultBox.result?.get() ?? {
            throw RemotePDFThumbnailExtractionError.truncatedRead
        }()
        blockCache.store(blockData, at: blockOffset)
        return blockData
    }

    private static var directCallbacks: CGDataProviderDirectCallbacks {
        CGDataProviderDirectCallbacks(
            version: 0,
            getBytePointer: { _ in nil },
            releaseBytePointer: { _, _ in },
            getBytesAtPosition: { info, buffer, offset, count in
                guard let info else {
                    return 0
                }

                let dataSource = Unmanaged<RemotePDFRandomAccessDataSource>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                return dataSource.readBytes(
                    into: buffer,
                    offset: UInt64(offset),
                    count: count
                )
            },
            releaseInfo: { info in
                guard let info else {
                    return
                }

                Unmanaged<RemotePDFRandomAccessDataSource>
                    .fromOpaque(info)
                    .release()
            }
        )
    }
}

private final class RemotePDFBlockCache {
    private let lock = NSLock()
    private var blocksByOffset: [UInt64: Data] = [:]
    private var lruOffsets: [UInt64] = []
    private let maximumBlockCount = 48

    func block(at offset: UInt64) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard let block = blocksByOffset[offset] else {
            return nil
        }

        touch(offset)
        return block
    }

    func store(_ block: Data, at offset: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        blocksByOffset[offset] = block
        touch(offset)

        while lruOffsets.count > maximumBlockCount, let oldestOffset = lruOffsets.first {
            lruOffsets.removeFirst()
            blocksByOffset.removeValue(forKey: oldestOffset)
        }
    }

    private func touch(_ offset: UInt64) {
        lruOffsets.removeAll { $0 == offset }
        lruOffsets.append(offset)
    }
}

private final class RemotePDFFileReaderProxy: @unchecked Sendable {
    let fileReader: any RemoteRandomAccessFileReader

    init(fileReader: any RemoteRandomAccessFileReader) {
        self.fileReader = fileReader
    }
}

private final class RemotePDFReadResultBox: @unchecked Sendable {
    nonisolated(unsafe) var result: Result<Data, Error>?
}
