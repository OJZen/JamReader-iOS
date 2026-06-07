import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

nonisolated final class ReaderRealCUGANCoreMLBackend: @unchecked Sendable {
    static let shared = ReaderRealCUGANCoreMLBackend()
    static let maxLowInputLongEdge = 1_024
    static let maxMediumInputLongEdge = 1_280
    static let maxHighInputLongEdge = 1_536
    static let maxUltraHighInputLongEdge = 1_792

    private let modelName = "RealCUGAN2xProConservativeTile432"
    private let inputName = "input"
    private let outputName = "output"
    private let tileInputSize = 384
    private let tileContext = 24
    private let modelInputSize = 432
    private let outputTileSize = 768
    private let scale = 2
    private let maxModelInputLongEdge = ReaderRealCUGANCoreMLBackend.maxUltraHighInputLongEdge
    private let maxModelOutputLongEdge = 3_584
    private let decoderTolerance: CGFloat = 1.10

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)
    private let modelLock = NSLock()
    private let inferenceQueue = DispatchQueue(label: "app.jamreader.realcugan.inference", qos: .userInitiated)
    private var cachedModel: MLModel?
    private var attemptedModelLoad = false

    private init() {}

    static func preferredDecodeMaxPixelSize(for modelScale: ReaderImageModelScale) -> Int? {
        switch modelScale {
        case .off:
            return nil
        case .low:
            return maxLowInputLongEdge
        case .medium:
            return maxMediumInputLongEdge
        case .high:
            return maxHighInputLongEdge
        case .ultraHigh:
            return maxUltraHighInputLongEdge
        }
    }

    func enhancedImage(
        from image: CIImage,
        context: CIContext,
        modelScale: ReaderImageModelScale,
        targetMaxPixelSize: Int
    ) -> CIImage? {
        enhancedImageResult(
            from: image,
            context: context,
            modelScale: modelScale,
            targetMaxPixelSize: targetMaxPixelSize
        ).image
    }

    func enhancedImageResult(
        from image: CIImage,
        context: CIContext,
        modelScale: ReaderImageModelScale,
        targetMaxPixelSize _: Int
    ) -> ReaderRealCUGANProcessingResult {
        guard !Task.isCancelled else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .disabled)
        }

        guard modelScale.isEnabled,
              let model = loadModel()
        else {
            let state: ReaderRealCUGANProcessingState = modelScale.isEnabled
                ? .modelUnavailable
                : .disabled
            return ReaderRealCUGANProcessingResult(image: nil, state: state)
        }

        let originalImage = image.normalizedToZeroOrigin()
        let originalMaxDimension = max(originalImage.extent.width, originalImage.extent.height)
        guard originalMaxDimension > 0 else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .failed)
        }

        let sourcePlan = preparedInitialImage(originalImage, modelScale: modelScale)
        guard let sourcePlan else {
            return ReaderRealCUGANProcessingResult(
                image: nil,
                state: .inputTooLarge(
                    inputLongEdge: Int(originalMaxDimension.rounded()),
                    maxLongEdge: maxInitialInputLongEdge(for: modelScale)
                )
            )
        }

        let outputImage = runTwoXPass(
            model: model,
            image: sourcePlan.image,
            context: context
        )

        guard let outputImage else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .disabled)
        }

        let outputLongEdge = max(outputImage.extent.width, outputImage.extent.height)
        return ReaderRealCUGANProcessingResult(
            image: outputImage,
            state: .applied(
                inputLongEdge: Int(sourcePlan.inputLongEdge.rounded()),
                outputLongEdge: Int(outputLongEdge.rounded()),
                downsampledInput: sourcePlan.downsampledInput
            )
        )
    }

    private func runTwoXPass(
        model: MLModel,
        image: CIImage,
        context: CIContext
    ) -> CIImage? {
        guard !Task.isCancelled else {
            return nil
        }

        guard canRunTwoXPass(on: image) else {
            return nil
        }

        let sourceImage = image.normalizedToZeroOrigin()
        let extent = sourceImage.extent.integral
        guard extent.width >= 16,
              extent.height >= 16,
              let cgImage = context.createCGImage(sourceImage, from: extent)
        else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let sourceBytes = rgbaBytes(from: cgImage, width: width, height: height) else {
            return nil
        }

        let outputWidth = width * scale
        let outputHeight = height * scale
        var outputBytes = [UInt8](repeating: 255, count: outputWidth * outputHeight * 4)

        return inferenceQueue.sync {
            autoreleasepool {
                guard !Task.isCancelled else {
                    return nil
                }

                guard renderTiles(
                    model: model,
                    sourceBytes: sourceBytes,
                    width: width,
                    height: height,
                    outputBytes: &outputBytes
                ) else {
                    return nil
                }

                guard !Task.isCancelled else {
                    return nil
                }

                guard let outputCGImage = makeCGImage(
                    bytes: outputBytes,
                    width: outputWidth,
                    height: outputHeight
                ) else {
                    return nil
                }

                return CIImage(cgImage: outputCGImage)
            }
        }
    }

    private func loadModel() -> MLModel? {
        modelLock.lock()
        defer {
            modelLock.unlock()
        }

        if let cachedModel {
            return cachedModel
        }

        guard !attemptedModelLoad else {
            return nil
        }

        attemptedModelLoad = true
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: compiledURL, configuration: configuration),
           isExpectedModel(model) {
            cachedModel = model
            return model
        }

        if let packageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage"),
           let compiledURL = try? MLModel.compileModel(at: packageURL),
           let model = try? MLModel(contentsOf: compiledURL, configuration: configuration),
           isExpectedModel(model) {
            cachedModel = model
            return model
        }

        return nil
    }

    private func preparedInitialImage(
        _ image: CIImage,
        modelScale: ReaderImageModelScale
    ) -> ModelInputPlan? {
        let image = image.normalizedToZeroOrigin()
        let sourceMaxDimension = max(image.extent.width, image.extent.height)
        guard sourceMaxDimension > 0 else {
            return nil
        }

        let maxInitialLongEdge = CGFloat(maxInitialInputLongEdge(for: modelScale))
        if sourceMaxDimension <= maxInitialLongEdge {
            return ModelInputPlan(
                image: image,
                inputLongEdge: sourceMaxDimension,
                downsampledInput: false
            )
        }

        guard sourceMaxDimension <= maxInitialLongEdge * decoderTolerance else {
            return nil
        }

        let resizeScale = maxInitialLongEdge / sourceMaxDimension
        let resizedImage = image.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                kCIInputScaleKey: resizeScale,
                kCIInputAspectRatioKey: 1
            ]
        )
        .normalizedToZeroOrigin()

        return ModelInputPlan(
            image: resizedImage,
            inputLongEdge: max(resizedImage.extent.width, resizedImage.extent.height),
            downsampledInput: true
        )
    }

    private func maxInitialInputLongEdge(for modelScale: ReaderImageModelScale) -> Int {
        switch modelScale {
        case .off:
            return 0
        case .low:
            return ReaderRealCUGANCoreMLBackend.maxLowInputLongEdge
        case .medium:
            return ReaderRealCUGANCoreMLBackend.maxMediumInputLongEdge
        case .high:
            return ReaderRealCUGANCoreMLBackend.maxHighInputLongEdge
        case .ultraHigh:
            return ReaderRealCUGANCoreMLBackend.maxUltraHighInputLongEdge
        }
    }

    private func canRunTwoXPass(on image: CIImage) -> Bool {
        let image = image.normalizedToZeroOrigin()
        let sourceMaxDimension = max(image.extent.width, image.extent.height)
        guard sourceMaxDimension > 0 else {
            return false
        }

        return sourceMaxDimension <= CGFloat(maxModelInputLongEdge)
            && sourceMaxDimension * CGFloat(scale) <= CGFloat(maxModelOutputLongEdge)
    }

    private func rgbaBytes(
        from cgImage: CGImage,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmapContext = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func renderTiles(
        model: MLModel,
        sourceBytes: [UInt8],
        width: Int,
        height: Int,
        outputBytes: inout [UInt8]
    ) -> Bool {
        let xTiles = stride(from: 0, to: width, by: tileInputSize)
        let yTiles = stride(from: 0, to: height, by: tileInputSize)
        guard let input = makeReusableInputArray() else {
            return false
        }

        for tileY in yTiles {
            for tileX in xTiles {
                guard !Task.isCancelled else {
                    return false
                }

                fillInputArray(
                    input,
                    sourceBytes: sourceBytes,
                    width: width,
                    height: height,
                    tileX: tileX,
                    tileY: tileY
                )

                guard let output = predict(model: model, input: input) else {
                    return false
                }

                guard !Task.isCancelled else {
                    return false
                }

                guard copyOutputTile(
                    output,
                    tileX: tileX,
                    tileY: tileY,
                    sourceWidth: width,
                    sourceHeight: height,
                    outputBytes: &outputBytes
                ) else {
                    return false
                }
            }
        }

        return true
    }

    private func makeReusableInputArray() -> MLMultiArray? {
        try? MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 3),
                NSNumber(value: modelInputSize),
                NSNumber(value: modelInputSize)
            ],
            dataType: .float32
        )
    }

    private func fillInputArray(
        _ inputArray: MLMultiArray,
        sourceBytes: [UInt8],
        width: Int,
        height: Int,
        tileX: Int,
        tileY: Int
    ) {
        let inputPointer = inputArray.dataPointer.bindMemory(
            to: Float32.self,
            capacity: inputArray.count
        )
        let channelStride = modelInputSize * modelInputSize

        for inputY in 0..<modelInputSize {
            let sourceY = clamped(tileY + inputY - tileContext, lowerBound: 0, upperBound: height - 1)
            for inputX in 0..<modelInputSize {
                let sourceX = clamped(tileX + inputX - tileContext, lowerBound: 0, upperBound: width - 1)
                let sourceOffset = (sourceY * width + sourceX) * 4
                let targetOffset = inputY * modelInputSize + inputX
                inputPointer[targetOffset] = Float32(sourceBytes[sourceOffset]) / 255
                inputPointer[channelStride + targetOffset] = Float32(sourceBytes[sourceOffset + 1]) / 255
                inputPointer[channelStride * 2 + targetOffset] = Float32(sourceBytes[sourceOffset + 2]) / 255
            }
        }
    }

    private func predict(
        model: MLModel,
        input: MLMultiArray
    ) -> MLMultiArray? {
        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: input)]
        ),
            let output = try? model.prediction(from: provider),
            let outputArray = output.featureValue(for: outputName)?.multiArrayValue
        else {
            return nil
        }

        return outputArray
    }

    private func copyOutputTile(
        _ outputArray: MLMultiArray,
        tileX: Int,
        tileY: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        outputBytes: inout [UInt8]
    ) -> Bool {
        guard isExpectedOutputArray(outputArray)
        else {
            return false
        }

        let outputWidth = sourceWidth * scale
        let validWidth = min(tileInputSize, sourceWidth - tileX) * scale
        let validHeight = min(tileInputSize, sourceHeight - tileY) * scale
        let outputPointer = outputArray.dataPointer.bindMemory(
            to: Float32.self,
            capacity: outputArray.count
        )
        let strides = outputArray.strides.map(\.intValue)
        let channelStride = strides[1]
        let rowStride = strides[2]
        let columnStride = strides[3]
        let greenBase = channelStride
        let blueBase = channelStride * 2

        for y in 0..<validHeight {
            let outputRowBase = (tileY * scale + y) * outputWidth + tileX * scale
            let modelRowBase = y * rowStride
            for x in 0..<validWidth {
                let modelOffset = modelRowBase + x * columnStride
                let destinationOffset = (outputRowBase + x) * 4
                outputBytes[destinationOffset] = byteValue(from: outputPointer[modelOffset])
                outputBytes[destinationOffset + 1] = byteValue(from: outputPointer[greenBase + modelOffset])
                outputBytes[destinationOffset + 2] = byteValue(from: outputPointer[blueBase + modelOffset])
                outputBytes[destinationOffset + 3] = 255
            }
        }

        return true
    }

    private func byteValue(from value: Float32) -> UInt8 {
        guard value.isFinite else {
            return 0
        }

        let scaledValue = Int((min(max(value, 0), 1) * 255).rounded())
        return UInt8(scaledValue)
    }

    private func isExpectedModel(_ model: MLModel) -> Bool {
        guard let inputConstraint = model.modelDescription
            .inputDescriptionsByName[inputName]?
            .multiArrayConstraint,
            let outputConstraint = model.modelDescription
            .outputDescriptionsByName[outputName]?
            .multiArrayConstraint
        else {
            return false
        }

        return inputConstraint.dataType == .float32
            && outputConstraint.dataType == .float32
            && inputConstraint.shape.map(\.intValue) == [1, 3, modelInputSize, modelInputSize]
            && outputConstraint.shape.map(\.intValue) == [1, 3, outputTileSize, outputTileSize]
    }

    private func isExpectedOutputArray(_ outputArray: MLMultiArray) -> Bool {
        outputArray.dataType == .float32
            && outputArray.shape.map(\.intValue) == [1, 3, outputTileSize, outputTileSize]
            && outputArray.strides.count >= 4
    }

    private func makeCGImage(
        bytes: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func clamped(_ value: Int, lowerBound: Int, upperBound: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}

nonisolated enum ReaderRealCUGANProcessingState: Equatable {
    case disabled
    case applied(inputLongEdge: Int, outputLongEdge: Int, downsampledInput: Bool)
    case modelUnavailable
    case inputTooLarge(inputLongEdge: Int, maxLongEdge: Int)
    case failed

    var isApplied: Bool {
        if case .applied = self {
            return true
        }
        return false
    }

    var userFacingMessage: String? {
        switch self {
        case .disabled:
            return nil
        case .applied(let inputLongEdge, let outputLongEdge, let downsampledInput):
            let resizeNote = downsampledInput ? " after resizing input" : ""
            return "AI model applied: \(inputLongEdge)p -> \(outputLongEdge)p\(resizeNote)."
        case .modelUnavailable:
            return "AI model is unavailable; using image processing fallback."
        case .inputTooLarge(let inputLongEdge, let maxLongEdge):
            return "AI model skipped: \(inputLongEdge)p input exceeds the \(maxLongEdge)p limit."
        case .failed:
            return "AI model failed; using image processing fallback."
        }
    }
}

nonisolated struct ReaderRealCUGANProcessingResult {
    let image: CIImage?
    let state: ReaderRealCUGANProcessingState
}

private struct ModelInputPlan {
    let image: CIImage
    let inputLongEdge: CGFloat
    let downsampledInput: Bool
}

nonisolated private extension CIImage {
    func normalizedToZeroOrigin() -> CIImage {
        let extent = extent.integral
        guard extent.origin != .zero else {
            return cropped(to: extent)
        }

        return cropped(to: extent)
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }
}
