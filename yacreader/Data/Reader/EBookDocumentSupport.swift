import CryptoKit
import Foundation
import QuickLook
import QuickLookThumbnailing
import UIKit

enum EBookDocumentSupport {
    nonisolated static let supportedExtensions: Set<String> = ["epub", "mobi"]

    nonisolated static func supportsFileExtension(_ fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }

    nonisolated static func canPreviewDocument(at fileURL: URL) -> Bool {
        guard supportsFileExtension(fileURL.pathExtension) else {
            return false
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                QLPreviewController.canPreview(fileURL as NSURL)
            }
        }

        var canPreview = false
        DispatchQueue.main.sync {
            canPreview = MainActor.assumeIsolated {
                QLPreviewController.canPreview(fileURL as NSURL)
            }
        }
        return canPreview
    }

    nonisolated static func unsupportedReason(for fileURL: URL) -> String {
        "\(fileURL.pathExtension.uppercased()) preview is not available on this device."
    }

    nonisolated static func documentIdentifier(for fileURL: URL) -> String {
        let resourceValues = try? fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileSize = resourceValues?.fileSize ?? 0
        let modificationDate = Int64((resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000)
        let rawIdentifier = [
            fileURL.standardizedFileURL.path,
            String(fileSize),
            String(modificationDate)
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(rawIdentifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func generateThumbnail(at fileURL: URL, maxPixelSize: Int) -> UIImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var resolvedImage: UIImage?
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: max(1, maxPixelSize), height: max(1, maxPixelSize)),
            scale: 1,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            _ = error
            resolvedImage = representation?.uiImage
            semaphore.signal()
        }

        semaphore.wait()
        return resolvedImage
    }
}

final class LocalEBookThumbnailExtractor {
    static let shared = LocalEBookThumbnailExtractor()

    private let extractionQueue = DispatchQueue(
        label: "YACReader.LocalEBookThumbnailExtractor",
        qos: .utility
    )

    nonisolated func thumbnail(from fileURL: URL, maxPixelSize: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            extractionQueue.async {
                let image = autoreleasepool {
                    EBookDocumentSupport.generateThumbnail(at: fileURL, maxPixelSize: maxPixelSize)
                }
                continuation.resume(returning: image)
            }
        }
    }
}
