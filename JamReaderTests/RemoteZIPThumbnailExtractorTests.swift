import UIKit
import XCTest
@testable import JamReader

final class RemoteZIPThumbnailExtractorTests: XCTestCase {
    func testCoverReadsOnlyItsOwnLocalHeaderHoweverManyPagesTheArchiveHas() async throws {
        let cover = try XCTUnwrap(makePage().pngData())
        // The cover is stored last, so finding it depends on page order rather than archive order.
        var pages = (2...40).map { (name: String(format: "%03d.png", $0), contents: Data("filler".utf8)) }
        pages.append((name: "001.png", contents: cover))
        let reader = CountingZIPReader(data: makeZIP(pages: pages))

        let thumbnail = try await RemoteZIPThumbnailExtractor(fileReader: reader)
            .extractThumbnail(maxPixelSize: 30)

        XCTAssertEqual(thumbnail.size, CGSize(width: 20, height: 30))
        // End record, central directory, the cover's local header and its data.
        XCTAssertEqual(reader.readCount, 4)
    }

    private func makePage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    /// Local headers carry an extra field the central directory lacks, as Info-ZIP archives do,
    /// so a page's data offset can only come from its own local header.
    private func makeZIP(pages: [(name: String, contents: Data)]) -> Data {
        let localExtra = Data(repeating: 0, count: 4)
        var result = Data()
        var directory = Data()
        for page in pages {
            let name = Data(page.name.utf8)
            var local = Data(repeating: 0, count: 30)
            put(0x04034b50, in: &local, at: 0)
            put(UInt32(page.contents.count), in: &local, at: 18)
            put(UInt32(page.contents.count), in: &local, at: 22)
            put(UInt32(name.count), in: &local, at: 26, bytes: 2)
            put(UInt32(localExtra.count), in: &local, at: 28, bytes: 2)
            var central = Data(repeating: 0, count: 46)
            put(0x02014b50, in: &central, at: 0)
            put(UInt32(page.contents.count), in: &central, at: 20)
            put(UInt32(page.contents.count), in: &central, at: 24)
            put(UInt32(name.count), in: &central, at: 28, bytes: 2)
            put(UInt32(result.count), in: &central, at: 42)
            result.append(local + name + localExtra + page.contents)
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

private final class CountingZIPReader: RemoteRandomAccessFileReader {
    private let data: Data
    private(set) var readCount = 0

    init(data: Data) {
        self.data = data
    }

    var fileSize: UInt64 { get async throws { UInt64(data.count) } }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        readCount += 1
        return data.subdata(in: Int(offset)..<(Int(offset) + Int(length)))
    }

    func close() async throws {}
}
