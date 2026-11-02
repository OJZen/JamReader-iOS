import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import JamReader

final class ReaderPagedImageDecoderTests: XCTestCase {
    func testFullResolutionPageArrivesDecoded() throws {
        let data = try makeJPEG()

        let image = try XCTUnwrap(ReaderPagedImageDecoder.decodeImage(
            from: data,
            maxPixelSize: 10,
            preferFullResolution: true
        ))

        XCTAssertFalse(isDecoded(try XCTUnwrap(UIImage(data: data))), "A plain UIImage stays undecoded")
        XCTAssertTrue(isDecoded(image))
    }

    func testPageWithinTheSizeLimitArrivesDecoded() throws {
        let image = try XCTUnwrap(ReaderPagedImageDecoder.decodeImage(
            from: try makeJPEG(),
            maxPixelSize: 4096,
            preferFullResolution: false
        ))

        XCTAssertTrue(isDecoded(image))
    }

    func testDecodingKeepsThePageGeometry() throws {
        let data = try makeJPEG(orientation: .right)

        let image = try XCTUnwrap(ReaderPagedImageDecoder.decodeImage(
            from: data,
            maxPixelSize: 4096,
            preferFullResolution: false
        ))

        XCTAssertEqual(image.size, CGSize(width: 300, height: 200))
        XCTAssertEqual(image.scale, 1)
    }

    /// `preparingForDisplay()` hands back the same image once there is nothing left to decode.
    private func isDecoded(_ image: UIImage) -> Bool {
        image.preparingForDisplay() === image
    }

    private func makeJPEG(orientation: CGImagePropertyOrientation = .up) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            try XCTUnwrap(page.cgImage),
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
