import Foundation
import UIKit
import zlib

enum RemoteZIPThumbnailExtractionError: Error {
    case invalidArchive
    case unsupportedZIP64
    case unsupportedMultiDiskArchive
    case noRenderablePages
    case encryptedEntry
    case unsupportedCompressionMethod
    case corruptEntry
    case truncatedEntry
    case inflateFailed
    case unreadableImage
}

struct RemoteZIPThumbnailExtractor {
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let centralDirectoryFileHeaderSignature: UInt32 = 0x02014b50
    private static let localFileHeaderSignature: UInt32 = 0x04034b50

    let fileReader: any RemoteRandomAccessFileReader

    func extractThumbnail(maxPixelSize: Int) async throws -> UIImage {
        let fileSize = try await fileReader.fileSize
        let endOfCentralDirectory = try await locateEndOfCentralDirectory(fileSize: fileSize)

        guard endOfCentralDirectory.diskNumber == 0,
              endOfCentralDirectory.centralDirectoryStartDisk == 0 else {
            throw RemoteZIPThumbnailExtractionError.unsupportedMultiDiskArchive
        }

        guard endOfCentralDirectory.totalEntries != 0xFFFF,
              endOfCentralDirectory.centralDirectorySize != 0xFFFFFFFF,
              endOfCentralDirectory.centralDirectoryOffset != 0xFFFFFFFF else {
            throw RemoteZIPThumbnailExtractionError.unsupportedZIP64
        }

        let centralDirectoryData = try await readData(
            from: UInt64(endOfCentralDirectory.centralDirectoryOffset),
            length: Int(endOfCentralDirectory.centralDirectorySize)
        )
        let entries = try await parseEntries(from: centralDirectoryData)
        let orderedEntries = orderedPageEntries(from: entries)

        guard let firstEntry = orderedEntries.first else {
            throw RemoteZIPThumbnailExtractionError.noRenderablePages
        }

        let imageData = try await data(for: firstEntry)
        guard let image = UIImage(data: imageData) else {
            throw RemoteZIPThumbnailExtractionError.unreadableImage
        }

        return downsampledImage(from: image, maxPixelSize: maxPixelSize)
    }

    private func locateEndOfCentralDirectory(fileSize: UInt64) async throws -> RemoteZIPEndOfCentralDirectory {
        let minimumRecordSize = 22
        let maximumCommentLength = 65_535
        let searchLength = Int(min(fileSize, UInt64(minimumRecordSize + maximumCommentLength)))
        let searchOffset = fileSize - UInt64(searchLength)
        let searchData = try await readData(from: searchOffset, length: searchLength)

        guard let relativeOffset = searchData.lastIndex(of: Self.endOfCentralDirectorySignature),
              let diskNumber = searchData.uint16LE(at: relativeOffset + 4),
              let centralDirectoryStartDisk = searchData.uint16LE(at: relativeOffset + 6),
              let entryCount = searchData.uint16LE(at: relativeOffset + 10),
              let centralDirectorySize = searchData.uint32LE(at: relativeOffset + 12),
              let centralDirectoryOffset = searchData.uint32LE(at: relativeOffset + 16) else {
            throw RemoteZIPThumbnailExtractionError.invalidArchive
        }

        return RemoteZIPEndOfCentralDirectory(
            diskNumber: diskNumber,
            centralDirectoryStartDisk: centralDirectoryStartDisk,
            totalEntries: entryCount,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset
        )
    }

    private func parseEntries(from centralDirectoryData: Data) async throws -> [RemoteZIPEntry] {
        var entries: [RemoteZIPEntry] = []
        var offset = 0

        while offset < centralDirectoryData.count {
            guard centralDirectoryData.uint32LE(at: offset) == Self.centralDirectoryFileHeaderSignature,
                  let generalPurposeFlag = centralDirectoryData.uint16LE(at: offset + 8),
                  let compressionMethod = centralDirectoryData.uint16LE(at: offset + 10),
                  let compressedSize = centralDirectoryData.uint32LE(at: offset + 20),
                  let uncompressedSize = centralDirectoryData.uint32LE(at: offset + 24),
                  let fileNameLength = centralDirectoryData.uint16LE(at: offset + 28),
                  let extraFieldLength = centralDirectoryData.uint16LE(at: offset + 30),
                  let commentLength = centralDirectoryData.uint16LE(at: offset + 32),
                  let localHeaderOffset = centralDirectoryData.uint32LE(at: offset + 42) else {
                throw RemoteZIPThumbnailExtractionError.invalidArchive
            }

            let headerSize = 46
            let pathStart = offset + headerSize
            let pathEnd = pathStart + Int(fileNameLength)
            let extraEnd = pathEnd + Int(extraFieldLength)
            let commentEnd = extraEnd + Int(commentLength)

            guard commentEnd <= centralDirectoryData.count else {
                throw RemoteZIPThumbnailExtractionError.invalidArchive
            }

            let fileNameData = centralDirectoryData.subdata(in: pathStart..<pathEnd)
            let path = decodeEntryName(fileNameData, generalPurposeFlag: generalPurposeFlag)
            let dataOffset = try await resolveDataOffset(from: UInt64(localHeaderOffset))

            entries.append(
                RemoteZIPEntry(
                    path: path,
                    compressionMethod: compressionMethod,
                    generalPurposeFlag: generalPurposeFlag,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    dataOffset: dataOffset
                )
            )

            offset = commentEnd
        }

        return entries
    }

    private func orderedPageEntries(from entries: [RemoteZIPEntry]) -> [RemoteZIPEntry] {
        let pageEntries = entries
            .filter { !$0.isDirectory && ComicPageNameSorter.isSupportedImagePath($0.path) }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        var entriesByPath = Dictionary(grouping: pageEntries, by: \.path)
        var orderedEntries: [RemoteZIPEntry] = []
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

    private func resolveDataOffset(from localHeaderOffset: UInt64) async throws -> UInt64 {
        let localHeader = try await readData(from: localHeaderOffset, length: 30)
        guard localHeader.uint32LE(at: 0) == Self.localFileHeaderSignature,
              let fileNameLength = localHeader.uint16LE(at: 26),
              let extraFieldLength = localHeader.uint16LE(at: 28) else {
            throw RemoteZIPThumbnailExtractionError.invalidArchive
        }

        return localHeaderOffset + 30 + UInt64(fileNameLength) + UInt64(extraFieldLength)
    }

    private func data(for entry: RemoteZIPEntry) async throws -> Data {
        guard (entry.generalPurposeFlag & 0x1) == 0 else {
            throw RemoteZIPThumbnailExtractionError.encryptedEntry
        }

        let compressedData = try await readData(
            from: entry.dataOffset,
            length: Int(entry.compressedSize)
        )

        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try decompressDeflatedData(
                rawDeflateData: compressedData,
                expectedSize: Int(entry.uncompressedSize)
            )
        default:
            throw RemoteZIPThumbnailExtractionError.unsupportedCompressionMethod
        }
    }

    private func readData(from offset: UInt64, length: Int) async throws -> Data {
        guard length >= 0 else {
            throw RemoteZIPThumbnailExtractionError.invalidArchive
        }

        let data = try await fileReader.read(offset: offset, length: UInt32(length))
        guard data.count == length else {
            throw RemoteZIPThumbnailExtractionError.truncatedEntry
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

    private func decompressDeflatedData(rawDeflateData: Data, expectedSize: Int) throws -> Data {
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
            throw RemoteZIPThumbnailExtractionError.inflateFailed
        }

        defer {
            inflateEnd(&stream)
        }

        return try rawDeflateData.withUnsafeBytes { rawBuffer -> Data in
            guard let inputBaseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                throw RemoteZIPThumbnailExtractionError.inflateFailed
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
                    throw RemoteZIPThumbnailExtractionError.inflateFailed
                }
            }

            return output
        }
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

private struct RemoteZIPEndOfCentralDirectory {
    let diskNumber: UInt16
    let centralDirectoryStartDisk: UInt16
    let totalEntries: UInt16
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
}

private struct RemoteZIPEntry {
    let path: String
    let compressionMethod: UInt16
    let generalPurposeFlag: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let dataOffset: UInt64

    var isDirectory: Bool {
        path.hasSuffix("/")
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16? {
        integer(at: offset, as: UInt16.self)
    }

    func uint32LE(at offset: Int) -> UInt32? {
        integer(at: offset, as: UInt32.self)
    }

    func lastIndex(of value: UInt32) -> Int? {
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

    private func integer<T: FixedWidthInteger>(at offset: Int, as type: T.Type) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            return nil
        }

        return withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self).littleEndian
        }
    }
}
