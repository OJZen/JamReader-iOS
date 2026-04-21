import SwiftUI
import ImageIO
import UIKit

struct VerticalImageSequenceReaderContainerView: UIViewControllerRepresentable {
    let document: ImageSequenceComicDocument
    let initialPageIndex: Int
    let layout: ReaderDisplayLayout
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            document: document,
            layout: layout,
            currentPageIndex: clampedPageIndex(initialPageIndex),
            onPageChanged: onPageChanged,
            onReaderTap: onReaderTap
        )
    }

    func makeUIViewController(context: Context) -> VerticalReaderViewController {
        let viewController = VerticalReaderViewController()
        context.coordinator.attach(to: viewController)
        context.coordinator.scrollToPage(index: clampedPageIndex(initialPageIndex), animated: false)
        return viewController
    }

    func updateUIViewController(_ viewController: VerticalReaderViewController, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        context.coordinator.onReaderTap = onReaderTap
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

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
        private weak var viewController: VerticalReaderViewController?
        private let imageCache: NSCache<NSNumber, UIImage>

        private var pageAspectRatios: [Int: CGFloat] = [:]
        private var pageLoadTasks: [Int: Task<Void, Never>] = [:]
        private var memoryWarningObserver: NSObjectProtocol?
        private var previewObserver: NSObjectProtocol?

        private(set) var document: ImageSequenceComicDocument
        private(set) var layout: ReaderDisplayLayout
        private(set) var currentPageIndex: Int
        var onPageChanged: (Int) -> Void
        var onReaderTap: (ReaderTapRegion) -> Void
        private var lastReportedPageIndex: Int?

        init(
            document: ImageSequenceComicDocument,
            layout: ReaderDisplayLayout,
            currentPageIndex: Int,
            onPageChanged: @escaping (Int) -> Void,
            onReaderTap: @escaping (ReaderTapRegion) -> Void
        ) {
            self.document = document
            self.layout = layout
            self.currentPageIndex = currentPageIndex
            self.lastReportedPageIndex = currentPageIndex
            self.onPageChanged = onPageChanged
            self.onReaderTap = onReaderTap

            let cache = NSCache<NSNumber, UIImage>()
            cache.countLimit = 6
            cache.totalCostLimit = 64 * 1_024 * 1_024
            self.imageCache = cache
        }

        deinit {
            cancelPageTasks()
            if let memoryWarningObserver {
                NotificationCenter.default.removeObserver(memoryWarningObserver)
            }
            removePreviewObserver()
        }

        func attach(to viewController: VerticalReaderViewController) {
            self.viewController = viewController
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

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let contentWidth = max(preferredContentWidth(for: collectionView), 1)
            let ratio = pageAspectRatios[indexPath.item] ?? 1.42
            let height = max(contentWidth * ratio, 220)
            return CGSize(width: contentWidth, height: height)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            insetForSectionAt section: Int
        ) -> UIEdgeInsets {
            let horizontalInset = max(0, (usableCollectionWidth(for: collectionView) - preferredContentWidth(for: collectionView)) * 0.5)
            let verticalInset = verticalSectionInset(for: collectionView.bounds.width)
            return UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumLineSpacingForSectionAt section: Int
        ) -> CGFloat {
            usesRegularReaderMetrics(for: collectionView.bounds.width) ? 18 : 10
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
            let horizontalRatio = location.x / width
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
            usesRegularReaderMetrics(for: width) ? 0.18 : 0.24
        }

        private func preferredDecodeMaxPixelSize() -> Int {
            guard let collectionView = viewController?.collectionView else {
                return 3072
            }

            let contentWidth = max(preferredContentWidth(for: collectionView), 640)
            let screenScale = collectionView.window?.windowScene?.screen.scale
                ?? collectionView.traitCollection.displayScale
            let estimated = contentWidth * screenScale * 2.5
            return max(1800, min(Int(estimated.rounded()), 8192))
        }

        private func handleContainerBoundsChanged() {
            guard let collectionView = viewController?.collectionView else {
                return
            }

            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            scrollToPage(index: currentPageIndex, animated: false)
        }

        private func usableCollectionWidth(for collectionView: UICollectionView) -> CGFloat {
            let adjustedInsets = collectionView.adjustedContentInset
            return max(
                collectionView.bounds.width - adjustedInsets.left - adjustedInsets.right,
                1
            )
        }

        private func preferredContentWidth(for collectionView: UICollectionView) -> CGFloat {
            let availableWidth = usableCollectionWidth(for: collectionView)
            guard usesRegularReaderMetrics(for: collectionView.bounds.width) else {
                return availableWidth
            }

            let maxReadableWidth: CGFloat = collectionView.bounds.width > 1_000 ? 920 : 820
            return min(availableWidth, maxReadableWidth)
        }

        private func verticalSectionInset(for width: CGFloat) -> CGFloat {
            usesRegularReaderMetrics(for: width) ? 24 : 12
        }

        private func usesRegularReaderMetrics(for width: CGFloat) -> Bool {
            max(width, 0) >= AppLayout.regularReaderLayoutMinWidth
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
            let preferredOffsetY = attributes.frame.minY - verticalSectionInset(for: collectionView.bounds.width)
            let clampedOffsetY = min(max(preferredOffsetY, minOffsetY), maxOffsetY)
            return CGPoint(x: -collectionView.adjustedContentInset.left, y: clampedOffsetY)
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

final class VerticalReaderViewController: UIViewController {
    let collectionView: UICollectionView
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
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .vertical
        flowLayout.minimumLineSpacing = 10
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = .zero
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
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
        collectionView.contentInsetAdjustmentBehavior = .automatic
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
        nextPageCommand.discoverabilityTitle = "Next Page"

        let previousPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: [],
            action: #selector(handleRetreatPage)
        )
        previousPageCommand.discoverabilityTitle = "Previous Page"

        let spaceAdvanceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        spaceAdvanceCommand.discoverabilityTitle = "Next Page"

        let shiftSpaceRetreatCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [.shift],
            action: #selector(handleRetreatPage)
        )
        shiftSpaceRetreatCommand.discoverabilityTitle = "Previous Page"

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
        accessibilityLabel = "Page \(pageNumber)"
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
            return "Page \(index + 1) could not be decoded."
        }
    }
}
