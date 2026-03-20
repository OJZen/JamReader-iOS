import Foundation
import UIKit

enum RemoteTARThumbnailExtractionError: Error {
    case invalidArchive
    case noRenderablePages
    case truncatedEntry
    case unreadableImage
}

struct RemoteTARThumbnailExtractor {
    private static let blockSize = 512
    private static let regularTypeFlags: Set<UInt8> = [0, ascii("0"), ascii("7")]
    private static let directoryTypeFlags: Set<UInt8> = [ascii("5")]
    private static let paxTypeFlags: Set<UInt8> = [ascii("x"), ascii("g")]
    private static let longNameTypeFlag = ascii("L")

    let fileReader: FileReader

    func extractThumbnail(maxPixelSize: Int) async throws -> UIImage {
        let fileSize = try await fileReader.fileSize
        let entries = try await parseEntries(fileSize: fileSize)
        let orderedEntries = orderedPageEntries(from: entries)

        guard let firstEntry = orderedEntries.first else {
            throw RemoteTARThumbnailExtractionError.noRenderablePages
        }

        let imageData = try await readData(from: firstEntry.dataOffset, length: firstEntry.size)
        guard let image = UIImage(data: imageData) else {
            throw RemoteTARThumbnailExtractionError.unreadableImage
        }

        return downsampledImage(from: image, maxPixelSize: maxPixelSize)
    }

    private func parseEntries(fileSize: UInt64) async throws -> [RemoteTAREntry] {
        var entries: [RemoteTAREntry] = []
        var offset: UInt64 = 0
        var pendingLongPath: String?
        var pendingPAXValues: [String: String] = [:]

        while offset + UInt64(Self.blockSize) <= fileSize {
            let header = try await readData(from: offset, length: Self.blockSize)

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
                let longNameData = try await readData(from: dataOffset, length: entrySize)
                pendingLongPath = decodeStringField(longNameData)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0\n"))
            case let flag where Self.paxTypeFlags.contains(flag):
                let paxData = try await readData(from: dataOffset, length: entrySize)
                pendingPAXValues = parsePAXRecords(paxData)
            case let flag where Self.regularTypeFlags.contains(flag):
                entries.append(
                    RemoteTAREntry(
                        path: resolvedPath,
                        size: entrySize,
                        dataOffset: dataOffset
                    )
                )
                pendingLongPath = nil
                pendingPAXValues = [:]
            case let flag where Self.directoryTypeFlags.contains(flag):
                entries.append(
                    RemoteTAREntry(
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

    private func orderedPageEntries(from entries: [RemoteTAREntry]) -> [RemoteTAREntry] {
        let pageEntries = entries
            .filter { !$0.isDirectory && ComicPageNameSorter.isSupportedImagePath($0.path) }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        let entriesByPath = Dictionary(uniqueKeysWithValues: pageEntries.map { ($0.path, $0) })
        return sortedPaths.compactMap { entriesByPath[$0] }
    }

    private func parseSize(from header: Data) throws -> Int {
        guard let size = parseOctalInteger(from: header.subdata(in: 124..<136)) else {
            throw RemoteTARThumbnailExtractionError.invalidArchive
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
                  recordLength > 0 else {
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

    private func readData(from offset: UInt64, length: Int) async throws -> Data {
        guard length >= 0 else {
            throw RemoteTARThumbnailExtractionError.invalidArchive
        }

        let data = try await fileReader.read(offset: offset, length: UInt32(length))
        guard data.count == length else {
            throw RemoteTARThumbnailExtractionError.truncatedEntry
        }

        return data
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

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue ?? 0
    }
}

private struct RemoteTAREntry {
    let path: String
    let size: Int
    let dataOffset: UInt64

    var isDirectory: Bool {
        path.hasSuffix("/")
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
