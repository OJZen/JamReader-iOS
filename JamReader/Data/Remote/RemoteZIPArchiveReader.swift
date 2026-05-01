import Foundation
import zlib

nonisolated struct RemoteZIPArchiveReader {
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let centralDirectoryFileHeaderSignature: UInt32 = 0x02014b50
    private static let localFileHeaderSignature: UInt32 = 0x04034b50

    func loadDocument(
        from fileReader: any RemoteRandomAccessFileReader,
        documentURL: URL
    ) async throws -> ImageSequenceComicDocument {
        let fileSize = try await fileReader.fileSize
        let endOfCentralDirectory = try await locateEndOfCentralDirectory(
            fileReader: fileReader,
            fileSize: fileSize
        )

        guard endOfCentralDirectory.diskNumber == 0,
              endOfCentralDirectory.centralDirectoryStartDisk == 0 else {
            throw ZIPArchiveError.unsupportedMultiDiskArchive
        }

        guard endOfCentralDirectory.totalEntries != 0xFFFF,
              endOfCentralDirectory.centralDirectorySize != 0xFFFFFFFF,
              endOfCentralDirectory.centralDirectoryOffset != 0xFFFFFFFF else {
            throw ZIPArchiveError.unsupportedZIP64
        }

        let centralDirectoryData = try await readData(
            with: fileReader,
            from: UInt64(endOfCentralDirectory.centralDirectoryOffset),
            length: Int(endOfCentralDirectory.centralDirectorySize)
        )
        let entries = try parseEntries(from: centralDirectoryData)
        let orderedEntries = try orderedPageEntries(from: entries)

        return ImageSequenceComicDocument(
            url: documentURL,
            pageNames: orderedEntries.map(\.path),
            pageSource: RemoteZIPArchivePageSource(
                documentURL: documentURL,
                fileReader: fileReader,
                entries: orderedEntries
            )
        )
    }

    private func locateEndOfCentralDirectory(
        fileReader: any RemoteRandomAccessFileReader,
        fileSize: UInt64
    ) async throws -> RemoteZIPEndOfCentralDirectory {
        let minimumRecordSize = 22
        let maximumCommentLength = 65_535
        let searchLength = Int(min(fileSize, UInt64(minimumRecordSize + maximumCommentLength)))
        let searchOffset = fileSize - UInt64(searchLength)
        let searchData = try await readData(with: fileReader, from: searchOffset, length: searchLength)

        guard let relativeOffset = searchData.lastIndex(of: Self.endOfCentralDirectorySignature),
              let diskNumber = searchData.uint16LE(at: relativeOffset + 4),
              let centralDirectoryStartDisk = searchData.uint16LE(at: relativeOffset + 6),
              let entryCount = searchData.uint16LE(at: relativeOffset + 10),
              let centralDirectorySize = searchData.uint32LE(at: relativeOffset + 12),
              let centralDirectoryOffset = searchData.uint32LE(at: relativeOffset + 16) else {
            throw ZIPArchiveError.invalidArchive
        }

        return RemoteZIPEndOfCentralDirectory(
            diskNumber: diskNumber,
            centralDirectoryStartDisk: centralDirectoryStartDisk,
            totalEntries: entryCount,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset
        )
    }

    private func parseEntries(from centralDirectoryData: Data) throws -> [ZIPArchiveEntry] {
        var entries: [ZIPArchiveEntry] = []
        entries.reserveCapacity(32)

        var offset = 0
        while offset < centralDirectoryData.count {
            try Task.checkCancellation()

            guard centralDirectoryData.uint32LE(at: offset) == Self.centralDirectoryFileHeaderSignature,
                  let generalPurposeFlag = centralDirectoryData.uint16LE(at: offset + 8),
                  let compressionMethod = centralDirectoryData.uint16LE(at: offset + 10),
                  let compressedSize = centralDirectoryData.uint32LE(at: offset + 20),
                  let uncompressedSize = centralDirectoryData.uint32LE(at: offset + 24),
                  let fileNameLength = centralDirectoryData.uint16LE(at: offset + 28),
                  let extraFieldLength = centralDirectoryData.uint16LE(at: offset + 30),
                  let commentLength = centralDirectoryData.uint16LE(at: offset + 32),
                  let localHeaderOffset = centralDirectoryData.uint32LE(at: offset + 42) else {
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

    private func readData(
        with fileReader: any RemoteRandomAccessFileReader,
        from offset: UInt64,
        length: Int
    ) async throws -> Data {
        guard length >= 0, length <= Int(UInt32.max) else {
            throw ZIPArchiveError.invalidArchive
        }

        try Task.checkCancellation()
        let data = try await fileReader.read(offset: offset, length: UInt32(length))
        guard data.count == length else {
            throw ZIPArchiveError.invalidArchive
        }

        return data
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

private struct RemoteZIPEndOfCentralDirectory {
    let diskNumber: UInt16
    let centralDirectoryStartDisk: UInt16
    let totalEntries: UInt16
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
}

private actor RemoteZIPArchivePageSource: ComicPageDataSource {
    private let fileReaderBox: RemoteRandomAccessFileReaderBox
    private let entries: [ZIPArchiveEntry]
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 12
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private var hasClosed = false

    init(
        documentURL: URL,
        fileReader: any RemoteRandomAccessFileReader,
        entries: [ZIPArchiveEntry]
    ) {
        self.fileReaderBox = RemoteRandomAccessFileReaderBox(fileReader)
        self.entries = entries
        self.cacheNamespace = ReaderPageCache.namespace(for: documentURL)
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

        try Task.checkCancellation()
        let pageData = try await data(for: entries[index])
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

    func close() async {
        guard !hasClosed else {
            return
        }

        hasClosed = true
        try? await fileReaderBox.fileReader.close()
    }

    private func data(for entry: ZIPArchiveEntry) async throws -> Data {
        guard (entry.generalPurposeFlag & 0x1) == 0 else {
            throw ZIPArchiveError.encryptedEntry(entry.path)
        }

        let dataOffset = try await resolveDataOffset(for: entry)
        let compressedData = try await readData(
            from: dataOffset,
            length: Int(entry.compressedSize),
            truncatedError: ZIPArchiveError.truncatedEntry(entry.path)
        )

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

    private func resolveDataOffset(for entry: ZIPArchiveEntry) async throws -> UInt64 {
        let localHeaderOffset = UInt64(entry.localHeaderOffset)
        let localHeader = try await readData(
            from: localHeaderOffset,
            length: 30,
            truncatedError: ZIPArchiveError.invalidArchive
        )
        guard localHeader.uint32LE(at: 0) == 0x04034b50,
              let fileNameLength = localHeader.uint16LE(at: 26),
              let extraFieldLength = localHeader.uint16LE(at: 28) else {
            throw ZIPArchiveError.invalidArchive
        }

        return localHeaderOffset + 30 + UInt64(fileNameLength) + UInt64(extraFieldLength)
    }

    private func readData(
        from offset: UInt64,
        length: Int,
        truncatedError: ZIPArchiveError
    ) async throws -> Data {
        guard length >= 0, length <= Int(UInt32.max) else {
            throw ZIPArchiveError.invalidArchive
        }

        try Task.checkCancellation()
        let data = try await fileReaderBox.fileReader.read(offset: offset, length: UInt32(length))
        guard data.count == length else {
            throw truncatedError
        }

        return data
    }

    private func decompressDeflatedData(
        rawDeflateData: Data,
        expectedSize: Int,
        entryPath: String
    ) throws -> Data {
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
            if expectedSize > 0 {
                output.reserveCapacity(expectedSize)
            }

            let chunkSize = max(65_536, min(expectedSize > 0 ? expectedSize : 65_536, 1_048_576))
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

private struct RemoteRandomAccessFileReaderBox: @unchecked Sendable {
    let fileReader: any RemoteRandomAccessFileReader

    init(_ fileReader: any RemoteRandomAccessFileReader) {
        self.fileReader = fileReader
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
