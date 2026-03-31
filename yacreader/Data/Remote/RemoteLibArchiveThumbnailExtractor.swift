import Foundation
import UIKit

enum RemoteLibArchiveThumbnailExtractionError: Error {
    case invalidArchive
    case noRenderablePages
    case unreadableImage
}

struct RemoteLibArchiveThumbnailExtractor {
    let fileReader: any RemoteRandomAccessFileReader

    func extractThumbnail(maxPixelSize: Int) async throws -> UIImage {
        let fileSize = try await fileReader.fileSize
        let dataSource = RemoteLibArchiveDataSource(
            fileReader: fileReader,
            fileSize: fileSize
        )
        let archiveReader = try YRLibArchiveReader(dataSource: dataSource)
        let orderedEntries = try orderedPageEntries(from: archiveReader.entryPaths)

        guard let firstEntry = orderedEntries.first else {
            throw RemoteLibArchiveThumbnailExtractionError.noRenderablePages
        }

        let imageData = try archiveReader.dataForEntry(at: firstEntry.archiveIndex)
        guard let image = UIImage(data: imageData) else {
            throw RemoteLibArchiveThumbnailExtractionError.unreadableImage
        }

        return downsampledImage(from: image, maxPixelSize: maxPixelSize)
    }

    private func orderedPageEntries(from entryPaths: [String]) throws -> [RemoteLibArchiveEntry] {
        let pageEntries = entryPaths.enumerated().compactMap { archiveIndex, path -> RemoteLibArchiveEntry? in
            guard ComicPageNameSorter.isSupportedImagePath(path) else {
                return nil
            }

            return RemoteLibArchiveEntry(path: path, archiveIndex: archiveIndex)
        }

        guard !pageEntries.isEmpty else {
            throw RemoteLibArchiveThumbnailExtractionError.noRenderablePages
        }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        var entriesByPath = Dictionary(grouping: pageEntries, by: \.path)
        var orderedEntries: [RemoteLibArchiveEntry] = []
        orderedEntries.reserveCapacity(pageEntries.count)

        for path in sortedPaths {
            guard var candidates = entriesByPath[path], let entry = candidates.first else {
                continue
            }

            candidates.removeFirst()
            entriesByPath[path] = candidates
            orderedEntries.append(entry)
        }

        return orderedEntries
    }

    private func downsampledImage(from image: UIImage, maxPixelSize: Int) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let largestDimension = max(pixelWidth, pixelHeight)

        guard largestDimension > CGFloat(maxPixelSize), largestDimension > 0 else {
            return image
        }

        let scaleRatio = CGFloat(maxPixelSize) / largestDimension
        let targetSize = CGSize(
            width: max(1, image.size.width * scaleRatio),
            height: max(1, image.size.height * scaleRatio)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct RemoteLibArchiveEntry {
    let path: String
    let archiveIndex: Int
}

@objcMembers
private final class RemoteLibArchiveDataSource: NSObject, YRLibArchiveDataSource {
    let archiveSize: Int64

    private let readerProxy: RemoteLibArchiveFileReaderProxy
    private let blockCache = RemoteLibArchiveBlockCache()
    private let blockSize = 128 * 1_024

    init(fileReader: any RemoteRandomAccessFileReader, fileSize: UInt64) {
        self.readerProxy = RemoteLibArchiveFileReaderProxy(fileReader: fileReader)
        self.archiveSize = Int64(clamping: fileSize)
        super.init()
    }

    func readData(atOffset offset: Int64, length: UInt) throws -> Data {
        let requestedLength = Int(length)

        guard requestedLength > 0, offset >= 0, offset < archiveSize else {
            return Data()
        }

        let readableByteCount = Int(min(Int64(requestedLength), archiveSize - offset))
        guard readableByteCount > 0 else {
            return Data()
        }

        var data = Data(count: readableByteCount)
        var remainingBytes = readableByteCount
        var currentOffset = UInt64(offset)
        var writtenBytes = 0

        while remainingBytes > 0 {
            let blockOffset = alignedBlockOffset(for: currentOffset)
            let block = try blockData(at: blockOffset)
            let blockRelativeOffset = Int(currentOffset - blockOffset)
            guard blockRelativeOffset >= 0, blockRelativeOffset < block.count else {
                break
            }
            let chunkLength = min(remainingBytes, block.count - blockRelativeOffset)

            block.withUnsafeBytes { sourceBuffer in
                data.withUnsafeMutableBytes { destinationBuffer in
                    guard let sourceBaseAddress = sourceBuffer.baseAddress,
                          let destinationBaseAddress = destinationBuffer.baseAddress else {
                        return
                    }

                    let sourcePointer = sourceBaseAddress.advanced(by: blockRelativeOffset)
                    let destinationPointer = destinationBaseAddress.advanced(by: writtenBytes)
                    destinationPointer.copyMemory(from: sourcePointer, byteCount: chunkLength)
                }
            }

            remainingBytes -= chunkLength
            writtenBytes += chunkLength
            currentOffset += UInt64(chunkLength)
        }

        return data
    }

    private func alignedBlockOffset(for offset: UInt64) -> UInt64 {
        (offset / UInt64(blockSize)) * UInt64(blockSize)
    }

    private func blockData(at blockOffset: UInt64) throws -> Data {
        if let cachedBlock = blockCache.block(at: blockOffset) {
            return cachedBlock
        }

        let remainingBytes = UInt64(max(0, archiveSize)) - blockOffset
        let requestedByteCount = Int(min(UInt64(blockSize), remainingBytes))
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = RemoteLibArchiveReadResultBox()

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

        let waitResult = semaphore.wait(timeout: .now() + 30)
        guard waitResult == .success else {
            throw RemoteLibArchiveThumbnailExtractionError.invalidArchive
        }
        let data = try resultBox.result?.get() ?? {
            throw RemoteLibArchiveThumbnailExtractionError.invalidArchive
        }()
        blockCache.store(data, at: blockOffset)
        return data
    }
}

private final class RemoteLibArchiveBlockCache {
    private let lock = NSLock()
    private var blocksByOffset: [UInt64: Data] = [:]
    private var lruOffsets: [UInt64] = []
    private let maximumBlockCount = 64

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

private final class RemoteLibArchiveFileReaderProxy: @unchecked Sendable {
    let fileReader: any RemoteRandomAccessFileReader

    init(fileReader: any RemoteRandomAccessFileReader) {
        self.fileReader = fileReader
    }
}

private final class RemoteLibArchiveReadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<Data, Error>?

    var result: Result<Data, Error>? {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
}
