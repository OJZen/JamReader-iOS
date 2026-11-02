import UIKit
import XCTest
@testable import JamReader

@MainActor
final class RemoteLibArchiveThumbnailExtractorTests: XCTestCase {
    func testExtractionLeavesTheMainActorFreeForRemoteReads() async throws {
        let reader = MainActorArchiveReader(
            data: makeTAR(name: "001.png", contents: try XCTUnwrap(makePage().pngData()))
        )

        let thumbnail = try await RemoteLibArchiveThumbnailExtractor(fileReader: reader)
            .extractThumbnail(maxPixelSize: 30)

        XCTAssertEqual(thumbnail.size, CGSize(width: 20, height: 30))
        XCTAssertGreaterThan(reader.readCount, 0)
    }

    func testReadFailureReachesTheCaller() async {
        let reader = MainActorArchiveReader(data: Data(count: 1_024), readError: URLError(.timedOut))

        do {
            _ = try await RemoteLibArchiveThumbnailExtractor(fileReader: reader)
                .extractThumbnail(maxPixelSize: 30)
            XCTFail("A failed remote read must not produce a thumbnail")
        } catch {
            XCTAssertEqual(reader.readCount, 1)
        }
    }

    private func makePage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    private func makeTAR(name: String, contents: Data) -> Data {
        var header = Data(repeating: 0, count: 512)
        header.replaceSubrange(0..<name.utf8.count, with: Data(name.utf8))
        put("0000644\0", in: &header, at: 100)
        put("0000000\0", in: &header, at: 108)
        put("0000000\0", in: &header, at: 116)
        put(String(format: "%011o\0", contents.count), in: &header, at: 124)
        put("00000000000\0", in: &header, at: 136)
        put("        ", in: &header, at: 148)
        put("0", in: &header, at: 156)
        put("ustar\000", in: &header, at: 257)
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o\0 ", checksum), in: &header, at: 148)

        let padding = (512 - contents.count % 512) % 512
        return header + contents + Data(count: padding + 1_024)
    }

    private func put(_ value: String, in data: inout Data, at offset: Int) {
        let bytes = Data(value.utf8)
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
}

/// Isolated like the real SMB and WebDAV readers, whose reads start on the main actor.
private final class MainActorArchiveReader: RemoteRandomAccessFileReader {
    private let data: Data
    private let readError: Error?
    private(set) var readCount = 0

    init(data: Data, readError: Error? = nil) {
        self.data = data
        self.readError = readError
    }

    var fileSize: UInt64 { get async throws { UInt64(data.count) } }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        readCount += 1
        if let readError {
            throw readError
        }
        return data.subdata(in: Int(offset)..<(Int(offset) + Int(length)))
    }

    func close() async throws {}
}
