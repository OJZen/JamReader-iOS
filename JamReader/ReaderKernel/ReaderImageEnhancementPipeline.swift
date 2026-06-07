import CoreImage
import UIKit
import Vision

actor ReaderImageEnhancementPipeline {
    static let shared = ReaderImageEnhancementPipeline()

    private let memoryCache: NSCache<NSString, UIImage>
    private let pageCache = ReaderPageCache.shared
    private var inFlightTasks: [String: Task<ReaderImageEnhancementProcessingResult?, Never>] = [:]

    private init() {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 18
        cache.totalCostLimit = 160 * 1_024 * 1_024
        self.memoryCache = cache
    }

    func enhancedImage(
        from sourceImage: UIImage,
        documentURL: URL,
        pageIndex: Int,
        pageName: String,
        settings: ReaderImageEnhancementSettings,
        targetMaxPixelSize: Int,
        priority: TaskPriority
    ) async -> UIImage {
        let result = await enhancedImageResult(
            from: sourceImage,
            documentURL: documentURL,
            pageIndex: pageIndex,
            pageName: pageName,
            settings: settings,
            targetMaxPixelSize: targetMaxPixelSize,
            priority: priority,
            usesPersistentCache: true
        )

        return result?.image ?? sourceImage
    }

    func previewEnhancedImage(
        from sourceImage: UIImage,
        settings: ReaderImageEnhancementSettings,
        targetMaxPixelSize: Int,
        priority: TaskPriority
    ) async -> ReaderImageEnhancementProcessingResult {
        await enhancedImageResult(
            from: sourceImage,
            documentURL: URL(fileURLWithPath: "/preview"),
            pageIndex: 0,
            pageName: "Preview",
            settings: settings,
            targetMaxPixelSize: targetMaxPixelSize,
            priority: priority,
            usesPersistentCache: false
        ) ?? ReaderImageEnhancementProcessingResult(
            image: sourceImage,
            modelState: .disabled
        )
    }

    private func enhancedImageResult(
        from sourceImage: UIImage,
        documentURL: URL,
        pageIndex: Int,
        pageName: String,
        settings: ReaderImageEnhancementSettings,
        targetMaxPixelSize: Int,
        priority: TaskPriority,
        usesPersistentCache: Bool
    ) async -> ReaderImageEnhancementProcessingResult? {
        guard settings.isEnabled else {
            return ReaderImageEnhancementProcessingResult(
                image: sourceImage,
                modelState: .disabled
            )
        }

        let namespace = ReaderImageEnhancementNamespace.namespace(
            documentURL: documentURL,
            settings: settings
        )
        let pageIdentifier = "\(pageIndex)-\(pageName)-\(targetMaxPixelSize)-\(settings.cacheKey)"
        let cacheKey = "\(namespace)#\(pageIdentifier)"
        let nsCacheKey = cacheKey as NSString

        if usesPersistentCache,
           let cachedImage = memoryCache.object(forKey: nsCacheKey) {
            return ReaderImageEnhancementProcessingResult(
                image: cachedImage,
                modelState: .disabled
            )
        }

        let diskCacheKey = ReaderPageCacheKey(
            namespace: namespace,
            pageIdentifier: pageIdentifier
        )
        if usesPersistentCache,
           let cachedData = await pageCache.data(for: diskCacheKey),
           let cachedImage = UIImage(data: cachedData) {
            memoryCache.setObject(
                cachedImage,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: cachedImage)
            )
            return ReaderImageEnhancementProcessingResult(
                image: cachedImage,
                modelState: .disabled
            )
        }

        if usesPersistentCache,
           let existingTask = inFlightTasks[cacheKey],
           let result = await existingTask.value {
            return result
        }

        let task: Task<ReaderImageEnhancementProcessingResult?, Never>?
        if usesPersistentCache {
            task = Task.detached(priority: priority) {
                Self.processImageResult(
                    sourceImage,
                    settings: settings,
                    targetMaxPixelSize: targetMaxPixelSize
                )
            }
            inFlightTasks[cacheKey] = task
        } else {
            task = nil
        }

        let processedImage: ReaderImageEnhancementProcessingResult?
        if let task {
            processedImage = await task.value
        } else {
            processedImage = Self.processImageResult(
                sourceImage,
                settings: settings,
                targetMaxPixelSize: targetMaxPixelSize
            )
        }
        if usesPersistentCache {
            inFlightTasks[cacheKey] = nil
        }

        guard let processedImage else {
            return nil
        }

        if usesPersistentCache {
            memoryCache.setObject(
                processedImage.image,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: processedImage.image)
            )

            if let data = processedImage.image.jpegData(compressionQuality: 0.94) {
                await pageCache.store(data, for: diskCacheKey)
            }
        }

        return processedImage
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
    }

    nonisolated private static func processImageResult(
        _ sourceImage: UIImage,
        settings: ReaderImageEnhancementSettings,
        targetMaxPixelSize: Int
    ) -> ReaderImageEnhancementProcessingResult? {
        guard !Task.isCancelled else {
            return nil
        }

        let normalizedImage = sourceImage.normalizedForReaderProcessing()
        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        let context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])

        var image = CIImage(cgImage: cgImage)
        var modelState: ReaderRealCUGANProcessingState = settings.modelScale.isEnabled
            ? .modelUnavailable
            : .disabled

        #if DEBUG
        let sourceWidth = Int((normalizedImage.size.width * normalizedImage.scale).rounded())
        let sourceHeight = Int((normalizedImage.size.height * normalizedImage.scale).rounded())
        NSLog(
            "JamReader enhancement pipeline start: %dx%d backend=%@ scale=%@ level=%@ target=%d",
            sourceWidth,
            sourceHeight,
            settings.modelBackend.rawValue,
            settings.modelScale.rawValue,
            settings.level.rawValue,
            targetMaxPixelSize
        )
        #endif

        if settings.appliesPerspectiveCorrection,
           let correctedImage = perspectiveCorrectedImage(from: image, cgImage: cgImage) {
            image = correctedImage
        }

        guard !Task.isCancelled else {
            return nil
        }

        if settings.modelScale.isEnabled {
            let modelResult = aiModelEnhancedImageIfAvailable(
                image,
                context: context,
                settings: settings,
                targetMaxPixelSize: targetMaxPixelSize
            )
            modelState = modelResult.state

            if let modelImage = modelResult.image {
                image = applyScanCleanup(to: modelImage, level: settings.level)
            } else {
                image = applyScanCleanup(to: image, level: settings.level)
                image = applyUpscaleIfNeeded(
                    to: image,
                    level: settings.level,
                    targetMaxPixelSize: targetMaxPixelSize
                )
            }
        } else {
            image = applyScanCleanup(to: image, level: settings.level)
            image = applyUpscaleIfNeeded(
                to: image,
                level: settings.level,
                targetMaxPixelSize: targetMaxPixelSize
            )
        }

        guard !Task.isCancelled else {
            return nil
        }

        let outputExtent = image.extent.integral
        guard let outputCGImage = context.createCGImage(image, from: outputExtent) else {
            return nil
        }

        return ReaderImageEnhancementProcessingResult(
            image: UIImage(cgImage: outputCGImage),
            modelState: modelState
        )
    }

    nonisolated private static func applyScanCleanup(
        to image: CIImage,
        level: ReaderImageEnhancementLevel
    ) -> CIImage {
        let profile = CleanupProfile(level: level)
        var output = image

        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: profile.saturation,
                kCIInputContrastKey: profile.contrast,
                kCIInputBrightnessKey: profile.brightness
            ]
        )

        if profile.exposure != 0 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: profile.exposure]
            )
        }

        if profile.noiseLevel > 0 {
            output = output.applyingFilter(
                "CINoiseReduction",
                parameters: [
                    "inputNoiseLevel": profile.noiseLevel,
                    "inputSharpness": profile.noiseSharpness
                ]
            )
        }

        output = output.applyingFilter(
            "CIUnsharpMask",
            parameters: [
                kCIInputRadiusKey: profile.unsharpRadius,
                kCIInputIntensityKey: profile.unsharpIntensity
            ]
        )

        return output
    }

    nonisolated private static func applyUpscaleIfNeeded(
        to image: CIImage,
        level: ReaderImageEnhancementLevel,
        targetMaxPixelSize: Int
    ) -> CIImage {
        let desiredScale: CGFloat
        switch level {
        case .off, .clean:
            desiredScale = 1
        case .crisp:
            desiredScale = 1.15
        case .hd:
            desiredScale = 1.75
        }

        guard desiredScale > 1 else {
            return image
        }

        let currentMaxDimension = max(image.extent.width, image.extent.height)
        guard currentMaxDimension > 0 else {
            return image
        }

        let cappedMaxDimension = CGFloat(max(1, min(targetMaxPixelSize, 8_192)))
        let scale = min(desiredScale, cappedMaxDimension / currentMaxDimension)
        guard scale > 1.01 else {
            return image
        }

        return image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1
            ]
        )
    }

    nonisolated private static func perspectiveCorrectedImage(
        from image: CIImage,
        cgImage: CGImage
    ) -> CIImage? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.72
        request.minimumSize = 0.62
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 2.4
        request.quadratureTolerance = 22

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first,
              observation.confidence >= 0.72,
              isReasonablePageRectangle(observation.boundingBox)
        else {
            return nil
        }

        let extent = image.extent
        func vector(from point: CGPoint) -> CIVector {
            CIVector(
                x: extent.minX + point.x * extent.width,
                y: extent.minY + point.y * extent.height
            )
        }

        return image.applyingFilter(
            "CIPerspectiveCorrection",
            parameters: [
                "inputTopLeft": vector(from: observation.topLeft),
                "inputTopRight": vector(from: observation.topRight),
                "inputBottomLeft": vector(from: observation.bottomLeft),
                "inputBottomRight": vector(from: observation.bottomRight)
            ]
        )
    }

    nonisolated private static func isReasonablePageRectangle(_ boundingBox: CGRect) -> Bool {
        let area = boundingBox.width * boundingBox.height
        return area >= 0.42 && area <= 0.995
    }

    nonisolated private static func aiModelEnhancedImageIfAvailable(
        _ image: CIImage,
        context: CIContext,
        settings: ReaderImageEnhancementSettings,
        targetMaxPixelSize: Int
    ) -> ReaderRealCUGANProcessingResult {
        guard settings.modelScale.isEnabled else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .disabled)
        }

        #if DEBUG
        NSLog(
            "JamReader enhancement model dispatch: backend=%@ scale=%@ inputLongEdge=%d",
            settings.modelBackend.rawValue,
            settings.modelScale.rawValue,
            Int(max(image.extent.width, image.extent.height).rounded())
        )
        #endif
        switch settings.modelBackend {
        case .realCUGAN:
            return ReaderRealCUGANCoreMLBackend.shared.enhancedImageResult(
                from: image,
                context: context,
                modelScale: settings.modelScale,
                targetMaxPixelSize: targetMaxPixelSize
            )
        }
    }

    nonisolated private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return max(1, Int(width * height * 4))
    }
}

nonisolated struct ReaderImageEnhancementProcessingResult {
    let image: UIImage
    let modelState: ReaderRealCUGANProcessingState
}

nonisolated private struct CleanupProfile {
    let saturation: CGFloat
    let contrast: CGFloat
    let brightness: CGFloat
    let exposure: CGFloat
    let noiseLevel: CGFloat
    let noiseSharpness: CGFloat
    let unsharpRadius: CGFloat
    let unsharpIntensity: CGFloat

    init(level: ReaderImageEnhancementLevel) {
        switch level {
        case .off:
            saturation = 1
            contrast = 1
            brightness = 0
            exposure = 0
            noiseLevel = 0
            noiseSharpness = 0.4
            unsharpRadius = 1
            unsharpIntensity = 0
        case .clean:
            saturation = 1
            contrast = 1.04
            brightness = 0
            exposure = 0
            noiseLevel = 0
            noiseSharpness = 0.42
            unsharpRadius = 0.9
            unsharpIntensity = 0.18
        case .crisp:
            saturation = 1
            contrast = 1.08
            brightness = 0
            exposure = 0
            noiseLevel = 0.006
            noiseSharpness = 0.45
            unsharpRadius = 1.1
            unsharpIntensity = 0.28
        case .hd:
            saturation = 1
            contrast = 1.03
            brightness = 0
            exposure = 0
            noiseLevel = 0
            noiseSharpness = 0.45
            unsharpRadius = 1.0
            unsharpIntensity = 0.22
        }
    }
}
