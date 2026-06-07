import Combine
import SwiftUI
import UIKit

struct ReaderImageEnhancementSheet: View {
    let document: ImageSequenceComicDocument
    let pageIndex: Int
    let currentSettings: ReaderImageEnhancementSettings
    let onCancel: () -> Void
    let onApply: (ReaderImageEnhancementSettings) -> Void

    @StateObject private var previewLoader = ReaderImageEnhancementPreviewLoader()
    @State private var draftSettings: ReaderImageEnhancementSettings
    @State private var comparisonPosition: CGFloat = 0.5

    init(
        document: ImageSequenceComicDocument,
        pageIndex: Int,
        currentSettings: ReaderImageEnhancementSettings,
        onCancel: @escaping () -> Void,
        onApply: @escaping (ReaderImageEnhancementSettings) -> Void
    ) {
        self.document = document
        self.pageIndex = pageIndex
        self.currentSettings = currentSettings
        self.onCancel = onCancel
        self.onApply = onApply
        _draftSettings = State(initialValue: currentSettings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    settingsPanel
                    previewContent
                }
                .padding(Spacing.lg)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Image Enhancement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draftSettings)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .adaptiveSheetWidth(680)
        .presentationBackground(Color.surfaceGrouped)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: previewRequestID) {
            await previewLoader.load(
                document: document,
                pageIndex: pageIndex,
                settings: draftSettings
            )
        }
        .onDisappear {
            previewLoader.cancel()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch previewLoader.phase {
        case .idle, .loading:
            ReaderImageEnhancementPreviewPlaceholder()
        case .loaded(let original, let enhanced, _, let processingNanoseconds):
            ReaderImageEnhancementComparisonView(
                originalImage: original,
                enhancedImage: enhanced,
                processingNanoseconds: processingNanoseconds,
                splitPosition: $comparisonPosition
            )
        case .failed(let message):
            ReaderImageEnhancementPreviewFailure(message: message)
        }
    }

    private var previewRequestID: String {
        "\(document.url.path)#\(pageIndex)#\(draftSettings.cacheKey)"
    }

    private var settingsPanel: some View {
        VStack(spacing: Spacing.md) {
            ReaderImageEnhancementLevelPicker(
                selection: Binding(
                    get: { draftSettings.level },
                    set: { draftSettings.level = $0 }
                )
            )

            ReaderImageModelBackendPicker(
                selection: Binding(
                    get: { draftSettings.modelBackend },
                    set: { draftSettings.modelBackend = $0 }
                )
            )

            ReaderImageModelScalePicker(
                selection: Binding(
                    get: { draftSettings.modelScale },
                    set: { draftSettings.modelScale = $0 }
                )
            )

            if let modelStatusMessage {
                ReaderImageModelStatusView(
                    message: modelStatusMessage.text,
                    isWarning: modelStatusMessage.isWarning
                )
            }

            Toggle(
                isOn: Binding(
                    get: { draftSettings.appliesPerspectiveCorrection },
                    set: { draftSettings.appliesPerspectiveCorrection = $0 }
                )
            ) {
                Label("Perspective Crop", systemImage: "crop.rotate")
            }
            .font(AppFont.subheadline(.medium))
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var modelStatusMessage: (text: String, isWarning: Bool)? {
        guard draftSettings.modelScale.isEnabled else {
            return nil
        }

        switch previewLoader.phase {
        case .idle, .loading:
            return ("Preparing \(draftSettings.modelBackend.title) preview...", false)
        case .loaded(_, _, let modelState, _):
            guard let message = modelState.userFacingMessage else {
                return nil
            }
            return (message, !modelState.isApplied)
        case .failed:
            return ("\(draftSettings.modelBackend.title) preview could not be prepared.", true)
        }
    }
}

private struct ReaderImageEnhancementLevelPicker: View {
    @Binding var selection: ReaderImageEnhancementLevel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Image Processing")
                .font(AppFont.caption(.semibold))
                .foregroundStyle(.secondary)

            Picker("Image Processing", selection: $selection) {
                ForEach(ReaderImageEnhancementLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ReaderImageModelBackendPicker: View {
    @Binding var selection: ReaderImageModelBackend

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("AI Model")
                .font(AppFont.caption(.semibold))
                .foregroundStyle(.secondary)

            Picker("AI Model", selection: $selection) {
                ForEach(ReaderImageModelBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ReaderImageModelScalePicker: View {
    @Binding var selection: ReaderImageModelScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Model Processing")
                .font(AppFont.caption(.semibold))
                .foregroundStyle(.secondary)

            Picker("Model Processing", selection: $selection) {
                ForEach(ReaderImageModelScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ReaderImageModelStatusView: View {
    let message: String
    let isWarning: Bool

    var body: some View {
        Label(message, systemImage: isWarning ? "exclamationmark.triangle" : "checkmark.circle")
            .font(AppFont.caption(.medium))
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
    }
}

private struct ReaderImageEnhancementComparisonView: View {
    let originalImage: UIImage
    let enhancedImage: UIImage
    let processingNanoseconds: UInt64
    @Binding var splitPosition: CGFloat

    private var aspectRatio: CGFloat {
        let size = originalImage.size
        guard size.width > 0, size.height > 0 else {
            return 0.72
        }
        return size.width / size.height
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                imageLayer(originalImage)

                imageLayer(enhancedImage)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(proxy.size.width * splitPosition, 0))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                comparisonHandle(in: proxy.size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(proxy.size.width, 1)
                        splitPosition = min(max(value.location.x / width, 0), 1)
                    }
            )
            .overlay(alignment: .topTrailing) {
                ReaderImageProcessingTimeBadge(nanoseconds: processingNanoseconds)
                    .padding(Spacing.sm)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }

    private func imageLayer(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    private func comparisonHandle(in size: CGSize) -> some View {
        let xOffset = max(size.width * splitPosition - 1, 0)

        return ZStack {
            Rectangle()
                .fill(.white.opacity(0.92))
                .frame(width: 2)
                .shadow(color: .black.opacity(0.35), radius: 5)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 44, height: 44)
                .overlay {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.36), lineWidth: 1)
                }
        }
        .frame(width: 44, height: max(size.height, 1))
        .offset(x: xOffset - 21)
    }
}

private struct ReaderImageProcessingTimeBadge: View {
    let nanoseconds: UInt64

    private var durationText: String {
        ReaderPerformanceTrace.format(nanoseconds: nanoseconds)
    }

    var body: some View {
        Label("Processed in \(durationText) ms", systemImage: "timer")
            .font(AppFont.caption(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.black.opacity(0.56), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct ReaderImageEnhancementPreviewPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .aspectRatio(0.72, contentMode: .fit)
            .overlay {
                VStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Preparing Preview")
                        .font(AppFont.subheadline(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
    }
}

private struct ReaderImageEnhancementPreviewFailure: View {
    let message: String

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .aspectRatio(0.72, contentMode: .fit)
            .overlay {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3.weight(.semibold))
                    Text(message)
                        .font(AppFont.subheadline(.medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(Spacing.lg)
            }
    }
}

@MainActor
private final class ReaderImageEnhancementPreviewLoader: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(
            original: UIImage,
            enhanced: UIImage,
            modelState: ReaderRealCUGANProcessingState,
            processingNanoseconds: UInt64
        )
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var loadTask: Task<Void, Never>?
    private var workerTask: Task<Result<(UIImage, UIImage, ReaderRealCUGANProcessingState, UInt64), Error>, Never>?
    private var requestID: String?

    deinit {
        loadTask?.cancel()
        workerTask?.cancel()
    }

    func load(
        document: ImageSequenceComicDocument,
        pageIndex: Int,
        settings: ReaderImageEnhancementSettings
    ) async {
        loadTask?.cancel()
        workerTask?.cancel()

        let pageName = document.pageName(at: pageIndex) ?? "Page \(pageIndex + 1)"
        let requestID = "\(document.url.path)#\(pageIndex)#\(pageName)#\(settings.cacheKey)"
        guard self.requestID != requestID || !phase.isLoaded else {
            return
        }

        self.requestID = requestID
        phase = .loading

        let pageSource = document.pageSource
        let workerTask = Task.detached(priority: .userInitiated) {
            do {
                #if DEBUG
                NSLog(
                    "JamReader enhancement preview request: backend=%@ scale=%@ level=%@ perspective=%d",
                    settings.modelBackend.rawValue,
                    settings.modelScale.rawValue,
                    settings.level.rawValue,
                    settings.appliesPerspectiveCorrection ? 1 : 0
                )
                #endif
                let data = try await pageSource.dataForPage(at: pageIndex)
                try Task.checkCancellation()

                let previewMaxPixelSize = settings.preferredDecodeMaxPixelSize ?? 1_400
                guard let originalImage = ReaderImageDecoder.decodeImage(
                    from: data,
                    maxPixelSize: previewMaxPixelSize
                ) else {
                    throw ReaderImageEnhancementPreviewError.decodeFailed
                }

                #if DEBUG
                let decodedPixelWidth = Int((originalImage.size.width * originalImage.scale).rounded())
                let decodedPixelHeight = Int((originalImage.size.height * originalImage.scale).rounded())
                NSLog(
                    "JamReader enhancement preview decoded: %dx%d maxPixelSize=%d",
                    decodedPixelWidth,
                    decodedPixelHeight,
                    previewMaxPixelSize
                )
                #endif
                try Task.checkCancellation()

                let processingStart = DispatchTime.now().uptimeNanoseconds
                let result = await ReaderImageEnhancementPipeline.shared.previewEnhancedImage(
                    from: originalImage,
                    settings: settings,
                    targetMaxPixelSize: 1_800,
                    priority: .userInitiated
                )
                let processingNanoseconds = DispatchTime.now().uptimeNanoseconds - processingStart

                try Task.checkCancellation()

                return Result<(UIImage, UIImage, ReaderRealCUGANProcessingState, UInt64), Error>.success((
                    originalImage,
                    result.image,
                    result.modelState,
                    processingNanoseconds
                ))
            } catch {
                return Result<(UIImage, UIImage, ReaderRealCUGANProcessingState, UInt64), Error>.failure(error)
            }
        }

        self.workerTask = workerTask
        loadTask = Task(priority: .userInitiated) { [weak self] in
            let result = await workerTask.value

            guard let self, !Task.isCancelled, self.requestID == requestID else {
                return
            }

            self.workerTask = nil
            switch result {
            case .success(let images):
                #if DEBUG
                NSLog("JamReader enhancement preview loaded in %.1f ms", Double(images.3) / 1_000_000)
                #endif
                self.phase = .loaded(
                    original: images.0,
                    enhanced: images.1,
                    modelState: images.2,
                    processingNanoseconds: images.3
                )
            case .failure(let error):
                if error is CancellationError {
                    return
                }

                #if DEBUG
                NSLog("JamReader enhancement preview failed: %@", error.userFacingMessage)
                #endif
                self.phase = .failed(error.userFacingMessage)
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        workerTask?.cancel()
        loadTask = nil
        workerTask = nil
    }
}

private extension ReaderImageEnhancementPreviewLoader.Phase {
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

private enum ReaderImageEnhancementPreviewError: LocalizedError {
    case decodeFailed

    var errorDescription: String? {
        "The current page could not be decoded."
    }
}
