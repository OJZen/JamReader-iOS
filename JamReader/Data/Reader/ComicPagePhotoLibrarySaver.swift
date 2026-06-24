import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum ComicPagePhotoLibrarySaverError: LocalizedError {
    case accessDenied
    case unsupportedImageData
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "JamReader does not have permission to add images to Photos."
        case .unsupportedImageData:
            return "This page could not be converted into a Photos-compatible image."
        case .saveFailed:
            return "The page could not be saved to Photos."
        }
    }
}

enum ComicPagePhotoLibrarySaver {
    static func savePageImageData(_ data: Data, suggestedFileName: String?) async throws {
        try await requestAddOnlyAccessIfNeeded()

        do {
            try await savePhotoResource(
                data,
                suggestedFileName: suggestedFileName,
                uniformTypeIdentifier: uniformTypeIdentifier(for: data, suggestedFileName: suggestedFileName)
            )
        } catch {
            let pngData = try convertedPNGData(from: data)
            try await savePhotoResource(
                pngData,
                suggestedFileName: pngFileName(from: suggestedFileName),
                uniformTypeIdentifier: UTType.png.identifier
            )
        }
    }

    private static func requestAddOnlyAccessIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let requestedStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw ComicPagePhotoLibrarySaverError.accessDenied
            }
        case .denied, .restricted:
            throw ComicPagePhotoLibrarySaverError.accessDenied
        @unknown default:
            throw ComicPagePhotoLibrarySaverError.accessDenied
        }
    }

    private static func savePhotoResource(
        _ data: Data,
        suggestedFileName: String?,
        uniformTypeIdentifier: String?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = sanitizedFileName(from: suggestedFileName)
                options.uniformTypeIdentifier = uniformTypeIdentifier
                request.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? ComicPagePhotoLibrarySaverError.saveFailed)
                }
            }
        }
    }

    private static func convertedPNGData(from data: Data) throws -> Data {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw ComicPagePhotoLibrarySaverError.unsupportedImageData
        }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw ComicPagePhotoLibrarySaverError.unsupportedImageData
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ComicPagePhotoLibrarySaverError.unsupportedImageData
        }

        return output as Data
    }

    private static func uniformTypeIdentifier(for data: Data, suggestedFileName: String?) -> String? {
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(imageSource) {
            return type as String
        }

        guard let fileExtension = suggestedFileName?.split(separator: ".").last else {
            return nil
        }

        return UTType(filenameExtension: String(fileExtension))?.identifier
    }

    private static func sanitizedFileName(from suggestedFileName: String?) -> String {
        let trimmedName = suggestedFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        guard let trimmedName, !trimmedName.isEmpty else {
            return "JamReader Page.png"
        }

        return trimmedName
    }

    private static func pngFileName(from suggestedFileName: String?) -> String {
        let sanitized = sanitizedFileName(from: suggestedFileName)
        let baseName = URL(fileURLWithPath: sanitized).deletingPathExtension().lastPathComponent
        return "\(baseName.isEmpty ? "JamReader Page" : baseName).png"
    }
}
