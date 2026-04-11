import Foundation
import zlib

enum ZIPArchiveError: LocalizedError {
    case unreadableArchive
    case invalidArchive
    case unsupportedZIP64
    case unsupportedMultiDiskArchive
    case noRenderablePages
    case pageIndexOutOfBounds(Int)
    case encryptedEntry(String)
    case unsupportedCompressionMethod(String, UInt16)
    case corruptEntry(String)
    case truncatedEntry(String)
    case inflateFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            return "The archive could not be opened."
        case .invalidArchive:
            return "The archive is not a valid ZIP/CBZ file."
        case .unsupportedZIP64:
            return "ZIP64 archives are not supported yet."
        case .unsupportedMultiDiskArchive:
            return "Split ZIP archives are not supported yet."
        case .noRenderablePages:
            return "No supported image pages were found inside this archive."
        case .pageIndexOutOfBounds(let index):
            return "The requested archive page \(index + 1) does not exist."
        case .encryptedEntry(let path):
            return "The archive entry `\(path)` is encrypted and cannot be opened yet."
        case .unsupportedCompressionMethod(let path, let method):
            return "The archive entry `\(path)` uses ZIP compression method \(method), which is not supported yet."
        case .corruptEntry(let path):
            return "The archive entry `\(path)` appears to be corrupt."
        case .truncatedEntry(let path):
            return "The archive entry `\(path)` could not be fully read."
        case .inflateFailed(let path):
            return "The archive entry `\(path)` could not be decompressed."
        }
    }
}

struct ZIPArchiveEntry: Sendable {
    let path: String
    let compressionMethod: UInt16
    let generalPurposeFlag: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32

    var isDirectory: Bool {
        path.hasSuffix("/")
    }
}

final class ZIPArchiveReader {
    private let fallbackReader: LibArchiveReader

    init(fallbackReader: LibArchiveReader = LibArchiveReader()) {
        self.fallbackReader = fallbackReader
    }

    func loadDocument(at archiveURL: URL) throws -> ImageSequenceComicDocument {
        do {
            let entries = try ZIPArchiveParser(archiveURL: archiveURL).parseEntries()
            let orderedEntries = try orderedPageEntries(from: entries)

            return ImageSequenceComicDocument(
                url: archiveURL,
                pageNames: orderedEntries.map(\.path),
                pageSource: try ZIPArchivePageSource(archiveURL: archiveURL, entries: orderedEntries)
            )
        } catch {
            guard shouldFallbackToLibArchive(for: error) else {
                throw error
            }

            do {
                return try fallbackReader.loadDocument(at: archiveURL)
            } catch {
                throw error
            }
        }
    }

    func extractMetadata(at archiveURL: URL, coverPage: Int = 1) throws -> ArchiveImageMetadata {
        do {
            let entries = try ZIPArchiveParser(archiveURL: archiveURL).parseEntries()
            let orderedEntries = try orderedPageEntries(from: entries)
            let coverIndex = min(max(coverPage - 1, 0), orderedEntries.count - 1)
            let coverData = try ZIPArchiveEntryReader.data(in: archiveURL, for: orderedEntries[coverIndex])
            let embeddedComicInfoData = try preferredEmbeddedComicInfoEntry(in: entries).flatMap {
                try ZIPArchiveEntryReader.data(in: archiveURL, for: $0)
            }

            return ArchiveImageMetadata(
                pageCount: orderedEntries.count,
                coverData: coverData,
                embeddedComicInfoData: embeddedComicInfoData
            )
        } catch {
            guard shouldFallbackToLibArchive(for: error) else {
                throw error
            }

            do {
                return try fallbackReader.extractMetadata(at: archiveURL, coverPage: coverPage)
            } catch {
                throw error
            }
        }
    }

    /// Lightweight: count pages by reading only the central directory (no decompression).
    func countPages(at archiveURL: URL) throws -> Int {
        let entries = try ZIPArchiveParser(archiveURL: archiveURL).parseEntries()
        return try orderedPageEntries(from: entries).count
    }

    private func orderedPageEntries(from entries: [ZIPArchiveEntry]) throws -> [ZIPArchiveEntry] {
        let pageEntries = entries
            .filter { !$0.isDirectory && ComicPageNameSorter.isSupportedImagePath($0.path) }

        guard !pageEntries.isEmpty else {
            throw ZIPArchiveError.noRenderablePages
        }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        var entriesByPath = Dictionary(grouping: pageEntries, by: \.path)
        var orderedEntries: [ZIPArchiveEntry] = []
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

    private func preferredEmbeddedComicInfoEntry(in entries: [ZIPArchiveEntry]) -> ZIPArchiveEntry? {
        guard let preferredPath = EmbeddedComicInfoLocator.preferredPath(in: entries.map(\.path)) else {
            return nil
        }

        return entries.first { $0.path == preferredPath }
    }

    private func shouldFallbackToLibArchive(for error: Error) -> Bool {
        guard let zipError = error as? ZIPArchiveError else {
            return false
        }

        switch zipError {
        case .unsupportedZIP64,
             .unsupportedMultiDiskArchive,
             .invalidArchive,
             .encryptedEntry,
             .unsupportedCompressionMethod,
             .corruptEntry,
             .truncatedEntry,
             .inflateFailed:
            return true
        case .unreadableArchive,
             .noRenderablePages,
             .pageIndexOutOfBounds:
            return false
        }
    }
}

private struct ZIPArchiveParser {
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let centralDirectoryFileHeaderSignature: UInt32 = 0x02014b50
    private static let localFileHeaderSignature: UInt32 = 0x04034b50

    let archiveURL: URL

    func parseEntries() throws -> [ZIPArchiveEntry] {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw ZIPArchiveError.unreadableArchive
        }

        defer {
            try? fileHandle.close()
        }

        let fileSize = try archiveFileSize()
        let endOfCentralDirectory = try locateEndOfCentralDirectory(
            fileHandle: fileHandle,
            fileSize: fileSize
        )

        guard endOfCentralDirectory.diskNumber == 0,
              endOfCentralDirectory.centralDirectoryStartDisk == 0
        else {
            throw ZIPArchiveError.unsupportedMultiDiskArchive
        }

        guard endOfCentralDirectory.totalEntries != 0xFFFF,
              endOfCentralDirectory.centralDirectorySize != 0xFFFFFFFF,
              endOfCentralDirectory.centralDirectoryOffset != 0xFFFFFFFF
        else {
            throw ZIPArchiveError.unsupportedZIP64
        }

        let centralDirectoryOffset = UInt64(endOfCentralDirectory.centralDirectoryOffset)
        let centralDirectorySize = Int(endOfCentralDirectory.centralDirectorySize)
        let centralDirectoryData = try readData(
            from: centralDirectoryOffset,
            length: centralDirectorySize,
            fileHandle: fileHandle
        )

        var entries: [ZIPArchiveEntry] = []
        entries.reserveCapacity(Int(endOfCentralDirectory.totalEntries))

        var offset = 0
        while offset < centralDirectoryData.count {
            guard centralDirectoryData.uint32LE(at: offset) == Self.centralDirectoryFileHeaderSignature else {
                throw ZIPArchiveError.invalidArchive
            }

            guard let generalPurposeFlag = centralDirectoryData.uint16LE(at: offset + 8),
                  let compressionMethod = centralDirectoryData.uint16LE(at: offset + 10),
                  let compressedSize = centralDirectoryData.uint32LE(at: offset + 20),
                  let uncompressedSize = centralDirectoryData.uint32LE(at: offset + 24),
                  let fileNameLength = centralDirectoryData.uint16LE(at: offset + 28),
                  let extraFieldLength = centralDirectoryData.uint16LE(at: offset + 30),
                  let commentLength = centralDirectoryData.uint16LE(at: offset + 32),
                  let localHeaderOffset = centralDirectoryData.uint32LE(at: offset + 42)
            else {
                throw ZIPArchiveError.invalidArchive
            }

            let headerSize = 46
            let pathStart = offset + headerSize
            let pathEnd = pathStart + Int(fileNameLength)
            let extraEnd = pathEnd + Int(extraFieldLength)
            let commentEnd = extraEnd + Int(commentLength)

            guard commentEnd <= centralDirectoryData.count else {
                throw ZIPArchiveError.invalidArchive
            }

            let fileNameData = centralDirectoryData.subdata(in: pathStart..<pathEnd)
            let path = decodeEntryName(fileNameData, generalPurposeFlag: generalPurposeFlag)

            entries.append(
                ZIPArchiveEntry(
                    path: path,
                    compressionMethod: compressionMethod,
                    generalPurposeFlag: generalPurposeFlag,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            offset = commentEnd
        }

        return entries
    }

    private func archiveFileSize() throws -> UInt64 {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize >= 0 else {
            throw ZIPArchiveError.invalidArchive
        }

        return UInt64(fileSize)
    }

    private func locateEndOfCentralDirectory(
        fileHandle: FileHandle,
        fileSize: UInt64
    ) throws -> ZIPEndOfCentralDirectory {
        let minimumRecordSize = 22
        let maximumCommentLength = 65_535
        let searchLength = Int(min(fileSize, UInt64(minimumRecordSize + maximumCommentLength)))
        let searchOffset = fileSize - UInt64(searchLength)
        let searchData = try readData(from: searchOffset, length: searchLength, fileHandle: fileHandle)

        guard let relativeOffset = searchData.lastIndex(of: Self.endOfCentralDirectorySignature) else {
            throw ZIPArchiveError.invalidArchive
        }

        guard let diskNumber = searchData.uint16LE(at: relativeOffset + 4),
              let centralDirectoryStartDisk = searchData.uint16LE(at: relativeOffset + 6),
              let entryCount = searchData.uint16LE(at: relativeOffset + 10),
              let centralDirectorySize = searchData.uint32LE(at: relativeOffset + 12),
              let centralDirectoryOffset = searchData.uint32LE(at: relativeOffset + 16)
        else {
            throw ZIPArchiveError.invalidArchive
        }

        return ZIPEndOfCentralDirectory(
            diskNumber: diskNumber,
            centralDirectoryStartDisk: centralDirectoryStartDisk,
            totalEntries: entryCount,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset
        )
    }

    private func readData(from offset: UInt64, length: Int, fileHandle: FileHandle) throws -> Data {
        guard length >= 0 else {
            throw ZIPArchiveError.invalidArchive
        }

        do {
            try fileHandle.seek(toOffset: offset)
            guard let data = try fileHandle.read(upToCount: length), data.count == length else {
                throw ZIPArchiveError.invalidArchive
            }
            return data
        } catch let error as ZIPArchiveError {
            throw error
        } catch {
            throw ZIPArchiveError.invalidArchive
        }
    }

    private func decodeEntryName(_ data: Data, generalPurposeFlag: UInt16) -> String {
        if (generalPurposeFlag & 0x800) != 0, let value = String(data: data, encoding: .utf8) {
            return value
        }

        if let value = String(data: data, encoding: .utf8) {
            return value
        }

        if let value = String(data: data, encoding: .isoLatin1) {
            return value
        }

        return data.map { String(UnicodeScalar($0)) }.joined()
    }
}

private struct ZIPEndOfCentralDirectory {
    let diskNumber: UInt16
    let centralDirectoryStartDisk: UInt16
    let totalEntries: UInt16
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
}

private enum ZIPArchiveEntryReader {
    nonisolated static func data(in archiveURL: URL, for entry: ZIPArchiveEntry) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: archiveURL)
        defer {
            try? fileHandle.close()
        }

        return try data(using: fileHandle, for: entry)
    }

    nonisolated static func data(using fileHandle: FileHandle, for entry: ZIPArchiveEntry) throws -> Data {
        guard (entry.generalPurposeFlag & 0x1) == 0 else {
            throw ZIPArchiveError.encryptedEntry(entry.path)
        }

        let dataOffset = try resolveDataOffset(using: fileHandle, for: entry)
        let compressedData = try readCompressedData(using: fileHandle, at: dataOffset, for: entry)

        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try decompressDeflatedData(
                rawDeflateData: compressedData,
                expectedSize: Int(entry.uncompressedSize),
                entryPath: entry.path
            )
        default:
            throw ZIPArchiveError.unsupportedCompressionMethod(entry.path, entry.compressionMethod)
        }
    }

    nonisolated private static func resolveDataOffset(
        using fileHandle: FileHandle,
        for entry: ZIPArchiveEntry
    ) throws -> UInt64 {
        let localHeaderOffset = UInt64(entry.localHeaderOffset)
        do {
            try fileHandle.seek(toOffset: localHeaderOffset)
            guard let localHeader = try fileHandle.read(upToCount: 30),
                  localHeader.count == 30,
                  localHeader.uint32LE(at: 0) == 0x04034b50,
                  let fileNameLength = localHeader.uint16LE(at: 26),
                  let extraFieldLength = localHeader.uint16LE(at: 28)
            else {
                throw ZIPArchiveError.invalidArchive
            }

            return localHeaderOffset + 30 + UInt64(fileNameLength) + UInt64(extraFieldLength)
        } catch let error as ZIPArchiveError {
            throw error
        } catch {
            throw ZIPArchiveError.invalidArchive
        }
    }

    nonisolated private static func readCompressedData(using fileHandle: FileHandle, at dataOffset: UInt64, for entry: ZIPArchiveEntry) throws -> Data {
        do {
            try fileHandle.seek(toOffset: dataOffset)
            guard let data = try fileHandle.read(upToCount: Int(entry.compressedSize)),
                  data.count == Int(entry.compressedSize)
            else {
                throw ZIPArchiveError.truncatedEntry(entry.path)
            }

            return data
        } catch let error as ZIPArchiveError {
            throw error
        } catch {
            throw ZIPArchiveError.corruptEntry(entry.path)
        }
    }

    /// Hard cap on decompressed output to guard against ZIP bombs and corrupted headers.
    nonisolated private static let maximumDecompressedSize = 256 * 1_024 * 1_024

    nonisolated private static func decompressDeflatedData(rawDeflateData: Data, expectedSize: Int, entryPath: String) throws -> Data {
        guard !rawDeflateData.isEmpty else {
            return Data()
        }

        var stream = z_stream()
        let initializeStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )

        guard initializeStatus == Z_OK else {
            throw ZIPArchiveError.inflateFailed(entryPath)
        }

        defer {
            inflateEnd(&stream)
        }

        return try rawDeflateData.withUnsafeBytes { rawBuffer -> Data in
            guard let inputBaseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                throw ZIPArchiveError.inflateFailed(entryPath)
            }

            stream.next_in = UnsafeMutablePointer(mutating: inputBaseAddress)
            stream.avail_in = uInt(rawDeflateData.count)

            var output = Data()
            let clampedExpectedSize = expectedSize > 0 ? min(expectedSize, maximumDecompressedSize) : 0
            if clampedExpectedSize > 0 {
                output.reserveCapacity(clampedExpectedSize)
            }

            let chunkSize = max(65_536, min(clampedExpectedSize > 0 ? clampedExpectedSize : 65_536, 1_048_576))
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let bufferCount = buffer.count
                let inflateStatus = buffer.withUnsafeMutableBytes { bufferPointer -> Int32 in
                    guard let baseAddress = bufferPointer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                        return Z_BUF_ERROR
                    }

                    stream.next_out = baseAddress
                    stream.avail_out = uInt(bufferCount)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }

                let producedBytes = bufferCount - Int(stream.avail_out)
                if producedBytes > 0 {
                    output.append(contentsOf: buffer.prefix(producedBytes))
                }

                if output.count > maximumDecompressedSize {
                    throw ZIPArchiveError.inflateFailed(entryPath)
                }

                if inflateStatus == Z_STREAM_END {
                    break
                }

                guard inflateStatus == Z_OK else {
                    throw ZIPArchiveError.inflateFailed(entryPath)
                }
            }

            return output
        }
    }
}

private actor ZIPArchivePageSource: ComicPageDataSource {
    private let archiveURL: URL
    private let entries: [ZIPArchiveEntry]
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    init(archiveURL: URL, entries: [ZIPArchiveEntry]) throws {
        self.archiveURL = archiveURL
        self.entries = entries
        self.cacheNamespace = ReaderPageCache.namespace(for: archiveURL)
    }

    func dataForPage(at index: Int) async throws -> Data {
        guard entries.indices.contains(index) else {
            throw ZIPArchiveError.pageIndexOutOfBounds(index)
        }

        if let cachedValue = cache.object(forKey: NSNumber(value: index)) {
            return Data(referencing: cachedValue)
        }

        let cacheKey = ReaderPageCacheKey(
            namespace: cacheNamespace,
            pageIdentifier: entries[index].path
        )
        if let cachedPage = await sharedCache.data(for: cacheKey) {
            cache.setObject(cachedPage as NSData, forKey: NSNumber(value: index), cost: cachedPage.count)
            return cachedPage
        }

        // Each read gets its own FileHandle to avoid seek/read interleaving across concurrent calls.
        let pageData = try ZIPArchiveEntryReader.data(in: archiveURL, for: entries[index])
        cache.setObject(pageData as NSData, forKey: NSNumber(value: index), cost: pageData.count)
        await sharedCache.store(pageData, for: cacheKey)
        return pageData
    }

    func prefetchPages(at indices: [Int]) async {
        for index in indices {
            guard entries.indices.contains(index) else {
                continue
            }

            _ = try? await dataForPage(at: index)
        }
    }
}

private extension Data {
    nonisolated func uint16LE(at offset: Int) -> UInt16? {
        integer(at: offset, as: UInt16.self)
    }

    nonisolated func uint32LE(at offset: Int) -> UInt32? {
        integer(at: offset, as: UInt32.self)
    }

    nonisolated func lastIndex(of value: UInt32) -> Int? {
        guard count >= MemoryLayout<UInt32>.size else {
            return nil
        }

        let signature = value.littleEndian
        return withUnsafeBytes { rawBuffer -> Int? in
            for offset in stride(from: count - MemoryLayout<UInt32>.size, through: 0, by: -1) {
                let candidate = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                if candidate == signature {
                    return offset
                }
            }

            return nil
        }
    }

    nonisolated private func integer<T: FixedWidthInteger>(at offset: Int, as type: T.Type) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            return nil
        }

        return withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self).littleEndian
        }
    }
}
