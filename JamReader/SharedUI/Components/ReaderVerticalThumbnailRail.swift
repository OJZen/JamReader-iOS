import Combine
import SwiftUI
import UIKit

struct ReaderVerticalThumbnailRail: View {
    let document: ComicDocument
    let currentPage: Int
    let pageCount: Int
    let viewportSize: CGSize
    let safeAreaInsets: EdgeInsets
    let onPageSelected: (Int) -> Void
    let onInteractionChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var coordinator: ReaderVerticalThumbnailRailCoordinator
    @StateObject private var previewCoordinator = ReaderVerticalRailPreviewCoordinator()

    init(
        document: ComicDocument,
        currentPage: Int,
        pageCount: Int,
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        onPageSelected: @escaping (Int) -> Void,
        onInteractionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.document = document
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.viewportSize = viewportSize
        self.safeAreaInsets = safeAreaInsets
        self.onPageSelected = onPageSelected
        self.onInteractionChanged = onInteractionChanged

        let initialPageIndex = max(min(currentPage - 1, max(pageCount - 1, 0)), 0)
        _coordinator = StateObject(
            wrappedValue: ReaderVerticalThumbnailRailCoordinator(
                initialPageIndex: initialPageIndex
            )
        )
    }

    var body: some View {
        let layout = ReaderVerticalThumbnailRailLayout.adaptive(
            viewportSize: viewportSize,
            safeAreaInsets: safeAreaInsets,
            pageCount: pageCount
        )

        Group {
            if pageCount > 1, layout.trackHeight >= 90 {
                railContent(layout: layout)
                    .frame(width: layout.containerWidth, height: layout.trackHeight)
                    .padding(.trailing, safeAreaInsets.trailing + layout.trailingInset)
                    .offset(y: layout.verticalOffset)
                    .frame(
                        width: viewportSize.width,
                        height: viewportSize.height,
                        alignment: .trailing
                    )
            }
        }
        .onAppear {
            coordinator.syncCurrentPage(currentPageIndex, pageCount: pageCount)
            refreshRailPreviews()
        }
        .onChange(of: currentPage) { _, _ in
            coordinator.syncCurrentPage(currentPageIndex, pageCount: pageCount)
        }
        .onChange(of: pageCount) { _, _ in
            coordinator.syncCurrentPage(currentPageIndex, pageCount: pageCount)
            refreshRailPreviews()
        }
        .onChange(of: document.fileURL) { _, _ in
            coordinator.syncCurrentPage(currentPageIndex, pageCount: pageCount)
            refreshRailPreviews()
        }
        .onChange(of: coordinator.thumbnailPageIndex) { _, pageIndex in
            previewCoordinator.loadFocusedPreview(
                document: document,
                pageIndex: pageIndex,
                maxPixelSize: focusedPreviewMaxPixelSize
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPagePreviewDidUpdate)) { notification in
            guard let previewNamespace,
                  let update = readerPagePreviewUpdateInfo(from: notification),
                  update.namespace == previewNamespace,
                  ReaderVerticalThumbnailRailGeometry.pageIndices(pageCount: pageCount).contains(update.pageIndex)
            else {
                return
            }

            guard let sourceImage = ReaderPagePreviewStore.shared.image(
                namespace: previewNamespace,
                pageIndex: update.pageIndex
            ) else {
                return
            }

            previewCoordinator.ingestPreview(
                sourceImage,
                pageIndex: update.pageIndex,
                maxPixelSize: railPreviewMaxPixelSize
            )
            if update.pageIndex == coordinator.thumbnailPageIndex {
                previewCoordinator.loadFocusedPreview(
                    document: document,
                    pageIndex: update.pageIndex,
                    maxPixelSize: focusedPreviewMaxPixelSize
                )
            }
        }
        .onChange(of: coordinator.isInteracting) { _, isInteracting in
            DispatchQueue.main.async {
                onInteractionChanged(isInteracting)
            }
        }
        .onDisappear {
            coordinator.cancelInteraction()
            previewCoordinator.reset()
            DispatchQueue.main.async {
                onInteractionChanged(false)
            }
        }
    }

    private var currentPageIndex: Int {
        max(min(currentPage - 1, max(pageCount - 1, 0)), 0)
    }

    private var previewNamespace: String? {
        guard case .imageSequence(let imageSequence) = document else {
            return nil
        }
        return ReaderPageCache.namespace(for: imageSequence.url)
    }

    private var railPreviewMaxPixelSize: Int {
        UIDevice.current.userInterfaceIdiom == .pad ? 18 : 12
    }

    private var focusedPreviewMaxPixelSize: Int {
        UIDevice.current.userInterfaceIdiom == .pad ? 96 : 72
    }

    private func refreshRailPreviews() {
        guard let previewNamespace else {
            previewCoordinator.reset()
            return
        }

        previewCoordinator.configure(
            namespace: previewNamespace,
            pageCount: pageCount,
            maxPixelSize: railPreviewMaxPixelSize
        )
        previewCoordinator.loadFocusedPreview(
            document: document,
            pageIndex: coordinator.thumbnailPageIndex,
            maxPixelSize: focusedPreviewMaxPixelSize
        )
    }

    private func railContent(layout: ReaderVerticalThumbnailRailLayout) -> some View {
        let focusedCenterY = pageCenterY(
            pageIndex: coordinator.focusedPageIndex,
            layout: layout
        )
        let railCenterX = layout.containerWidth - (layout.railThumbnailWidth / 2) - 4
        let interactionCenterX = layout.containerWidth - (layout.interactionWidth / 2)

        return ZStack(alignment: .topLeading) {
            ReaderVerticalThumbnailRibbon(
                pageCount: pageCount,
                focusedPagePosition: CGFloat(coordinator.focusedPageIndex),
                focusedPreviewPageIndex: previewCoordinator.focusedPageIndex,
                focusedPreviewImage: previewCoordinator.focusedPreviewImage,
                layout: layout,
                railCenterX: railCenterX,
                previewImages: previewCoordinator.railPreviewImages
            )
            .frame(width: layout.containerWidth, height: layout.trackHeight)
            .accessibilityHidden(true)

            if coordinator.isInteracting {
                let focusedThumbnailWidth = layout.maximumFocusedThumbnailWidth
                let focusedThumbnailX = railCenterX - layout.maximumLeadingOffset
                Text(verbatim: "\(coordinator.focusedPageIndex + 1) / \(pageCount)")
                    .font(AppFont.caption(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .fixedSize()
                    .position(
                        x: max((focusedThumbnailX - focusedThumbnailWidth / 2 - 8) / 2, 28),
                        y: focusedCenterY
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .accessibilityHidden(true)
            }

            ReaderVerticalThumbnailRailInteractionBridge(
                pageCount: pageCount,
                focusedPageIndex: coordinator.focusedPageIndex,
                onBegan: { locationY in
                    coordinator.beginInteraction()
                    coordinator.updateFocusedPage(
                        pageIndex(at: locationY, layout: layout),
                        pageCount: pageCount
                    )
                },
                onChanged: { locationY in
                    coordinator.updateFocusedPage(
                        pageIndex(at: locationY, layout: layout),
                        pageCount: pageCount
                    )
                },
                onEnded: { locationY, cancelled in
                    if !cancelled {
                        coordinator.updateFocusedPage(
                            pageIndex(at: locationY, layout: layout),
                            pageCount: pageCount
                        )
                    }

                    if let committedPageIndex = coordinator.endInteraction(
                        commit: !cancelled,
                        pageCount: pageCount
                    ) {
                        onPageSelected(committedPageIndex + 1)
                    }
                },
                onAccessibilityAdjustment: { pageIndex in
                    commitImmediately(pageIndex)
                }
            )
            .frame(width: layout.interactionWidth, height: layout.trackHeight)
            .position(x: interactionCenterX, y: layout.trackHeight / 2)
        }
        .animation(
            accessibilityReduceMotion
                ? nil
                : .spring(response: 0.20, dampingFraction: 0.86),
            value: coordinator.focusedPageIndex
        )
        .animation(
            accessibilityReduceMotion ? nil : AppAnimation.quickFade,
            value: coordinator.isInteracting
        )
    }

    private func pageCenterY(
        pageIndex: Int,
        layout: ReaderVerticalThumbnailRailLayout
    ) -> CGFloat {
        ReaderVerticalThumbnailRailGeometry.thumbCenterY(
            pageIndex: pageIndex,
            pageCount: pageCount,
            trackHeight: layout.trackHeight,
            trackInset: layout.trackInset
        )
    }

    private func pageIndex(
        at locationY: CGFloat,
        layout: ReaderVerticalThumbnailRailLayout
    ) -> Int {
        ReaderVerticalThumbnailRailGeometry.pageIndex(
            at: locationY,
            pageCount: pageCount,
            trackHeight: layout.trackHeight,
            trackInset: layout.trackInset
        )
    }

    private func commitImmediately(_ pageIndex: Int) {
        if let committedPageIndex = coordinator.commitImmediately(
            pageIndex,
            pageCount: pageCount
        ) {
            onPageSelected(committedPageIndex + 1)
        }
    }
}

private struct ReaderVerticalThumbnailRibbon: View, Animatable {
    let pageCount: Int
    var focusedPagePosition: CGFloat
    let focusedPreviewPageIndex: Int?
    let focusedPreviewImage: UIImage?
    let layout: ReaderVerticalThumbnailRailLayout
    let railCenterX: CGFloat
    let previewImages: [Int: UIImage]

    var animatableData: CGFloat {
        get { focusedPagePosition }
        set { focusedPagePosition = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            for pageIndex in ReaderVerticalThumbnailRailGeometry.pageIndices(pageCount: pageCount) {
                let influence = ReaderVerticalThumbnailRailGeometry.focusInfluence(
                    pageDistance: CGFloat(pageIndex) - focusedPagePosition
                )
                let thumbnailWidth = ReaderVerticalThumbnailRailGeometry.magnifiedDimension(
                    base: layout.railThumbnailWidth,
                    maximum: layout.maximumFocusedThumbnailWidth,
                    influence: influence
                )
                let thumbnailHeight = ReaderVerticalThumbnailRailGeometry.magnifiedDimension(
                    base: layout.railThumbnailHeight,
                    maximum: layout.maximumFocusedThumbnailHeight,
                    influence: influence
                )
                let centerY = ReaderVerticalThumbnailRailGeometry.magnifiedThumbCenterY(
                    pageIndex: pageIndex,
                    focusedPagePosition: focusedPagePosition,
                    pageCount: pageCount,
                    trackHeight: layout.trackHeight,
                    trackInset: layout.trackInset,
                    baseThumbnailHeight: layout.railThumbnailHeight,
                    maximumThumbnailHeight: layout.maximumFocusedThumbnailHeight,
                    minimumGap: layout.minimumThumbnailGap
                )
                let centerX = railCenterX - (layout.maximumLeadingOffset * influence)
                let rect = CGRect(
                    x: centerX - thumbnailWidth / 2,
                    y: centerY - thumbnailHeight / 2,
                    width: thumbnailWidth,
                    height: thumbnailHeight
                )
                let cornerRadius = min(max(thumbnailWidth * 0.18, 0.4), 8)
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                if influence > 0 {
                    let shadowRect = rect.offsetBy(dx: 0, dy: 1.5)
                    context.fill(
                        Path(roundedRect: shadowRect, cornerRadius: cornerRadius),
                        with: .color(.black.opacity(0.22 * influence))
                    )
                }

                var itemContext = context
                itemContext.opacity = 0.48 + (0.52 * influence)
                itemContext.fill(path, with: .color(.white.opacity(0.12)))

                let previewImage = pageIndex == focusedPreviewPageIndex
                    ? focusedPreviewImage ?? previewImages[pageIndex]
                    : previewImages[pageIndex]
                if let previewImage {
                    var imageContext = itemContext
                    imageContext.clip(to: path)
                    imageContext.draw(
                        Image(uiImage: previewImage),
                        in: aspectFillRect(imageSize: previewImage.size, bounds: rect)
                    )
                } else if influence >= 0.2 {
                    var pageLabel = context.resolve(
                        Text(verbatim: "\(pageIndex + 1)")
                            .font(.system(size: max(min(thumbnailWidth * 0.34, 9), 6), weight: .semibold))
                    )
                    pageLabel.shading = .color(.white.opacity(0.72))
                    itemContext.draw(pageLabel, at: CGPoint(x: rect.midX, y: rect.midY))
                }

                itemContext.stroke(
                    path,
                    with: .color(.white.opacity(0.22 + (0.68 * influence))),
                    lineWidth: 0.35 + (1.15 * influence)
                )
            }
        }
    }

    private func aspectFillRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let scale = max(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum ReaderVerticalThumbnailRailGeometry {
    static func pageIndices(pageCount: Int) -> Range<Int> {
        0..<max(pageCount, 0)
    }

    static func focusInfluence(pageDistance: Int) -> CGFloat {
        focusInfluence(pageDistance: CGFloat(abs(pageDistance)))
    }

    static func focusInfluence(pageDistance: CGFloat) -> CGFloat {
        let distance = abs(pageDistance)
        if distance <= 1 {
            return 1 - (0.42 * distance)
        }
        if distance <= 2 {
            return 0.58 - (0.33 * (distance - 1))
        }
        if distance <= 3 {
            return 0.25 * (3 - distance)
        }
        return 0
    }

    static func magnifiedDimension(
        base: CGFloat,
        maximum: CGFloat,
        influence: CGFloat
    ) -> CGFloat {
        let clampedInfluence = min(max(influence, 0), 1)
        return max(base, 0) + ((max(maximum, base) - max(base, 0)) * clampedInfluence)
    }

    static func minimumTrackInsetForMagnification(
        maximumThumbnailHeight: CGFloat,
        edgePadding: CGFloat = 1
    ) -> CGFloat {
        let focusedHeight = max(maximumThumbnailHeight, 0)
        let firstNeighborHeight = magnifiedDimension(
            base: 0,
            maximum: focusedHeight,
            influence: focusInfluence(pageDistance: 1)
        )
        let secondNeighborHeight = magnifiedDimension(
            base: 0,
            maximum: focusedHeight,
            influence: focusInfluence(pageDistance: 2)
        )

        let affectedSpan = (focusedHeight + firstNeighborHeight) / 2
            + (firstNeighborHeight + secondNeighborHeight) / 2
            + secondNeighborHeight / 2
        return affectedSpan + max(edgePadding, 0)
    }

    static func compactThumbnailHeight(
        naturalStride: CGFloat,
        maximumHeight: CGFloat,
        minimumGap: CGFloat
    ) -> CGFloat {
        guard naturalStride > 0 else {
            return 0
        }

        let availableHeight = max(
            naturalStride - max(minimumGap, 0),
            naturalStride * 0.55
        )
        return min(max(maximumHeight, 0), availableHeight)
    }

    static func compactTrackHeight(
        pageCount: Int,
        preferredPageStride: CGFloat,
        focusInset: CGFloat,
        minimumHeight: CGFloat,
        maximumHeight: CGFloat
    ) -> CGFloat {
        let resolvedMaximumHeight = max(maximumHeight, 0)
        let resolvedMinimumHeight = min(max(minimumHeight, 0), resolvedMaximumHeight)
        let pageSpan = CGFloat(max(pageCount - 1, 0)) * max(preferredPageStride, 0)
        let desiredHeight = (2 * max(focusInset, 0)) + pageSpan
        return min(max(desiredHeight, resolvedMinimumHeight), resolvedMaximumHeight)
    }

    static func naturalPageStride(
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat
    ) -> CGFloat {
        guard pageCount > 1 else {
            return 0
        }

        let range = travelRange(trackHeight: trackHeight, trackInset: trackInset)
        return max(range.upperBound - range.lowerBound, 0) / CGFloat(pageCount - 1)
    }

    static func thumbCenterY(
        pageIndex: Int,
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat
    ) -> CGFloat {
        thumbCenterY(
            pagePosition: CGFloat(pageIndex),
            pageCount: pageCount,
            trackHeight: trackHeight,
            trackInset: trackInset
        )
    }

    static func magnifiedThumbCenterY(
        pageIndex: Int,
        focusedPagePosition: CGFloat,
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat,
        baseThumbnailHeight: CGFloat,
        maximumThumbnailHeight: CGFloat,
        minimumGap: CGFloat
    ) -> CGFloat {
        guard pageCount > 1 else {
            return max(trackHeight, 0) / 2
        }

        let clampedPageIndex = max(min(pageIndex, pageCount - 1), 0)
        let clampedFocusPosition = min(
            max(focusedPagePosition, 0),
            CGFloat(pageCount - 1)
        )
        let signedPageDistance = CGFloat(clampedPageIndex) - clampedFocusPosition
        guard signedPageDistance != 0 else {
            return thumbCenterY(
                pagePosition: clampedFocusPosition,
                pageCount: pageCount,
                trackHeight: trackHeight,
                trackInset: trackInset
            )
        }

        let focusCenterY = thumbCenterY(
            pagePosition: clampedFocusPosition,
            pageCount: pageCount,
            trackHeight: trackHeight,
            trackInset: trackInset
        )
        let direction: CGFloat = signedPageDistance < 0 ? -1 : 1
        let distance = magnifiedDistance(
            pageDistance: abs(signedPageDistance),
            pageCount: pageCount,
            trackHeight: trackHeight,
            trackInset: trackInset,
            baseThumbnailHeight: baseThumbnailHeight,
            maximumThumbnailHeight: maximumThumbnailHeight,
            minimumGap: minimumGap
        )
        return focusCenterY + (direction * distance)
    }

    static func pageIndex(
        at locationY: CGFloat,
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat
    ) -> Int {
        guard pageCount > 1 else {
            return 0
        }

        let range = travelRange(trackHeight: trackHeight, trackInset: trackInset)
        guard pageCount > 1, range.upperBound > range.lowerBound else {
            return 0
        }

        let clampedY = min(max(locationY, range.lowerBound), range.upperBound)
        let progress = (clampedY - range.lowerBound) / (range.upperBound - range.lowerBound)
        return Int((progress * CGFloat(pageCount - 1)).rounded())
    }

    private static func thumbCenterY(
        pagePosition: CGFloat,
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat
    ) -> CGFloat {
        let range = travelRange(trackHeight: trackHeight, trackInset: trackInset)
        guard pageCount > 1 else {
            return max(trackHeight, 0) / 2
        }

        let clampedPosition = min(max(pagePosition, 0), CGFloat(pageCount - 1))
        let progress = clampedPosition / CGFloat(pageCount - 1)
        return range.lowerBound + ((range.upperBound - range.lowerBound) * progress)
    }

    private static func magnifiedDistance(
        pageDistance: CGFloat,
        pageCount: Int,
        trackHeight: CGFloat,
        trackInset: CGFloat,
        baseThumbnailHeight: CGFloat,
        maximumThumbnailHeight: CGFloat,
        minimumGap: CGFloat
    ) -> CGFloat {
        let naturalStride = naturalPageStride(
            pageCount: pageCount,
            trackHeight: trackHeight,
            trackInset: trackInset
        )
        let firstNeighborHeight = magnifiedDimension(
            base: baseThumbnailHeight,
            maximum: maximumThumbnailHeight,
            influence: focusInfluence(pageDistance: 1)
        )
        let secondNeighborHeight = magnifiedDimension(
            base: baseThumbnailHeight,
            maximum: maximumThumbnailHeight,
            influence: focusInfluence(pageDistance: 2)
        )
        let gap = max(minimumGap, 0)
        let firstStride = max(
            naturalStride,
            (maximumThumbnailHeight + firstNeighborHeight) / 2 + gap
        )
        let secondStride = max(
            naturalStride,
            (firstNeighborHeight + secondNeighborHeight) / 2 + gap
        )
        let thirdStride = max(
            naturalStride,
            (secondNeighborHeight + baseThumbnailHeight) / 2 + gap
        )

        if pageDistance <= 1 {
            return pageDistance * firstStride
        }
        if pageDistance <= 2 {
            return firstStride + ((pageDistance - 1) * secondStride)
        }
        if pageDistance <= 3 {
            return firstStride + secondStride + ((pageDistance - 2) * thirdStride)
        }

        return firstStride
            + secondStride
            + thirdStride
            + ((pageDistance - 3) * naturalStride)
    }

    private static func travelRange(
        trackHeight: CGFloat,
        trackInset: CGFloat
    ) -> ClosedRange<CGFloat> {
        let resolvedTrackHeight = max(trackHeight, 0)
        let inset = min(max(trackInset, 0), resolvedTrackHeight / 2)
        return inset...(resolvedTrackHeight - inset)
    }
}

struct ReaderVerticalThumbnailRailLayout: Equatable {
    let trackHeight: CGFloat
    let trackInset: CGFloat
    let railThumbnailWidth: CGFloat
    let railThumbnailHeight: CGFloat
    let maximumFocusedThumbnailWidth: CGFloat
    let maximumFocusedThumbnailHeight: CGFloat
    let minimumThumbnailGap: CGFloat
    let maximumLeadingOffset: CGFloat
    let containerWidth: CGFloat
    let interactionWidth: CGFloat
    let trailingInset: CGFloat
    let verticalOffset: CGFloat

    static func adaptive(
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets,
        pageCount: Int,
        userInterfaceIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> ReaderVerticalThumbnailRailLayout {
        let isPad = userInterfaceIdiom == .pad
        let chromeClearance: CGFloat = isPad ? 112 : 96
        let availableHeight = max(
            viewportSize.height
                - safeAreaInsets.top
                - safeAreaInsets.bottom
                - chromeClearance,
            0
        )
        let preferredPageStride: CGFloat = isPad ? 3.8 : 2.8
        let nominalFocusedThumbnailHeight: CGFloat = isPad ? 56 : 44
        let preferredTrackInset = max(
            isPad ? 72 : 58,
            ReaderVerticalThumbnailRailGeometry.minimumTrackInsetForMagnification(
                maximumThumbnailHeight: nominalFocusedThumbnailHeight
            ).rounded(.up)
        )
        let viewportHeightLimit = viewportSize.height * (isPad ? 0.50 : 0.52)
        let absoluteHeightLimit: CGFloat = isPad ? 540 : 380
        let maximumTrackHeight = min(
            availableHeight,
            min(viewportHeightLimit, absoluteHeightLimit)
        )
        let trackHeight = ReaderVerticalThumbnailRailGeometry.compactTrackHeight(
            pageCount: pageCount,
            preferredPageStride: preferredPageStride,
            focusInset: preferredTrackInset,
            minimumHeight: isPad ? 148 : 120,
            maximumHeight: maximumTrackHeight
        )
        let focusScale = min(
            max(trackHeight / (isPad ? 540 : 320), isPad ? 0.72 : 0.68),
            1
        )
        let maximumFocusedThumbnailWidth = (isPad ? 38 : 30) * focusScale
        let maximumFocusedThumbnailHeight = nominalFocusedThumbnailHeight * focusScale
        let trackInset = min(preferredTrackInset, max((trackHeight - 4) / 2, 0))
        let naturalStride = ReaderVerticalThumbnailRailGeometry.naturalPageStride(
            pageCount: pageCount,
            trackHeight: trackHeight,
            trackInset: trackInset
        )
        let densityAwareGap = min(
            max(naturalStride * 0.18, 0.08),
            naturalStride * 0.35
        )
        let minimumThumbnailGap = min(densityAwareGap, isPad ? 1.2 : 1)
        let railThumbnailHeight = ReaderVerticalThumbnailRailGeometry.compactThumbnailHeight(
            naturalStride: naturalStride,
            maximumHeight: isPad ? 12 : 10,
            minimumGap: minimumThumbnailGap
        )
        let railThumbnailWidth = min(
            isPad ? 8 : 7,
            max(railThumbnailHeight * 0.68, min(railThumbnailHeight, 0.75))
        )

        return ReaderVerticalThumbnailRailLayout(
            trackHeight: trackHeight,
            trackInset: trackInset,
            railThumbnailWidth: railThumbnailWidth,
            railThumbnailHeight: railThumbnailHeight,
            maximumFocusedThumbnailWidth: maximumFocusedThumbnailWidth,
            maximumFocusedThumbnailHeight: maximumFocusedThumbnailHeight,
            minimumThumbnailGap: minimumThumbnailGap,
            maximumLeadingOffset: isPad ? 28 : 20,
            containerWidth: isPad ? 160 : 136,
            interactionWidth: isPad ? 82 : 68,
            trailingInset: isPad ? 8 : 5,
            verticalOffset: (safeAreaInsets.top - safeAreaInsets.bottom) / 2
        )
    }
}

@MainActor
private final class ReaderVerticalRailPreviewCoordinator: ObservableObject {
    @Published private(set) var railPreviewImages: [Int: UIImage] = [:]
    @Published private(set) var focusedPageIndex: Int?
    @Published private(set) var focusedPreviewImage: UIImage?

    private var configurationID: String?
    private var focusedRequestID: String?
    private var focusedPreviewIsPrepared = false
    private var scanTask: Task<Void, Never>?
    private var focusedTask: Task<Void, Never>?
    private var ingestTasks: [Int: Task<Void, Never>] = [:]

    func configure(namespace: String, pageCount: Int, maxPixelSize: Int) {
        let resolvedPageCount = max(pageCount, 0)
        let resolvedPixelSize = max(maxPixelSize, 1)
        let newConfigurationID = "\(namespace)#\(resolvedPageCount)#\(resolvedPixelSize)"
        guard configurationID != newConfigurationID else {
            return
        }

        cancelTasks()
        configurationID = newConfigurationID
        focusedRequestID = nil
        focusedPreviewIsPrepared = false
        railPreviewImages = [:]
        focusedPageIndex = nil
        focusedPreviewImage = nil

        scanTask = Task.detached(priority: .utility) { [weak self] in
            let preparedImages = await Self.prepareCachedThumbnails(
                namespace: namespace,
                pageCount: resolvedPageCount,
                maxPixelSize: resolvedPixelSize
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      self.configurationID == newConfigurationID
                else {
                    return
                }

                self.railPreviewImages.merge(preparedImages) { existing, _ in existing }
                self.scanTask = nil
            }
        }
    }

    func ingestPreview(_ sourceImage: UIImage, pageIndex: Int, maxPixelSize: Int) {
        guard pageIndex >= 0, let configurationID else {
            return
        }

        ingestTasks[pageIndex]?.cancel()
        let resolvedPixelSize = max(maxPixelSize, 1)
        ingestTasks[pageIndex] = Task(priority: .utility) { @MainActor [weak self] in
            let preparedImage = await Self.prepareThumbnail(
                sourceImage,
                maxPixelSize: resolvedPixelSize
            )
            guard let self,
                  !Task.isCancelled,
                  self.configurationID == configurationID,
                  let preparedImage
            else {
                return
            }

            self.railPreviewImages[pageIndex] = preparedImage
            self.ingestTasks[pageIndex] = nil
        }
    }

    func loadFocusedPreview(document: ComicDocument, pageIndex: Int, maxPixelSize: Int) {
        let resolvedPixelSize = max(maxPixelSize, 1)
        let requestID = "\(document.fileURL.path)#\(pageIndex)#\(resolvedPixelSize)"
        if focusedRequestID == requestID,
           focusedTask != nil || focusedPreviewIsPrepared {
            return
        }

        focusedTask?.cancel()
        focusedRequestID = requestID
        focusedPreviewIsPrepared = false
        focusedPageIndex = pageIndex
        focusedPreviewImage = railPreviewImages[pageIndex]

        focusedTask = Task(priority: .utility) { @MainActor [weak self] in
            let sourceImage: UIImage?
            switch document {
            case .imageSequence(let imageSequence):
                let namespace = ReaderPageCache.namespace(for: imageSequence.url)
                if let cachedImage = ReaderPagePreviewStore.shared.image(
                    namespace: namespace,
                    pageIndex: pageIndex
                ) {
                    sourceImage = cachedImage
                } else if let pageName = imageSequence.pageName(at: pageIndex) {
                    sourceImage = await ReaderImageSequenceThumbnailPipeline.shared.image(
                        documentURL: imageSequence.url,
                        pageSource: imageSequence.pageSource,
                        pageName: pageName,
                        pageIndex: pageIndex,
                        maxPixelSize: resolvedPixelSize
                    )
                } else {
                    sourceImage = nil
                }
            case .ebook, .unsupported:
                sourceImage = nil
            }

            let preparedImage: UIImage?
            if let sourceImage {
                preparedImage = await Self.prepareThumbnail(
                    sourceImage,
                    maxPixelSize: resolvedPixelSize
                )
            } else {
                preparedImage = nil
            }

            guard let self,
                  !Task.isCancelled,
                  self.focusedRequestID == requestID
            else {
                return
            }

            if let preparedImage {
                self.focusedPreviewImage = preparedImage
                self.focusedPreviewIsPrepared = true
            }
            self.focusedTask = nil
        }
    }

    func reset() {
        cancelTasks()
        configurationID = nil
        focusedRequestID = nil
        focusedPreviewIsPrepared = false
        railPreviewImages = [:]
        focusedPageIndex = nil
        focusedPreviewImage = nil
    }

    deinit {
        scanTask?.cancel()
        focusedTask?.cancel()
        ingestTasks.values.forEach { $0.cancel() }
    }

    private func cancelTasks() {
        scanTask?.cancel()
        scanTask = nil
        focusedTask?.cancel()
        focusedTask = nil
        ingestTasks.values.forEach { $0.cancel() }
        ingestTasks.removeAll()
    }

    nonisolated private static func prepareCachedThumbnails(
        namespace: String,
        pageCount: Int,
        maxPixelSize: Int
    ) async -> [Int: UIImage] {
        var preparedImages: [Int: UIImage] = [:]
        for pageIndex in 0..<pageCount {
            guard !Task.isCancelled else {
                return [:]
            }
            guard let sourceImage = ReaderPagePreviewStore.shared.image(
                namespace: namespace,
                pageIndex: pageIndex
            ), let preparedImage = await prepareThumbnail(
                sourceImage,
                maxPixelSize: maxPixelSize
            ) else {
                continue
            }

            preparedImages[pageIndex] = preparedImage
        }
        return preparedImages
    }

    nonisolated private static func prepareThumbnail(
        _ image: UIImage,
        maxPixelSize: Int
    ) async -> UIImage? {
        await image.byPreparingThumbnail(
            ofSize: CGSize(width: maxPixelSize, height: maxPixelSize)
        )
    }
}

@MainActor
private final class ReaderVerticalThumbnailRailCoordinator: ObservableObject {
    @Published private(set) var focusedPageIndex: Int
    @Published private(set) var thumbnailPageIndex: Int
    @Published private(set) var isInteracting = false

    private var lastCommittedPageIndex: Int
    private var previewUpdateTask: Task<Void, Never>?

    init(initialPageIndex: Int) {
        focusedPageIndex = initialPageIndex
        thumbnailPageIndex = initialPageIndex
        lastCommittedPageIndex = initialPageIndex
    }

    deinit {
        previewUpdateTask?.cancel()
    }

    func syncCurrentPage(_ pageIndex: Int, pageCount: Int) {
        let clampedIndex = clamp(pageIndex, pageCount: pageCount)
        lastCommittedPageIndex = clampedIndex

        guard !isInteracting else {
            return
        }

        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        focusedPageIndex = clampedIndex
        thumbnailPageIndex = clampedIndex
    }

    func beginInteraction() {
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        isInteracting = true
    }

    func updateFocusedPage(_ pageIndex: Int, pageCount: Int) {
        let clampedIndex = clamp(pageIndex, pageCount: pageCount)
        guard focusedPageIndex != clampedIndex else {
            return
        }

        focusedPageIndex = clampedIndex
        scheduleThumbnailUpdate(to: clampedIndex)
    }

    func endInteraction(commit: Bool, pageCount: Int) -> Int? {
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        isInteracting = false

        guard commit else {
            focusedPageIndex = clamp(lastCommittedPageIndex, pageCount: pageCount)
            thumbnailPageIndex = focusedPageIndex
            return nil
        }

        let committedPageIndex = clamp(focusedPageIndex, pageCount: pageCount)
        thumbnailPageIndex = committedPageIndex
        guard committedPageIndex != lastCommittedPageIndex else {
            return nil
        }

        lastCommittedPageIndex = committedPageIndex
        return committedPageIndex
    }

    func commitImmediately(_ pageIndex: Int, pageCount: Int) -> Int? {
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        isInteracting = false

        let committedPageIndex = clamp(pageIndex, pageCount: pageCount)
        focusedPageIndex = committedPageIndex
        thumbnailPageIndex = committedPageIndex
        guard committedPageIndex != lastCommittedPageIndex else {
            return nil
        }

        lastCommittedPageIndex = committedPageIndex
        return committedPageIndex
    }

    func cancelInteraction() {
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        isInteracting = false
        focusedPageIndex = lastCommittedPageIndex
        thumbnailPageIndex = lastCommittedPageIndex
    }

    private func scheduleThumbnailUpdate(to pageIndex: Int) {
        previewUpdateTask?.cancel()
        previewUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.thumbnailPageIndex = pageIndex
        }
    }

    private func clamp(_ pageIndex: Int, pageCount: Int) -> Int {
        max(min(pageIndex, max(pageCount - 1, 0)), 0)
    }
}

private struct ReaderVerticalThumbnailRailInteractionBridge: UIViewRepresentable {
    let pageCount: Int
    let focusedPageIndex: Int
    let onBegan: (CGFloat) -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, Bool) -> Void
    let onAccessibilityAdjustment: (Int) -> Void

    func makeUIView(context: Context) -> ReaderVerticalThumbnailRailInteractionView {
        ReaderVerticalThumbnailRailInteractionView()
    }

    func updateUIView(_ uiView: ReaderVerticalThumbnailRailInteractionView, context: Context) {
        uiView.pageCount = pageCount
        uiView.focusedPageIndex = focusedPageIndex
        uiView.onBegan = onBegan
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
        uiView.onAccessibilityAdjustment = onAccessibilityAdjustment
        uiView.refreshAccessibilityValue()
    }
}

private final class ReaderVerticalThumbnailRailInteractionView: UIControl, UIGestureRecognizerDelegate {
    var pageCount = 1
    var focusedPageIndex = 0
    var onBegan: ((CGFloat) -> Void)?
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat, Bool) -> Void)?
    var onAccessibilityAdjustment: ((Int) -> Void)?

    private lazy var pressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handlePress(_:))
        )
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = 10_000
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.requiresExclusiveTouchType = true
        recognizer.delegate = self
        return recognizer
    }()

    private var isInteractionActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isExclusiveTouch = true
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = NSLocalizedString(
            "Browse Pages",
            comment: "Reader page rail accessibility label"
        )
        addGestureRecognizer(pressRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func accessibilityIncrement() {
        adjustAccessibilityPage(by: 1)
    }

    override func accessibilityDecrement() {
        adjustAccessibilityPage(by: -1)
    }

    func refreshAccessibilityValue() {
        accessibilityValue = String.localizedStringWithFormat(
            NSLocalizedString(
                "Page %lld of %lld",
                comment: "Reader current page accessibility value"
            ),
            Int64(focusedPageIndex + 1),
            Int64(max(pageCount, 1))
        )
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        pageCount > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let locationY = recognizer.location(in: self).y
        switch recognizer.state {
        case .began:
            isInteractionActive = true
            onBegan?(locationY)
        case .changed:
            guard isInteractionActive else {
                return
            }
            onChanged?(locationY)
        case .ended:
            guard isInteractionActive else {
                return
            }
            isInteractionActive = false
            onEnded?(locationY, false)
        case .cancelled, .failed:
            guard isInteractionActive else {
                return
            }
            isInteractionActive = false
            onEnded?(locationY, true)
        default:
            break
        }
    }

    private func adjustAccessibilityPage(by offset: Int) {
        let targetPageIndex = max(min(focusedPageIndex + offset, max(pageCount - 1, 0)), 0)
        guard targetPageIndex != focusedPageIndex else {
            return
        }

        focusedPageIndex = targetPageIndex
        refreshAccessibilityValue()
        onAccessibilityAdjustment?(targetPageIndex)
    }
}
