import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

nonisolated final class ReaderSwinIRCoreMLBackend: @unchecked Sendable {
    static let shared = ReaderSwinIRCoreMLBackend()
    static let maxLowInputLongEdge = 224
    static let maxMediumInputLongEdge = 336
    static let maxHighInputLongEdge = 448
    static let maxUltraHighInputLongEdge = 560

    private let modelName = "SwinIRJPEG30LumaTile63NN"
    private let inputName = "input"
    private let outputName = "output"
    private let tileInputSize = 63
    private let tileOverlap = 3
    private let maxModelInputLongEdge = ReaderSwinIRCoreMLBackend.maxUltraHighInputLongEdge
    private let decoderTolerance: CGFloat = 1.10

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)
    private let modelLock = NSLock()
    private let inferenceQueue = DispatchQueue(label: "app.jamreader.swinir.inference", qos: .userInitiated)
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

    func enhancedImageResult(
        from image: CIImage,
        context: CIContext,
        modelScale: ReaderImageModelScale,
        targetMaxPixelSize _: Int
    ) -> ReaderRealCUGANProcessingResult {
        guard modelScale.isEnabled,
              let model = loadModel()
        else {
            let state: ReaderRealCUGANProcessingState = modelScale.isEnabled
                ? .modelUnavailable
                : .disabled
            #if DEBUG
            NSLog("JamReader SwinIR unavailable: scale=%@ state=%@", modelScale.rawValue, String(describing: state))
            #endif
            return ReaderRealCUGANProcessingResult(image: nil, state: state)
        }

        let originalImage = image.normalizedToZeroOrigin()
        let originalMaxDimension = max(originalImage.extent.width, originalImage.extent.height)
        guard originalMaxDimension > 0 else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .failed)
        }

        guard let sourcePlan = preparedInitialImage(originalImage, modelScale: modelScale) else {
            #if DEBUG
            NSLog(
                "JamReader SwinIR input rejected: inputLongEdge=%d maxLongEdge=%d",
                Int(originalMaxDimension.rounded()),
                maxInitialInputLongEdge(for: modelScale)
            )
            #endif
            return ReaderRealCUGANProcessingResult(
                image: nil,
                state: .inputTooLarge(
                    inputLongEdge: Int(originalMaxDimension.rounded()),
                    maxLongEdge: maxInitialInputLongEdge(for: modelScale)
                )
            )
        }

        guard let outputImage = runLumaPass(
            model: model,
            image: sourcePlan.image,
            context: context
        ) else {
            return ReaderRealCUGANProcessingResult(image: nil, state: .failed)
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

    private func runLumaPass(
        model: MLModel,
        image: CIImage,
        context: CIContext
    ) -> CIImage? {
        guard canRunPass(on: image) else {
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

        var outputBytes = sourceBytes
        return inferenceQueue.sync {
            autoreleasepool {
                guard renderTiles(
                    model: model,
                    sourceBytes: sourceBytes,
                    width: width,
                    height: height,
                    outputBytes: &outputBytes
                ) else {
                    return nil
                }

                guard let outputCGImage = makeCGImage(
                    bytes: outputBytes,
                    width: width,
                    height: height
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
            #if DEBUG
            NSLog("JamReader SwinIR using cached model: %@", modelName)
            #endif
            return cachedModel
        }

        guard !attemptedModelLoad else {
            #if DEBUG
            NSLog("JamReader SwinIR model load already failed: %@", modelName)
            #endif
            return nil
        }

        attemptedModelLoad = true
        let configuration = MLModelConfiguration()
        // The mlProgram conversion hits the MPS SDPA crash path on iPadOS.
        // Use the neuralnetwork conversion so Core ML does not fuse attention into SDPA.
        configuration.computeUnits = .cpuAndNeuralEngine

        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            do {
                let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
                guard isExpectedModel(model) else {
                    #if DEBUG
                    NSLog("JamReader SwinIR compiled model contract mismatch: %@", modelContractDescription(model))
                    #endif
                    return nil
                }

                cachedModel = model
                #if DEBUG
                NSLog("JamReader SwinIR loaded compiled model: %@", modelName)
                #endif
                return model
            } catch {
                #if DEBUG
                NSLog("JamReader SwinIR failed to load compiled model %@: %@", modelName, error.localizedDescription)
                #endif
            }
        } else {
            #if DEBUG
            NSLog("JamReader SwinIR compiled model URL missing: %@", modelName)
            #endif
        }

        if let packageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            do {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
                guard isExpectedModel(model) else {
                    #if DEBUG
                    NSLog("JamReader SwinIR package model contract mismatch: %@", modelContractDescription(model))
                    #endif
                    return nil
                }

                cachedModel = model
                #if DEBUG
                NSLog("JamReader SwinIR compiled and loaded package model: %@", modelName)
                #endif
                return model
            } catch {
                #if DEBUG
                NSLog("JamReader SwinIR failed to compile/load package model %@: %@", modelName, error.localizedDescription)
                #endif
            }
        }

        #if DEBUG
        NSLog("JamReader SwinIR failed to load expected model: %@", modelName)
        #endif
        return nil
    }

    private func preparedInitialImage(
        _ image: CIImage,
        modelScale: ReaderImageModelScale
    ) -> SwinIRModelInputPlan? {
        let image = image.normalizedToZeroOrigin()
        let sourceMaxDimension = max(image.extent.width, image.extent.height)
        guard sourceMaxDimension > 0 else {
            return nil
        }

        let maxInitialLongEdge = CGFloat(maxInitialInputLongEdge(for: modelScale))
        if sourceMaxDimension <= maxInitialLongEdge {
            return SwinIRModelInputPlan(
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

        return SwinIRModelInputPlan(
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
            return ReaderSwinIRCoreMLBackend.maxLowInputLongEdge
        case .medium:
            return ReaderSwinIRCoreMLBackend.maxMediumInputLongEdge
        case .high:
            return ReaderSwinIRCoreMLBackend.maxHighInputLongEdge
        case .ultraHigh:
            return ReaderSwinIRCoreMLBackend.maxUltraHighInputLongEdge
        }
    }

    private func canRunPass(on image: CIImage) -> Bool {
        let image = image.normalizedToZeroOrigin()
        let sourceMaxDimension = max(image.extent.width, image.extent.height)
        return sourceMaxDimension > 0 && sourceMaxDimension <= CGFloat(maxModelInputLongEdge)
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
        let xTiles = tileStarts(for: width)
        let yTiles = tileStarts(for: height)
        guard let input = makeReusableInputArray() else {
            return false
        }

        #if DEBUG
        let tileCount = xTiles.count * yTiles.count
        var tileIndex = 0
        NSLog("JamReader SwinIR starting luma pass: %dx%d, tiles=%d", width, height, tileCount)
        #endif

        let pixelCount = width * height
        var deltaSums = [Float32](repeating: 0, count: pixelCount)
        var weightSums = [Float32](repeating: 0, count: pixelCount)

        for tileY in yTiles {
            for tileX in xTiles {
                guard !Task.isCancelled else {
                    return false
                }

                #if DEBUG
                tileIndex += 1
                let tileStart = DispatchTime.now().uptimeNanoseconds
                #endif

                fillInputArray(
                    input,
                    sourceBytes: sourceBytes,
                    width: width,
                    height: height,
                    tileX: tileX,
                    tileY: tileY
                )

                guard let output = predict(model: model, input: input),
                      accumulateOutputTile(
                        output,
                        sourceBytes: sourceBytes,
                        tileX: tileX,
                        tileY: tileY,
                        sourceWidth: width,
                        sourceHeight: height,
                        deltaSums: &deltaSums,
                        weightSums: &weightSums
                      )
                else {
                    return false
                }

                #if DEBUG
                let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - tileStart) / 1_000_000
                if tileIndex == 1 || tileIndex == tileCount || tileIndex.isMultiple(of: 4) {
                    NSLog(
                        "JamReader SwinIR finished tile %d/%d in %.1f ms",
                        tileIndex,
                        tileCount,
                        elapsedMilliseconds
                    )
                }
                #endif
            }
        }

        applyAccumulatedDeltas(
            sourceBytes: sourceBytes,
            deltaSums: deltaSums,
            weightSums: weightSums,
            outputBytes: &outputBytes
        )
        #if DEBUG
        NSLog("JamReader SwinIR finished luma pass")
        #endif
        return true
    }

    private func makeReusableInputArray() -> MLMultiArray? {
        try? MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 1),
                NSNumber(value: tileInputSize),
                NSNumber(value: tileInputSize)
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

        for inputY in 0..<tileInputSize {
            let sourceY = clamped(tileY + inputY, lowerBound: 0, upperBound: height - 1)
            for inputX in 0..<tileInputSize {
                let sourceX = clamped(tileX + inputX, lowerBound: 0, upperBound: width - 1)
                let sourceOffset = (sourceY * width + sourceX) * 4
                let targetOffset = inputY * tileInputSize + inputX
                inputPointer[targetOffset] = lumaValue(
                    red: sourceBytes[sourceOffset],
                    green: sourceBytes[sourceOffset + 1],
                    blue: sourceBytes[sourceOffset + 2]
                )
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

    private func accumulateOutputTile(
        _ outputArray: MLMultiArray,
        sourceBytes: [UInt8],
        tileX: Int,
        tileY: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        deltaSums: inout [Float32],
        weightSums: inout [Float32]
    ) -> Bool {
        guard isExpectedOutputArray(outputArray) else {
            return false
        }

        let validWidth = min(tileInputSize, sourceWidth - tileX)
        let validHeight = min(tileInputSize, sourceHeight - tileY)
        let outputPointer = outputArray.dataPointer.bindMemory(
            to: Float32.self,
            capacity: outputArray.count
        )
        let strides = outputArray.strides.map(\.intValue)

        for y in 0..<validHeight {
            for x in 0..<validWidth {
                let destinationX = tileX + x
                let destinationY = tileY + y
                let destinationIndex = destinationY * sourceWidth + destinationX
                let destinationOffset = destinationIndex * 4
                let sourceLuma = lumaValue(
                    red: sourceBytes[destinationOffset],
                    green: sourceBytes[destinationOffset + 1],
                    blue: sourceBytes[destinationOffset + 2]
                )
                let enhancedLuma = outputValue(outputPointer, strides: strides, x: x, y: y)
                let delta = (enhancedLuma - sourceLuma) * 255
                let weight = axisBlendWeight(
                    position: x,
                    validLength: validWidth,
                    tileStart: tileX,
                    imageLength: sourceWidth
                ) * axisBlendWeight(
                    position: y,
                    validLength: validHeight,
                    tileStart: tileY,
                    imageLength: sourceHeight
                )

                deltaSums[destinationIndex] += delta * weight
                weightSums[destinationIndex] += weight
            }
        }

        return true
    }

    private func lumaValue(red: UInt8, green: UInt8, blue: UInt8) -> Float32 {
        let y = 16 + (
            65.481 * Float32(red)
                + 128.553 * Float32(green)
                + 24.966 * Float32(blue)
        ) / 255
        return min(max(y / 255, 0), 1)
    }

    private func applyAccumulatedDeltas(
        sourceBytes: [UInt8],
        deltaSums: [Float32],
        weightSums: [Float32],
        outputBytes: inout [UInt8]
    ) {
        for pixelIndex in 0..<weightSums.count {
            let weight = weightSums[pixelIndex]
            guard weight > 0 else {
                continue
            }

            let delta = deltaSums[pixelIndex] / weight
            let sourceOffset = pixelIndex * 4
            outputBytes[sourceOffset] = adjustedChannel(sourceBytes[sourceOffset], delta: delta)
            outputBytes[sourceOffset + 1] = adjustedChannel(sourceBytes[sourceOffset + 1], delta: delta)
            outputBytes[sourceOffset + 2] = adjustedChannel(sourceBytes[sourceOffset + 2], delta: delta)
            outputBytes[sourceOffset + 3] = sourceBytes[sourceOffset + 3]
        }
    }

    private func tileStarts(for length: Int) -> [Int] {
        guard length > tileInputSize else {
            return [0]
        }

        let tileStride = max(1, tileInputSize - tileOverlap * 2)
        var starts = [0]
        var nextStart = tileStride
        while nextStart + tileInputSize < length {
            starts.append(nextStart)
            nextStart += tileStride
        }

        let finalStart = length - tileInputSize
        if starts.last != finalStart {
            starts.append(finalStart)
        }

        return starts
    }

    private func axisBlendWeight(
        position: Int,
        validLength: Int,
        tileStart: Int,
        imageLength: Int
    ) -> Float32 {
        let isLeadingImageEdge = tileStart == 0
        let isTrailingImageEdge = tileStart + validLength >= imageLength
        var weight: Float32 = 1

        if !isLeadingImageEdge && position < tileOverlap {
            weight = min(weight, Float32(position + 1) / Float32(tileOverlap + 1))
        }

        if !isTrailingImageEdge && position >= validLength - tileOverlap {
            weight = min(weight, Float32(validLength - position) / Float32(tileOverlap + 1))
        }

        return max(weight, 0.001)
    }

    private func adjustedChannel(_ value: UInt8, delta: Float32) -> UInt8 {
        UInt8(clamping: Int((Float32(value) + delta).rounded()))
    }

    private func outputValue(
        _ pointer: UnsafeMutablePointer<Float32>,
        strides: [Int],
        x: Int,
        y: Int
    ) -> Float32 {
        let index = strides[2] * y + strides[3] * x
        let value = pointer[index]
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
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

        let expectedShape = [1, 1, tileInputSize, tileInputSize]
        let outputShape = outputConstraint.shape.map(\.intValue)
        return inputConstraint.dataType == .float32
            && outputConstraint.dataType == .float32
            && inputConstraint.shape.map(\.intValue) == expectedShape
            && (outputShape.isEmpty || outputShape == expectedShape)
    }

    private func modelContractDescription(_ model: MLModel) -> String {
        let inputDescription = model.modelDescription.inputDescriptionsByName[inputName]
        let outputDescription = model.modelDescription.outputDescriptionsByName[outputName]
        let inputConstraint = inputDescription?.multiArrayConstraint
        let outputConstraint = outputDescription?.multiArrayConstraint

        return [
            "inputNames=\(Array(model.modelDescription.inputDescriptionsByName.keys).sorted())",
            "outputNames=\(Array(model.modelDescription.outputDescriptionsByName.keys).sorted())",
            "inputType=\(String(describing: inputDescription?.type))",
            "outputType=\(String(describing: outputDescription?.type))",
            "inputDataType=\(String(describing: inputConstraint?.dataType))",
            "outputDataType=\(String(describing: outputConstraint?.dataType))",
            "inputShape=\(String(describing: inputConstraint?.shape.map(\.intValue)))",
            "outputShape=\(String(describing: outputConstraint?.shape.map(\.intValue)))"
        ].joined(separator: " ")
    }

    private func isExpectedOutputArray(_ outputArray: MLMultiArray) -> Bool {
        outputArray.dataType == .float32
            && outputArray.shape.map(\.intValue) == [1, 1, tileInputSize, tileInputSize]
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

nonisolated private struct SwinIRModelInputPlan {
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
