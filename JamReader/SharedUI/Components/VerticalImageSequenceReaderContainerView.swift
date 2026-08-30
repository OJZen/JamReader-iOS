import SwiftUI
import ImageIO
import UIKit

enum VerticalReaderZoomGeometry {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let zoomedTolerance: CGFloat = 0.01

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumScale), maximumScale)
    }

    static func isZoomed(_ scale: CGFloat) -> Bool {
        scale > minimumScale + zoomedTolerance
    }

    static func pageSize(viewportWidth: CGFloat, aspectRatio: CGFloat, scale: CGFloat) -> CGSize {
        let baseWidth = max(viewportWidth, 1)
        let safeRatio = max(aspectRatio, 0.01)
        let resolvedScale = clampedScale(scale)
        let baseHeight = max(baseWidth * safeRatio, 220)
        return CGSize(width: baseWidth * resolvedScale, height: baseHeight * resolvedScale)
    }

    static func verticalSectionInset(viewportWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let baseInset: CGFloat = usesRegularMetrics(viewportWidth: viewportWidth) ? 24 : 12
        return baseInset * clampedScale(scale)
    }

    static func lineSpacing(viewportWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let baseSpacing: CGFloat = usesRegularMetrics(viewportWidth: viewportWidth) ? 18 : 10
        return baseSpacing * clampedScale(scale)
    }

    static func usesRegularMetrics(viewportWidth: CGFloat) -> Bool {
        max(viewportWidth, 0) >= AppLayout.regularReaderLayoutMinWidth
    }

    static func contentOffset(
        preserving viewportLocation: CGPoint,
        currentContentOffset: CGPoint,
        from oldScale: CGFloat,
        to newScale: CGFloat,
        contentSize: CGSize,
        viewportSize: CGSize,
        adjustedInsets: UIEdgeInsets
    ) -> CGPoint {
        let safeOldScale = max(oldScale, 0.01)
        let scaleRatio = clampedScale(newScale) / safeOldScale
        let anchorInContent = CGPoint(
            x: currentContentOffset.x + viewportLocation.x,
            y: currentContentOffset.y + viewportLocation.y
        )
        let proposedOffset = CGPoint(
            x: anchorInContent.x * scaleRatio - viewportLocation.x,
            y: anchorInContent.y * scaleRatio - viewportLocation.y
        )
        return clampedContentOffset(
            proposedOffset,
            contentSize: contentSize,
            viewportSize: viewportSize,
            adjustedInsets: adjustedInsets
        )
    }

    static func clampedContentOffset(
        _ offset: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize,
        adjustedInsets: UIEdgeInsets
    ) -> CGPoint {
        let minX = -adjustedInsets.left
        let maxX = max(minX, contentSize.width - viewportSize.width + adjustedInsets.right)
        let minY = -adjustedInsets.top
        let maxY = max(minY, contentSize.height - viewportSize.height + adjustedInsets.bottom)
        return CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }
}

struct VerticalImageSequenceReaderContainerView: UIViewControllerRepresentable {
    let document: ImageSequenceComicDocument
    let initialPageIndex: Int
    let layout: ReaderDisplayLayout
    let isDismissGestureActive: Bool
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void
    let onZoomStateChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            document: document,
            layout: layout,
            currentPageIndex: clampedPageIndex(initialPageIndex),
            onPageChanged: onPageChanged,
            onReaderTap: onReaderTap,
            onZoomStateChanged: onZoomStateChanged
        )
    }

    func makeUIViewController(context: Context) -> VerticalReaderViewController {
        let viewController = VerticalReaderViewController()
        viewController.isDismissGestureActive = isDismissGestureActive
        context.coordinator.attach(to: viewController)
        context.coordinator.scrollToPage(index: clampedPageIndex(initialPageIndex), animated: false)
        return viewController
    }

    func updateUIViewController(_ viewController: VerticalReaderViewController, context: Context) {
        viewController.isDismissGestureActive = isDismissGestureActive
        context.coordinator.onPageChanged = onPageChanged
        context.coordinator.onReaderTap = onReaderTap
        context.coordinator.onZoomStateChanged = onZoomStateChanged
        context.coordinator.update(
            document: document,
            layout: layout,
            requestedPageIndex: clampedPageIndex(initialPageIndex)
        )
    }

    private func clampedPageIndex(_ pageIndex: Int) -> Int {
        guard document.pageCount > 0 else {
            return 0
        }

        return min(max(pageIndex, 0), document.pageCount - 1)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        private weak var viewController: VerticalReaderViewController?
        private let imageCache: NSCache<NSNumber, UIImage>

        private var pageAspectRatios: [Int: CGFloat] = [:]
        private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
        private var memoryWarningObserver: NSObjectProtocol?
        private var previewObserver: NSObjectProtocol?
        private weak var pinchGestureRecognizer: UIPinchGestureRecognizer?
        private var pinchStartScale = VerticalReaderZoomGeometry.minimumScale
        private var zoomScale = VerticalReaderZoomGeometry.minimumScale
        private var lastReportedZoomState = false

        private(set) var document: ImageSequenceComicDocument
        private(set) var layout: ReaderDisplayLayout
        private(set) var currentPageIndex: Int
        var onPageChanged: (Int) -> Void
        var onReaderTap: (ReaderTapRegion) -> Void
        var onZoomStateChanged: ((Bool) -> Void)?
        private var lastReportedPageIndex: Int?

        init(
            document: ImageSequenceComicDocument,
            layout: ReaderDisplayLayout,
            currentPageIndex: Int,
            onPageChanged: @escaping (Int) -> Void,
            onReaderTap: @escaping (ReaderTapRegion) -> Void,
            onZoomStateChanged: ((Bool) -> Void)?
        ) {
            self.document = document
            self.layout = layout
            self.currentPageIndex = currentPageIndex
            self.lastReportedPageIndex = currentPageIndex
            self.onPageChanged = onPageChanged
            self.onReaderTap = onReaderTap
            self.onZoomStateChanged = onZoomStateChanged

            let cache = NSCache<NSNumber, UIImage>()
            cache.countLimit = 6
            cache.totalCostLimit = 64 * 1_024 * 1_024
            self.imageCache = cache
        }

        deinit {
            if let pinchGestureRecognizer {
                pinchGestureRecognizer.view?.removeGestureRecognizer(pinchGestureRecognizer)
            }
            cancelPageTasks()
            if let memoryWarningObserver {
                NotificationCenter.default.removeObserver(memoryWarningObserver)
            }
            removePreviewObserver()
        }

        func attach(to viewController: VerticalReaderViewController) {
            self.viewController = viewController
            viewController.collectionLayout.aspectRatioProvider = { [weak self] index in
                self?.pageAspectRatios[index] ?? 1.42
            }
            viewController.collectionView.dataSource = self
            viewController.collectionView.delegate = self
            viewController.collectionView.prefetchDataSource = self
            viewController.onTap = { [weak self, weak viewController] location in
                guard let self, let viewController else {
                    return
                }

                self.handleTap(at: location, in: viewController.collectionView)
            }
            viewController.onBoundsChanged = { [weak self] in
                self?.handleContainerBoundsChanged()
            }
            viewController.onAdvancePage = { [weak self] in
                self?.navigateByPage(step: 1)
            }
            viewController.onRetreatPage = { [weak self] in
                self?.navigateByPage(step: -1)
            }

            let pinchGestureRecognizer = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handlePinch(_:))
            )
            pinchGestureRecognizer.delegate = self
            pinchGestureRecognizer.cancelsTouchesInView = false
            viewController.collectionView.addGestureRecognizer(pinchGestureRecognizer)
            self.pinchGestureRecognizer = pinchGestureRecognizer

            observeMemoryWarningsIfNeeded()
            observePreviewUpdatesIfNeeded()
            viewController.collectionView.reloadData()
        }

        func update(document: ImageSequenceComicDocument, layout: ReaderDisplayLayout, requestedPageIndex: Int) {
            let documentChanged = self.document.url != document.url
                || self.document.pageNames != document.pageNames
                || ObjectIdentifier(self.document.pageSource) != ObjectIdentifier(document.pageSource)
            let layoutChanged = self.layout != layout

            self.document = document
            self.layout = layout

            if documentChanged {
                resetZoomScale()
                pageAspectRatios.removeAll()
                imageCache.removeAllObjects()
                cancelPageTasks()
                viewController?.collectionView.reloadData()
                scrollToPage(index: requestedPageIndex, animated: false)
                prefetchAround(pageIndex: requestedPageIndex)
                return
            }

            if layoutChanged {
                viewController?.collectionView.collectionViewLayout.invalidateLayout()
            }

            guard requestedPageIndex != currentPageIndex else {
                return
            }

            scrollToPage(index: requestedPageIndex, animated: false)
        }

        func scrollToPage(index: Int, animated: Bool) {
            guard let collectionView = viewController?.collectionView else {
                return
            }

            let clampedIndex = min(max(index, 0), max(document.pageCount - 1, 0))
            guard document.pageCount > 0 else {
                return
            }

            let indexPath = IndexPath(item: clampedIndex, section: 0)
            guard collectionView.numberOfItems(inSection: 0) > clampedIndex else {
                return
            }

            let pageDidChange = currentPageIndex != clampedIndex
            if pageDidChange {
                resetZoomScale()
            }
            currentPageIndex = clampedIndex
            collectionView.layoutIfNeeded()
            if let targetOffset = targetContentOffset(for: indexPath, in: collectionView) {
                collectionView.setContentOffset(targetOffset, animated: animated)
            } else {
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
            }
            if pageDidChange {
                notifyPageChangedIfNeeded(clampedIndex)
                prefetchAround(pageIndex: clampedIndex)
            }
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            1
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            document.pageCount
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: VerticalReaderPageCell.reuseIdentifier,
                for: indexPath
            ) as? VerticalReaderPageCell else {
                return UICollectionViewCell()
            }

            cell.configurePlaceholder(pageNumber: indexPath.item + 1)
            if let image = imageCache.object(forKey: NSNumber(value: indexPath.item)) {
                cell.setImage(image)
            } else {
                applyPreviewIfAvailable(
                    at: indexPath.item,
                    to: cell,
                    in: collectionView
                )
                ensurePageLoaded(at: indexPath.item, priority: .userInitiated)
            }

            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths {
                ensurePageLoaded(at: indexPath.item, priority: .utility)
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths {
                guard !collectionView.indexPathsForVisibleItems.contains(indexPath) else {
                    continue
                }

                pageLoadTasks[indexPath.item]?.cancel()
                pageLoadTasks[indexPath.item] = nil
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateCurrentPageFromVisibleCells()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateCurrentPageFromVisibleCells()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateCurrentPageFromVisibleCells()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateCurrentPageFromVisibleCells()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let collectionView = viewController?.collectionView,
                  let pinchGestureRecognizer
            else {
                return false
            }

            return (gestureRecognizer === pinchGestureRecognizer
                && otherGestureRecognizer === collectionView.panGestureRecognizer)
                || (otherGestureRecognizer === pinchGestureRecognizer
                    && gestureRecognizer === collectionView.panGestureRecognizer)
        }

        @objc
        private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            guard let collectionView = viewController?.collectionView else {
                return
            }

            let anchor = gestureRecognizer.location(in: collectionView)
            switch gestureRecognizer.state {
            case .began:
                pinchStartScale = zoomScale
            case .changed:
                applyZoomScale(pinchStartScale * gestureRecognizer.scale, around: anchor)
            case .ended:
                let settledScale = VerticalReaderZoomGeometry.isZoomed(zoomScale)
                    ? zoomScale
                    : VerticalReaderZoomGeometry.minimumScale
                applyZoomScale(settledScale, around: anchor)
                pinchStartScale = zoomScale
            case .cancelled, .failed:
                applyZoomScale(pinchStartScale, around: anchor)
            default:
                break
            }
        }

        private func applyZoomScale(_ proposedScale: CGFloat, around anchorInContent: CGPoint) {
            guard let viewController else {
                return
            }

            let collectionView = viewController.collectionView
            let resolvedScale = VerticalReaderZoomGeometry.clampedScale(proposedScale)
            guard abs(resolvedScale - zoomScale) > 0.0001 else {
                reportZoomStateIfNeeded()
                return
            }

            let oldScale = zoomScale
            let oldOffset = collectionView.contentOffset
            let viewportLocation = CGPoint(
                x: anchorInContent.x - collectionView.bounds.minX,
                y: anchorInContent.y - collectionView.bounds.minY
            )
            zoomScale = resolvedScale
            viewController.collectionLayout.zoomScale = resolvedScale

            UIView.performWithoutAnimation {
                collectionView.layoutIfNeeded()
                let targetOffset = VerticalReaderZoomGeometry.contentOffset(
                    preserving: viewportLocation,
                    currentContentOffset: oldOffset,
                    from: oldScale,
                    to: resolvedScale,
                    contentSize: collectionView.contentSize,
                    viewportSize: collectionView.bounds.size,
                    adjustedInsets: collectionView.adjustedContentInset
                )
                collectionView.setContentOffset(targetOffset, animated: false)
            }
            reportZoomStateIfNeeded()
        }

        private func resetZoomScale() {
            guard let collectionView = viewController?.collectionView else {
                zoomScale = VerticalReaderZoomGeometry.minimumScale
                lastReportedZoomState = false
                return
            }

            let viewportCenter = CGPoint(
                x: collectionView.bounds.midX,
                y: collectionView.bounds.midY
            )
            applyZoomScale(VerticalReaderZoomGeometry.minimumScale, around: viewportCenter)
        }

        private func reportZoomStateIfNeeded() {
            let isZoomed = VerticalReaderZoomGeometry.isZoomed(zoomScale)
            guard isZoomed != lastReportedZoomState else {
                return
            }

            lastReportedZoomState = isZoomed
            onZoomStateChanged?(isZoomed)
        }

        private func updateCurrentPageFromVisibleCells() {
            guard let collectionView = viewController?.collectionView else {
                return
            }

            guard let bestIndexPath = preferredCurrentIndexPath(in: collectionView) else {
                return
            }

            if bestIndexPath.item != currentPageIndex {
                currentPageIndex = bestIndexPath.item
                notifyPageChangedIfNeeded(bestIndexPath.item)
                prefetchAround(pageIndex: bestIndexPath.item)
            }
        }

        private func notifyPageChangedIfNeeded(_ pageIndex: Int) {
            guard lastReportedPageIndex != pageIndex else {
                return
            }

            lastReportedPageIndex = pageIndex
            DispatchQueue.main.async { [onPageChanged] in
                onPageChanged(pageIndex)
            }
        }

        private func preferredCurrentIndexPath(in collectionView: UICollectionView) -> IndexPath? {
            let visibleIndexPaths = collectionView.indexPathsForVisibleItems
            guard !visibleIndexPaths.isEmpty else {
                return nil
            }

            let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
            let viewportMidY = visibleRect.midY

            let indexPathContainingMidpoint = visibleIndexPaths.first { indexPath in
                guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                    return false
                }

                return attributes.frame.minY <= viewportMidY && attributes.frame.maxY >= viewportMidY
            }

            if let indexPathContainingMidpoint {
                return indexPathContainingMidpoint
            }

            return visibleIndexPaths.min { lhs, rhs in
                let lhsDistance = distanceFromViewportMidY(for: lhs, viewportMidY: viewportMidY, collectionView: collectionView)
                let rhsDistance = distanceFromViewportMidY(for: rhs, viewportMidY: viewportMidY, collectionView: collectionView)
                if abs(lhsDistance - rhsDistance) < 1 {
                    let lhsArea = visibleArea(for: lhs, in: visibleRect, collectionView: collectionView)
                    let rhsArea = visibleArea(for: rhs, in: visibleRect, collectionView: collectionView)
                    return lhsArea > rhsArea
                }

                return lhsDistance < rhsDistance
            }
        }

        private func visibleArea(
            for indexPath: IndexPath,
            in visibleRect: CGRect,
            collectionView: UICollectionView
        ) -> CGFloat {
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return 0
            }

            let intersection = attributes.frame.intersection(visibleRect)
            guard !intersection.isNull else {
                return 0
            }

            return intersection.width * intersection.height
        }

        private func distanceFromViewportMidY(
            for indexPath: IndexPath,
            viewportMidY: CGFloat,
            collectionView: UICollectionView
        ) -> CGFloat {
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return .greatestFiniteMagnitude
            }

            return abs(attributes.frame.midY - viewportMidY)
        }

        private func ensurePageLoaded(at index: Int, priority: TaskPriority) {
            guard index >= 0, index < document.pageCount else {
                return
            }

            let cacheKey = NSNumber(value: index)
            if imageCache.object(forKey: cacheKey) != nil {
                return
            }

            guard pageLoadTasks[index] == nil else {
                return
            }

            let pageSource = document.pageSource
            let maxPixelSize = preferredDecodeMaxPixelSize()
            let previewNamespace = self.previewNamespace

            pageLoadTasks[index] = Task(priority: priority) { [weak self] in
                guard let self else {
                    return
                }

                let result = await Task.detached(priority: priority) {
                    do {
                        let data = try await pageSource.dataForPage(at: index)
                        guard let image = Self.decodeImage(from: data, maxPixelSize: maxPixelSize) else {
                            throw VerticalPageLoadError.decodeFailed(index: index)
                        }

                        let safeWidth = max(image.size.width, 1)
                        let ratio = image.size.height / safeWidth
                        return Result<(UIImage, CGFloat), Error>.success((image, ratio))
                    } catch {
                        return Result<(UIImage, CGFloat), Error>.failure(error)
                    }
                }.value

                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.pageLoadTasks[index] = nil
                    }
                    return
                }

                await MainActor.run {
                    self.pageLoadTasks[index] = nil
                    guard let collectionView = self.viewController?.collectionView else {
                        return
                    }

                    switch result {
                    case .success(let (image, ratio)):
                        ReaderPagePreviewStore.shared.store(
                            image,
                            namespace: previewNamespace,
                            pageIndex: index
                        )
                        self.imageCache.setObject(
                            image,
                            forKey: cacheKey,
                            cost: max(1, Int(image.size.width * image.size.height * 4))
                        )

                        let previousRatio = self.pageAspectRatios[index]
                        self.pageAspectRatios[index] = ratio
                        if previousRatio == nil || abs((previousRatio ?? ratio) - ratio) > 0.01 {
                            let shouldKeepCurrentPageAnchored = index == self.currentPageIndex
                            collectionView.collectionViewLayout.invalidateLayout()
                            if shouldKeepCurrentPageAnchored {
                                collectionView.layoutIfNeeded()
                                self.scrollToPage(index: self.currentPageIndex, animated: false)
                            }
                        }

                        if let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
                            as? VerticalReaderPageCell {
                            cell.setImage(image)
                        }
                    case .failure(let error):
                        if let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
                            as? VerticalReaderPageCell {
                            cell.setError(error.userFacingMessage)
                        }
                    }
                }
            }
        }

        private func prefetchAround(pageIndex: Int) {
            guard document.pageCount > 1 else {
                return
            }

            let lower = max(0, pageIndex - 2)
            let upper = min(document.pageCount - 1, pageIndex + 2)
            for index in lower...upper where index != pageIndex {
                ensurePageLoaded(at: index, priority: .utility)
            }
        }

        private var previewNamespace: String {
            ReaderPageCache.namespace(for: document.url)
        }

        private func observePreviewUpdatesIfNeeded() {
            guard previewObserver == nil else {
                return
            }

            previewObserver = NotificationCenter.default.addObserver(
                forName: .readerPagePreviewDidUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let info = readerPagePreviewUpdateInfo(from: notification),
                      info.namespace == self.previewNamespace,
                      self.imageCache.object(forKey: NSNumber(value: info.pageIndex)) == nil,
                      let collectionView = self.viewController?.collectionView,
                      let cell = collectionView.cellForItem(at: IndexPath(item: info.pageIndex, section: 0))
                        as? VerticalReaderPageCell
                else {
                    return
                }

                self.applyPreviewIfAvailable(
                    at: info.pageIndex,
                    to: cell,
                    in: collectionView
                )
            }
        }

        private func removePreviewObserver() {
            if let previewObserver {
                NotificationCenter.default.removeObserver(previewObserver)
                self.previewObserver = nil
            }
        }

        private func applyPreviewIfAvailable(
            at index: Int,
            to cell: VerticalReaderPageCell,
            in collectionView: UICollectionView
        ) {
            guard let image = ReaderPagePreviewStore.shared.image(
                namespace: previewNamespace,
                pageIndex: index
            ) else {
                return
            }

            cell.setImage(image)
            updateAspectRatioIfNeeded(
                for: index,
                ratio: image.size.height / max(image.size.width, 1),
                in: collectionView
            )
        }

        private func updateAspectRatioIfNeeded(
            for index: Int,
            ratio: CGFloat,
            in collectionView: UICollectionView
        ) {
            let previousRatio = pageAspectRatios[index]
            pageAspectRatios[index] = ratio

            guard previousRatio == nil || abs((previousRatio ?? ratio) - ratio) > 0.01 else {
                return
            }

            let shouldKeepCurrentPageAnchored = index == currentPageIndex
            collectionView.collectionViewLayout.invalidateLayout()
            if shouldKeepCurrentPageAnchored {
                collectionView.layoutIfNeeded()
                scrollToPage(index: currentPageIndex, animated: false)
            }
        }

        private func handleTap(at location: CGPoint, in collectionView: UICollectionView) {
            let width = max(collectionView.bounds.width, 1)
            let viewportX = location.x - collectionView.bounds.minX
            let horizontalRatio = viewportX / width
            let edgeRatio = preferredTapEdgeRatio(for: width)

            if horizontalRatio < edgeRatio {
                onReaderTap(.leading)
            } else if horizontalRatio > 1 - edgeRatio {
                onReaderTap(.trailing)
            } else {
                onReaderTap(.center)
            }
        }

        private func navigateByPage(step: Int) {
            let targetIndex = currentPageIndex + step

            if targetIndex < 0 {
                onReaderTap(.leading)
                return
            }

            if targetIndex >= document.pageCount {
                onReaderTap(.trailing)
                return
            }

            scrollToPage(index: targetIndex, animated: true)
        }

        private func preferredTapEdgeRatio(for width: CGFloat) -> CGFloat {
            VerticalReaderZoomGeometry.usesRegularMetrics(viewportWidth: width) ? 0.18 : 0.24
        }

        private func preferredDecodeMaxPixelSize() -> Int {
            guard let collectionView = viewController?.collectionView else {
                return 3072
            }

            let contentWidth = max(collectionView.bounds.width, 640)
            let screenScale = collectionView.window?.windowScene?.screen.scale
                ?? collectionView.traitCollection.displayScale
            let estimated = contentWidth * screenScale * 2.5
            return max(1800, min(Int(estimated.rounded()), 4_608))
        }

        private func handleContainerBoundsChanged() {
            guard let collectionView = viewController?.collectionView else {
                return
            }

            resetZoomScale()
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            scrollToPage(index: currentPageIndex, animated: false)
        }

        private func targetContentOffset(for indexPath: IndexPath, in collectionView: UICollectionView) -> CGPoint? {
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                return nil
            }

            let viewportHeight = max(collectionView.bounds.height, 1)
            let minOffsetY = -collectionView.adjustedContentInset.top
            let maxOffsetY = max(
                minOffsetY,
                collectionView.contentSize.height - viewportHeight + collectionView.adjustedContentInset.bottom
            )
            let scaledInset = VerticalReaderZoomGeometry.verticalSectionInset(
                viewportWidth: collectionView.bounds.width,
                scale: zoomScale
            )
            let preferredOffsetY = attributes.frame.minY - scaledInset
            let clampedOffsetY = min(max(preferredOffsetY, minOffsetY), maxOffsetY)
            return VerticalReaderZoomGeometry.clampedContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: clampedOffsetY),
                contentSize: collectionView.contentSize,
                viewportSize: collectionView.bounds.size,
                adjustedInsets: collectionView.adjustedContentInset
            )
        }

        private func observeMemoryWarningsIfNeeded() {
            guard memoryWarningObserver == nil else {
                return
            }

            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.imageCache.removeAllObjects()
                self?.cancelPageTasks()
            }
        }

        private func cancelPageTasks() {
            for task in pageLoadTasks.values {
                task.cancel()
            }
            pageLoadTasks.removeAll()
        }

        nonisolated private static func decodeImage(from data: Data, maxPixelSize: Int) -> UIImage? {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return UIImage(data: data)
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
            ]

            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                return UIImage(cgImage: thumbnail)
            }

            return UIImage(data: data)
        }
    }
}

fileprivate final class VerticalReaderCollectionViewLayout: UICollectionViewLayout {
    var aspectRatioProvider: ((Int) -> CGFloat)? {
        didSet {
            invalidateLayout()
        }
    }

    var zoomScale = VerticalReaderZoomGeometry.minimumScale {
        didSet {
            if abs(zoomScale - oldValue) > 0.0001 {
                invalidateLayout()
            }
        }
    }

    private var cachedAttributes: [UICollectionViewLayoutAttributes] = []
    private var cachedContentSize = CGSize.zero

    override func prepare() {
        super.prepare()
        guard cachedAttributes.isEmpty, let collectionView else {
            return
        }

        let viewportWidth = max(collectionView.bounds.width, 1)
        let inset = VerticalReaderZoomGeometry.verticalSectionInset(
            viewportWidth: viewportWidth,
            scale: zoomScale
        )
        let spacing = VerticalReaderZoomGeometry.lineSpacing(
            viewportWidth: viewportWidth,
            scale: zoomScale
        )
        let itemCount = collectionView.numberOfSections > 0
            ? collectionView.numberOfItems(inSection: 0)
            : 0

        cachedAttributes.reserveCapacity(itemCount)
        var nextY = inset
        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let size = VerticalReaderZoomGeometry.pageSize(
                viewportWidth: viewportWidth,
                aspectRatio: aspectRatioProvider?(item) ?? 1.42,
                scale: zoomScale
            )
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(origin: CGPoint(x: 0, y: nextY), size: size)
            cachedAttributes.append(attributes)
            nextY += size.height + spacing
        }

        let contentHeight = itemCount > 0 ? nextY - spacing + inset : 0
        let scaledWidth = viewportWidth * VerticalReaderZoomGeometry.clampedScale(zoomScale)
        cachedContentSize = CGSize(
            width: max(collectionView.bounds.width, scaledWidth),
            height: max(contentHeight, 0)
        )
    }

    override var collectionViewContentSize: CGSize {
        cachedContentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !cachedAttributes.isEmpty else {
            return []
        }

        var lowerBound = 0
        var upperBound = cachedAttributes.count
        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if cachedAttributes[midpoint].frame.maxY < rect.minY {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        var result: [UICollectionViewLayoutAttributes] = []
        var index = lowerBound
        while index < cachedAttributes.count {
            let attributes = cachedAttributes[index]
            guard attributes.frame.minY <= rect.maxY else {
                break
            }
            if attributes.frame.intersects(rect) {
                result.append(attributes)
            }
            index += 1
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, cachedAttributes.indices.contains(indexPath.item) else {
            return nil
        }
        return cachedAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else {
            return false
        }
        return collectionView.bounds.size != newBounds.size
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        cachedAttributes.removeAll(keepingCapacity: true)
        cachedContentSize = .zero
        super.invalidateLayout(with: context)
    }
}

final class VerticalReaderViewController: UIViewController {
    fileprivate let collectionLayout: VerticalReaderCollectionViewLayout
    let collectionView: UICollectionView
    var isDismissGestureActive = false {
        didSet {
            guard isDismissGestureActive != oldValue else {
                return
            }
            collectionView.isScrollEnabled = !isDismissGestureActive
        }
    }
    var onTap: ((CGPoint) -> Void)?
    var onBoundsChanged: (() -> Void)?
    var onAdvancePage: (() -> Void)?
    var onRetreatPage: (() -> Void)?

    private var lastKnownBoundsSize: CGSize = .zero

    private lazy var singleTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 1
        gestureRecognizer.cancelsTouchesInView = false
        return gestureRecognizer
    }()

    init() {
        let collectionLayout = VerticalReaderCollectionViewLayout()
        self.collectionLayout = collectionLayout
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionLayout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        collectionView.backgroundColor = .black
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(
            VerticalReaderPageCell.self,
            forCellWithReuseIdentifier: VerticalReaderPageCell.reuseIdentifier
        )
        collectionView.addGestureRecognizer(singleTapGestureRecognizer)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard view.bounds.size != lastKnownBoundsSize else {
            return
        }

        lastKnownBoundsSize = view.bounds.size
        onBoundsChanged?()
    }

    @objc
    private func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        onTap?(gestureRecognizer.location(in: collectionView))
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resignFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        let nextPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        nextPageCommand.discoverabilityTitle = String(localized: "Next Page")

        let previousPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: [],
            action: #selector(handleRetreatPage)
        )
        previousPageCommand.discoverabilityTitle = String(localized: "Previous Page")

        let spaceAdvanceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        spaceAdvanceCommand.discoverabilityTitle = String(localized: "Next Page")

        let shiftSpaceRetreatCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [.shift],
            action: #selector(handleRetreatPage)
        )
        shiftSpaceRetreatCommand.discoverabilityTitle = String(localized: "Previous Page")

        return [nextPageCommand, previousPageCommand, spaceAdvanceCommand, shiftSpaceRetreatCommand]
    }

    @objc
    private func handleAdvancePage() {
        onAdvancePage?()
    }

    @objc
    private func handleRetreatPage() {
        onRetreatPage?()
    }
}

private final class VerticalReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "VerticalReaderPageCell"

    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.isHidden = true
        messageLabel.text = nil
        messageLabel.isHidden = true
        activityIndicator.startAnimating()
    }

    func configurePlaceholder(pageNumber: Int) {
        messageLabel.isHidden = true
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.startAnimating()
        accessibilityLabel = String(localized: "Page \(pageNumber)")
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        messageLabel.isHidden = true
        activityIndicator.stopAnimating()
    }

    func setError(_ message: String) {
        imageView.image = nil
        imageView.isHidden = true
        messageLabel.text = message
        messageLabel.isHidden = false
        activityIndicator.stopAnimating()
    }

    private func configureSubviews() {
        contentView.backgroundColor = .black
        contentView.isOpaque = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.isHidden = true

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        contentView.addSubview(imageView)
        contentView.addSubview(activityIndicator)
        contentView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            messageLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

private enum VerticalPageLoadError: LocalizedError {
    case decodeFailed(index: Int)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let index):
            return String(localized: "Page \(index + 1) could not be decoded.")
        }
    }
}
