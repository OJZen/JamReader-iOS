import Foundation

enum TARArchiveError: LocalizedError {
    case unreadableArchive
    case invalidArchive
    case noRenderablePages
    case pageIndexOutOfBounds(Int)
    case truncatedEntry(String)

    var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            return "The archive could not be opened."
        case .invalidArchive:
            return "The archive is not a valid TAR/CBT file."
        case .noRenderablePages:
            return "No supported image pages were found inside this archive."
        case .pageIndexOutOfBounds(let index):
            return "The requested archive page \(index + 1) does not exist."
        case .truncatedEntry(let path):
            return "The archive entry `\(path)` could not be fully read."
        }
    }
}

struct TARArchiveEntry: Sendable {
    let path: String
    let size: Int
    let dataOffset: UInt64

    var isDirectory: Bool {
        path.hasSuffix("/")
    }
}

final class TARArchiveReader {
    func loadDocument(at archiveURL: URL) throws -> ImageSequenceComicDocument {
        let entries = try TARArchiveParser(archiveURL: archiveURL).parseEntries()
        let orderedEntries = try orderedPageEntries(from: entries)

        return ImageSequenceComicDocument(
            url: archiveURL,
            pageNames: orderedEntries.map(\.path),
            pageSource: try TARArchivePageSource(archiveURL: archiveURL, entries: orderedEntries)
        )
    }

    func extractMetadata(at archiveURL: URL, coverPage: Int = 1) throws -> ArchiveImageMetadata {
        let entries = try TARArchiveParser(archiveURL: archiveURL).parseEntries()
        let orderedEntries = try orderedPageEntries(from: entries)
        let coverIndex = min(max(coverPage - 1, 0), orderedEntries.count - 1)
        let coverData = try TARArchiveEntryReader.data(in: archiveURL, for: orderedEntries[coverIndex])
        let embeddedComicInfoData = try preferredEmbeddedComicInfoEntry(in: entries).flatMap {
            try TARArchiveEntryReader.data(in: archiveURL, for: $0)
        }

        return ArchiveImageMetadata(
            pageCount: orderedEntries.count,
            coverData: coverData,
            embeddedComicInfoData: embeddedComicInfoData
        )
    }

    func extractMetadataSummary(at archiveURL: URL) throws -> (pageCount: Int, embeddedComicInfoData: Data?) {
        let entries = try TARArchiveParser(archiveURL: archiveURL).parseEntries()
        let orderedEntries = try orderedPageEntries(from: entries)
        let embeddedComicInfoData = try preferredEmbeddedComicInfoEntry(in: entries).flatMap {
            try TARArchiveEntryReader.data(in: archiveURL, for: $0)
        }

        return (orderedEntries.count, embeddedComicInfoData)
    }

    /// Lightweight: count pages by parsing headers only (no data extraction).
    func countPages(at archiveURL: URL) throws -> Int {
        let entries = try TARArchiveParser(archiveURL: archiveURL).parseEntries()
        return try orderedPageEntries(from: entries).count
    }

    private func orderedPageEntries(from entries: [TARArchiveEntry]) throws -> [TARArchiveEntry] {
        let pageEntries = entries
            .filter { !$0.isDirectory && ComicPageNameSorter.isSupportedImagePath($0.path) }

        guard !pageEntries.isEmpty else {
            throw TARArchiveError.noRenderablePages
        }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        let entriesByPath = Dictionary(uniqueKeysWithValues: pageEntries.map { ($0.path, $0) })
        return sortedPaths.compactMap { entriesByPath[$0] }
    }

    private func preferredEmbeddedComicInfoEntry(in entries: [TARArchiveEntry]) -> TARArchiveEntry? {
        guard let preferredPath = EmbeddedComicInfoLocator.preferredPath(in: entries.map(\.path)) else {
            return nil
        }

        return entries.first { $0.path == preferredPath }
    }
}

private struct TARArchiveParser {
    private static let blockSize = 512
    private static let regularTypeFlags: Set<UInt8> = [0, ascii("0"), ascii("7")]
    private static let directoryTypeFlags: Set<UInt8> = [ascii("5")]
    private static let paxTypeFlags: Set<UInt8> = [ascii("x"), ascii("g")]
    private static let longNameTypeFlag = ascii("L")

    let archiveURL: URL

    private static let maxEntries = 100_000

    func parseEntries() throws -> [TARArchiveEntry] {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw TARArchiveError.unreadableArchive
        }

        defer {
            try? fileHandle.close()
        }

        let fileSize = try archiveFileSize()

        var entries: [TARArchiveEntry] = []
        var offset: UInt64 = 0
        var pendingLongPath: String?
        var pendingPAXValues: [String: String] = [:]

        while offset + UInt64(Self.blockSize) <= fileSize {
            guard entries.count < Self.maxEntries else {
                break
            }
            let header = try readData(
                from: offset,
                length: Self.blockSize,
                fileHandle: fileHandle
            )

            if header.isTARZeroBlock {
                break
            }

            let entrySize = try parseSize(from: header)
            let typeFlag = header.byte(at: 156) ?? 0
            let dataOffset = offset + UInt64(Self.blockSize)
            let nextOffset = dataOffset + paddedSize(for: entrySize)

            let parsedPath = makeEntryPath(from: header)
            let resolvedPath = pendingPAXValues["path"] ?? pendingLongPath ?? parsedPath

            switch typeFlag {
            case Self.longNameTypeFlag:
                let longNameData = try readData(
                    from: dataOffset,
                    length: entrySize,
                    fileHandle: fileHandle
                )
                pendingLongPath = decodeStringField(longNameData)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0\n"))
            case let flag where Self.paxTypeFlags.contains(flag):
                let paxData = try readData(
                    from: dataOffset,
                    length: entrySize,
                    fileHandle: fileHandle
                )
                pendingPAXValues = parsePAXRecords(paxData)
            case let flag where Self.regularTypeFlags.contains(flag):
                entries.append(
                    TARArchiveEntry(
                        path: resolvedPath,
                        size: entrySize,
                        dataOffset: dataOffset
                    )
                )
                pendingLongPath = nil
                pendingPAXValues = [:]
            case let flag where Self.directoryTypeFlags.contains(flag):
                entries.append(
                    TARArchiveEntry(
                        path: resolvedPath.hasSuffix("/") ? resolvedPath : resolvedPath + "/",
                        size: 0,
                        dataOffset: dataOffset
                    )
                )
                pendingLongPath = nil
                pendingPAXValues = [:]
            default:
                pendingLongPath = nil
                pendingPAXValues = [:]
            }

            offset = nextOffset
        }

        return entries
    }

    private func archiveFileSize() throws -> UInt64 {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize >= 0 else {
            throw TARArchiveError.invalidArchive
        }

        return UInt64(fileSize)
    }

    private func parseSize(from header: Data) throws -> Int {
        guard let size = parseOctalInteger(from: header.subdata(in: 124..<136)) else {
            throw TARArchiveError.invalidArchive
        }

        return size
    }

    private func makeEntryPath(from header: Data) -> String {
        let name = decodeStringField(header.subdata(in: 0..<100))
        let prefix = decodeStringField(header.subdata(in: 345..<500))

        if prefix.isEmpty {
            return name
        }

        return "\(prefix)/\(name)"
    }

    private func parseOctalInteger(from data: Data) -> Int? {
        let string = decodeStringField(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else {
            return 0
        }

        return Int(string, radix: 8)
    }

    private func decodeStringField(_ data: Data) -> String {
        let trimmedData = data.prefix { byte in
            byte != 0
        }

        if let value = String(data: trimmedData, encoding: .utf8) {
            return value
        }

        if let value = String(data: trimmedData, encoding: .isoLatin1) {
            return value
        }

        return String(decoding: trimmedData, as: UTF8.self)
    }

    private static let maxPAXRecordLength = 1_048_576

    private func parsePAXRecords(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        var position = 0
        let bytes = [UInt8](data)

        while position < bytes.count {
            guard let spaceIndex = bytes[position...].firstIndex(of: 0x20) else {
                break
            }

            let lengthData = Data(bytes[position..<spaceIndex])
            guard let lengthString = String(data: lengthData, encoding: .utf8),
                  let recordLength = Int(lengthString),
                  recordLength > 0,
                  recordLength <= Self.maxPAXRecordLength
            else {
                break
            }

            let recordEnd = position + recordLength
            guard recordEnd <= bytes.count, spaceIndex + 1 < recordEnd else {
                break
            }

            let bodyRange = (spaceIndex + 1)..<max(spaceIndex + 1, recordEnd - 1)
            let bodyData = Data(bytes[bodyRange])
            if let bodyString = String(data: bodyData, encoding: .utf8),
               let separatorIndex = bodyString.firstIndex(of: "=") {
                let key = String(bodyString[..<separatorIndex])
                let value = String(bodyString[bodyString.index(after: separatorIndex)...])
                result[key] = value
            }

            position = recordEnd
        }

        return result
    }

    private func paddedSize(for size: Int) -> UInt64 {
        let blocks = (size + Self.blockSize - 1) / Self.blockSize
        return UInt64(blocks * Self.blockSize)
    }

    private func readData(from offset: UInt64, length: Int, fileHandle: FileHandle) throws -> Data {
        guard length >= 0 else {
            throw TARArchiveError.invalidArchive
        }

        do {
            try fileHandle.seek(toOffset: offset)
            guard let data = try fileHandle.read(upToCount: length), data.count == length else {
                throw TARArchiveError.invalidArchive
            }

            return data
        } catch let error as TARArchiveError {
            throw error
        } catch {
            throw TARArchiveError.invalidArchive
        }
    }

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue ?? 0
    }
}

private enum TARArchiveEntryReader {
    nonisolated static func data(in archiveURL: URL, for entry: TARArchiveEntry) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: archiveURL)
        defer {
            try? fileHandle.close()
        }

        return try data(using: fileHandle, for: entry)
    }

    nonisolated static func data(using fileHandle: FileHandle, for entry: TARArchiveEntry) throws -> Data {
        do {
            try fileHandle.seek(toOffset: entry.dataOffset)
            guard let data = try fileHandle.read(upToCount: entry.size),
                  data.count == entry.size
            else {
                throw TARArchiveError.truncatedEntry(entry.path)
            }
            return data
        } catch let error as TARArchiveError {
            throw error
        } catch {
            throw TARArchiveError.truncatedEntry(entry.path)
        }
    }
}

private actor TARArchivePageSource: ComicPageDataSource {
    private let archiveURL: URL
    private let entries: [TARArchiveEntry]
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    init(archiveURL: URL, entries: [TARArchiveEntry]) throws {
        self.archiveURL = archiveURL
        self.entries = entries
        self.cacheNamespace = ReaderPageCache.namespace(for: archiveURL)
    }

    func dataForPage(at index: Int) async throws -> Data {
        guard entries.indices.contains(index) else {
            throw TARArchiveError.pageIndexOutOfBounds(index)
        }

        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return Data(referencing: cached)
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
        let data = try TARArchiveEntryReader.data(in: archiveURL, for: entries[index])
        cache.setObject(data as NSData, forKey: NSNumber(value: index), cost: data.count)
        await sharedCache.store(data, for: cacheKey)
        return data
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
    var isTARZeroBlock: Bool {
        !isEmpty && allSatisfy { $0 == 0 }
    }

    func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else {
            return nil
        }

        return self[index(startIndex, offsetBy: offset)]
    }
}
