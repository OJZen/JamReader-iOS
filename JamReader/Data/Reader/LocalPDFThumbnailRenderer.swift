import CoreGraphics
import Foundation
import UIKit

struct LocalPDFThumbnail {
    let image: UIImage
    let originalPageSize: CGSize
}

enum LocalPDFThumbnailRenderer {
    nonisolated static func pageCount(for fileURL: URL) -> Int? {
        guard let document = CGPDFDocument(fileURL as CFURL) else {
            return nil
        }
        return document.numberOfPages
    }

    nonisolated static func thumbnail(
        from fileURL: URL,
        pageIndex: Int = 0,
        maxPixelSize: Int
    ) -> UIImage? {
        thumbnailInfo(
            from: fileURL,
            pageIndex: pageIndex,
            maxPixelSize: maxPixelSize
        )?.image
    }

    nonisolated static func thumbnailInfo(
        from fileURL: URL,
        pageIndex: Int = 0,
        maxPixelSize: Int
    ) -> LocalPDFThumbnail? {
        guard let document = CGPDFDocument(fileURL as CFURL),
              document.numberOfPages > 0
        else {
            return nil
        }

        let clampedPageIndex = min(max(pageIndex, 0), document.numberOfPages - 1)
        guard let page = document.page(at: clampedPageIndex + 1) else {
            return nil
        }

        return thumbnail(for: page, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func thumbnail(
        for page: CGPDFPage,
        maxPixelSize: Int
    ) -> LocalPDFThumbnail? {
        let pageBounds = page.getBoxRect(.mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let targetSize = scaledTargetSize(
            for: pageBounds.size,
            maxPixelSize: maxPixelSize
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { context in
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

        return LocalPDFThumbnail(
            image: image,
            originalPageSize: pageBounds.size
        )
    }

    nonisolated private static func scaledTargetSize(
        for sourceSize: CGSize,
        maxPixelSize: Int
    ) -> CGSize {
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
