import SwiftUI
import ImageIO
import UIKit

enum ReaderTapRegion {
    case leading
    case center
    case trailing
}

struct ImageSequenceReaderContainerView: UIViewControllerRepresentable {
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

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = ReaderPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )

        context.coordinator.attach(to: pageViewController)
        context.coordinator.displaySpread(containing: clampedPageIndex(initialPageIndex), animated: false)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
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

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        private weak var pageViewController: UIPageViewController?
        private var controllerCache: [Int: ComicImageSpreadViewController] = [:]
        private var prefetchTask: Task<Void, Never>?
        private var memoryWarningObserver: NSObjectProtocol?
        private let pageTurnFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

        private(set) var document: ImageSequenceComicDocument
        private(set) var layout: ReaderDisplayLayout
        private(set) var spreads: [ReaderSpreadDescriptor]
        private(set) var currentPageIndex: Int
        private(set) var currentSpreadIndex: Int
        var onPageChanged: (Int) -> Void
        var onReaderTap: (ReaderTapRegion) -> Void

        init(
            document: ImageSequenceComicDocument,
            layout: ReaderDisplayLayout,
            currentPageIndex: Int,
            onPageChanged: @escaping (Int) -> Void,
            onReaderTap: @escaping (ReaderTapRegion) -> Void
        ) {
            self.document = document
            self.layout = layout
            self.spreads = ReaderSpreadDescriptor.makeSpreads(
                pageCount: document.pageCount,
                layout: layout
            )
            self.currentPageIndex = currentPageIndex
            self.currentSpreadIndex = ReaderSpreadDescriptor.spreadIndex(
                containing: currentPageIndex,
                in: spreads
            ) ?? 0
            self.onPageChanged = onPageChanged
            self.onReaderTap = onReaderTap
            self.pageTurnFeedbackGenerator.prepare()
        }

        deinit {
            prefetchTask?.cancel()
            if let memoryWarningObserver {
                NotificationCenter.default.removeObserver(memoryWarningObserver)
            }
        }

        func attach(to pageViewController: UIPageViewController) {
            self.pageViewController = pageViewController
            pageViewController.dataSource = self
            pageViewController.delegate = self
            observeMemoryWarningsIfNeeded()

            if let keyboardEnabledPageViewController = pageViewController as? ReaderPageViewController {
                keyboardEnabledPageViewController.onAdvance = { [weak self] in
                    self?.navigateByReadingOrder(step: 1)
                }
                keyboardEnabledPageViewController.onRetreat = { [weak self] in
                    self?.navigateByReadingOrder(step: -1)
                }
            }
        }

        func update(document: ImageSequenceComicDocument, layout: ReaderDisplayLayout, requestedPageIndex: Int) {
            let documentChanged = self.document.url != document.url || self.document.pageNames != document.pageNames
            let layoutChanged = self.layout != layout

            self.document = document
            self.layout = layout

            if documentChanged || layoutChanged {
                spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: document.pageCount, layout: layout)
                controllerCache.removeAll()
                displaySpread(containing: requestedPageIndex, animated: false)
                return
            }

            guard requestedPageIndex != currentPageIndex else {
                return
            }

            displaySpread(containing: requestedPageIndex, animated: false)
        }

        func displaySpread(containing pageIndex: Int, animated: Bool) {
            guard let spreadIndex = ReaderSpreadDescriptor.spreadIndex(containing: pageIndex, in: spreads) else {
                return
            }

            displaySpread(at: spreadIndex, animated: animated)
        }

        func displaySpread(at spreadIndex: Int, animated: Bool) {
            guard let pageViewController,
                  let controller = controller(forSpreadIndex: spreadIndex)
            else {
                return
            }

            let direction = navigationDirection(for: spreadIndex)
            let spread = spreads[spreadIndex]
            currentSpreadIndex = spreadIndex
            currentPageIndex = spread.primaryPageIndex

            pageViewController.setViewControllers(
                [controller],
                direction: direction,
                animated: animated
            )

            onPageChanged(spread.primaryPageIndex)
            trimCache(around: spreadIndex)
            prefetchAround(spreadIndex: spreadIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let spreadController = viewController as? ComicImageSpreadViewController else {
                return nil
            }

            let targetSpreadIndex = layout.readingDirection == .rightToLeft
                ? spreadController.spreadIndex + 1
                : spreadController.spreadIndex - 1

            return controller(forSpreadIndex: targetSpreadIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let spreadController = viewController as? ComicImageSpreadViewController else {
                return nil
            }

            let targetSpreadIndex = layout.readingDirection == .rightToLeft
                ? spreadController.spreadIndex - 1
                : spreadController.spreadIndex + 1

            return controller(forSpreadIndex: targetSpreadIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let controller = pageViewController.viewControllers?.first as? ComicImageSpreadViewController,
                  spreads.indices.contains(controller.spreadIndex)
            else {
                return
            }

            let spread = spreads[controller.spreadIndex]
            currentSpreadIndex = controller.spreadIndex
            currentPageIndex = spread.primaryPageIndex
            onPageChanged(spread.primaryPageIndex)
            trimCache(around: controller.spreadIndex)
            prefetchAround(spreadIndex: controller.spreadIndex)
        }

        private func controller(forSpreadIndex spreadIndex: Int) -> ComicImageSpreadViewController? {
            guard spreads.indices.contains(spreadIndex) else {
                return nil
            }

            if let cachedController = controllerCache[spreadIndex] {
                return cachedController
            }

            let controller = ComicImageSpreadViewController(
                spreadIndex: spreadIndex,
                spread: spreads[spreadIndex],
                document: document,
                layout: layout,
                onTapRegion: { [weak self] tapRegion in
                    self?.handleTapRegion(tapRegion)
                }
            )
            controllerCache[spreadIndex] = controller
            return controller
        }

        private func navigationDirection(for targetSpreadIndex: Int) -> UIPageViewController.NavigationDirection {
            guard targetSpreadIndex != currentSpreadIndex else {
                return .forward
            }

            let isAdvancing = targetSpreadIndex > currentSpreadIndex
            switch layout.readingDirection {
            case .leftToRight:
                return isAdvancing ? .forward : .reverse
            case .rightToLeft:
                return isAdvancing ? .reverse : .forward
            }
        }

        private func navigateByReadingOrder(step: Int) {
            let adjustedStep: Int
            switch layout.readingDirection {
            case .leftToRight:
                adjustedStep = step
            case .rightToLeft:
                adjustedStep = -step
            }

            displaySpread(at: currentSpreadIndex + adjustedStep, animated: true)
        }

        private func handleTapRegion(_ tapRegion: ReaderTapRegion) {
            switch tapRegion {
            case .center:
                onReaderTap(.center)
            case .leading:
                let previousSpreadIndex = currentSpreadIndex
                let step = layout.readingDirection == .leftToRight ? -1 : 1
                navigateByReadingOrder(step: step)
                if currentSpreadIndex != previousSpreadIndex {
                    pageTurnFeedbackGenerator.impactOccurred()
                } else {
                    onReaderTap(.leading)
                }
            case .trailing:
                let previousSpreadIndex = currentSpreadIndex
                let step = layout.readingDirection == .leftToRight ? 1 : -1
                navigateByReadingOrder(step: step)
                if currentSpreadIndex != previousSpreadIndex {
                    pageTurnFeedbackGenerator.impactOccurred()
                } else {
                    onReaderTap(.trailing)
                }
            }
        }

        private func trimCache(around spreadIndex: Int) {
            let allowedRange = max(0, spreadIndex - 2)...(spreadIndex + 2)
            controllerCache = controllerCache.filter { allowedRange.contains($0.key) }
        }

        private func prefetchAround(spreadIndex: Int) {
            let prefetchRange = max(0, spreadIndex - 2)...min(spreads.count - 1, spreadIndex + 2)
            let nearbyPageIndices = Array(Set(prefetchRange
                .flatMap { spreads[$0].displayPageIndices(for: layout.readingDirection) }
                .filter { $0 != currentPageIndex }))
                .sorted()

            guard !nearbyPageIndices.isEmpty else {
                return
            }

            let pageSource = document.pageSource
            prefetchTask?.cancel()
            prefetchTask = Task(priority: .utility) {
                await pageSource.prefetchPages(at: nearbyPageIndices)
            }

            pageTurnFeedbackGenerator.prepare()
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
                self?.handleMemoryWarning()
            }
        }

        private func handleMemoryWarning() {
            prefetchTask?.cancel()
            prefetchTask = nil

            guard let currentController = controllerCache[currentSpreadIndex] else {
                controllerCache.removeAll()
                return
            }

            controllerCache.removeAll(keepingCapacity: true)
            controllerCache[currentSpreadIndex] = currentController
        }
    }
}

private final class ReaderPageViewController: UIPageViewController {
    var onAdvance: (() -> Void)?
    var onRetreat: (() -> Void)?

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
            input: UIKeyCommand.inputRightArrow,
            modifierFlags: [],
            action: #selector(handleAdvance)
        )
        nextPageCommand.discoverabilityTitle = "Next Page"

        let previousPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputLeftArrow,
            modifierFlags: [],
            action: #selector(handleRetreat)
        )
        previousPageCommand.discoverabilityTitle = "Previous Page"

        let nextPageDownCommand = UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: [],
            action: #selector(handleAdvance)
        )
        nextPageDownCommand.discoverabilityTitle = "Next Page"

        let previousPageUpCommand = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: [],
            action: #selector(handleRetreat)
        )
        previousPageUpCommand.discoverabilityTitle = "Previous Page"

        let nextPageSpaceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [],
            action: #selector(handleAdvance)
        )
        nextPageSpaceCommand.discoverabilityTitle = "Next Page"

        let previousPageShiftSpaceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [.shift],
            action: #selector(handleRetreat)
        )
        previousPageShiftSpaceCommand.discoverabilityTitle = "Previous Page"

        return [
            nextPageCommand,
            previousPageCommand,
            nextPageDownCommand,
            previousPageUpCommand,
            nextPageSpaceCommand,
            previousPageShiftSpaceCommand
        ]
    }

    @objc
    private func handleAdvance() {
        onAdvance?()
    }

    @objc
    private func handleRetreat() {
        onRetreat?()
    }
}

private struct LoadedComicPage: @unchecked Sendable {
    let index: Int
    let image: UIImage
}

@MainActor
private final class ComicImageSpreadViewController: UIViewController, UIScrollViewDelegate {
    let spreadIndex: Int

    private let spread: ReaderSpreadDescriptor
    private let document: ImageSequenceComicDocument
    private let layout: ReaderDisplayLayout
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let rotationContainerView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private lazy var doubleTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 2
        return gestureRecognizer
    }()
    private lazy var singleTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 1
        return gestureRecognizer
    }()

    private var imageViews: [UIImageView] = []
    private var loadedPages: [LoadedComicPage] = []
    private var hasStartedLoading = false
    private var loadTask: Task<Void, Never>?
    private let onTapRegion: (ReaderTapRegion) -> Void

    init(
        spreadIndex: Int,
        spread: ReaderSpreadDescriptor,
        document: ImageSequenceComicDocument,
        layout: ReaderDisplayLayout,
        onTapRegion: @escaping (ReaderTapRegion) -> Void
    ) {
        self.spreadIndex = spreadIndex
        self.spread = spread
        self.document = document
        self.layout = layout
        self.onTapRegion = onTapRegion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        configureSubviews()
        loadImagesIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutLoadedPages(resetZoomScale: false)
    }

    private func configureSubviews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.decelerationRate = .fast
        scrollView.isDirectionalLockEnabled = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        singleTapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        scrollView.addGestureRecognizer(singleTapGestureRecognizer)
        scrollView.addGestureRecognizer(doubleTapGestureRecognizer)

        contentView.backgroundColor = .black
        rotationContainerView.backgroundColor = .black
        scrollView.addSubview(contentView)
        contentView.addSubview(rotationContainerView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        view.addSubview(scrollView)
        view.addSubview(activityIndicator)
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadImagesIfNeeded() {
        guard !hasStartedLoading else {
            return
        }

        hasStartedLoading = true
        activityIndicator.startAnimating()
        messageLabel.isHidden = true

        let pageSource = document.pageSource
        let pageIndices = spread.displayPageIndices(for: layout.readingDirection)
        let pageNames = pageIndices.map { index in
            document.pageName(at: index) ?? "Page \(index + 1)"
        }
        let shouldPreferFullResolution = layout.fitMode == .originalSize
        let decodeMaxPixelSize = preferredDecodeMaxPixelSize()

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[LoadedComicPage], Error> in
                do {
                    var loadedPages: [LoadedComicPage] = []
                    loadedPages.reserveCapacity(pageIndices.count)

                    for index in pageIndices {
                        let data = try await pageSource.dataForPage(at: index)
                        guard let image = Self.decodeImage(
                            from: data,
                            maxPixelSize: decodeMaxPixelSize,
                            preferFullResolution: shouldPreferFullResolution
                        ) else {
                            throw ReaderSpreadImageError.decodeFailed(index: index)
                        }

                        loadedPages.append(LoadedComicPage(index: index, image: image))
                    }

                    return .success(loadedPages)
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else {
                return
            }

            self.activityIndicator.stopAnimating()

            switch result {
            case .success(let loadedPages):
                self.loadedPages = loadedPages
                self.messageLabel.isHidden = true
                self.configureImageViews(with: loadedPages)
                self.layoutLoadedPages(resetZoomScale: true)
            case .failure(let error):
                let fallbackMessage = pageNames.joined(separator: ", ")
                self.presentError(
                    error.localizedDescription.isEmpty
                        ? "Unable to decode spread: \(fallbackMessage)"
                        : error.localizedDescription
                )
            }
        }
    }

    private func configureImageViews(with loadedPages: [LoadedComicPage]) {
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = loadedPages.map { loadedPage in
            let imageView = UIImageView(image: loadedPage.image)
            imageView.contentMode = .center
            imageView.backgroundColor = .black
            rotationContainerView.addSubview(imageView)
            return imageView
        }
    }

    private func layoutLoadedPages(resetZoomScale: Bool) {
        guard !loadedPages.isEmpty else {
            scrollView.contentSize = .zero
            return
        }

        let boundsSize = scrollView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else {
            return
        }

        let spacing: CGFloat = loadedPages.count > 1 ? 12 : 0
        let naturalSizes = loadedPages.map(\.image.size)
        let naturalContentHeight = naturalSizes.map(\.height).max() ?? 0
        let naturalContentWidth = naturalSizes.reduce(CGFloat(0)) { partialResult, size in
            partialResult + size.width
        } + CGFloat(max(0, loadedPages.count - 1)) * spacing

        guard naturalContentWidth > 0, naturalContentHeight > 0 else {
            return
        }

        var currentX: CGFloat = 0
        for (imageView, imageSize) in zip(imageViews, naturalSizes) {
            let originY = (naturalContentHeight - imageSize.height) * 0.5
            imageView.frame = CGRect(origin: CGPoint(x: currentX, y: originY), size: imageSize)
            currentX += imageSize.width + spacing
        }

        let naturalContentSize = CGSize(width: naturalContentWidth, height: naturalContentHeight)
        let rotatedContentSize = layout.rotation.rotatedSize(for: naturalContentSize)

        rotationContainerView.bounds = CGRect(origin: .zero, size: naturalContentSize)
        rotationContainerView.center = CGPoint(
            x: rotatedContentSize.width * 0.5,
            y: rotatedContentSize.height * 0.5
        )
        rotationContainerView.transform = CGAffineTransform(rotationAngle: layout.rotation.radians)

        contentView.frame = CGRect(origin: .zero, size: rotatedContentSize)
        scrollView.contentSize = contentView.bounds.size

        let minimumZoomScale = preferredZoomScale(
            boundsSize: boundsSize,
            contentSize: rotatedContentSize
        )
        let maximumZoomScale = max(minimumZoomScale * 4, 4)
        let previousMinimumZoomScale = scrollView.minimumZoomScale
        // When decoding completes before the page gets a real viewport size, the first
        // successful layout should still snap to fit instead of preserving the placeholder 1x zoom.
        let wasAtFitZoom = scrollView.zoomScale <= previousMinimumZoomScale + 0.01
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale

        if resetZoomScale || wasAtFitZoom {
            scrollView.zoomScale = minimumZoomScale
        } else {
            scrollView.zoomScale = min(max(scrollView.zoomScale, minimumZoomScale), maximumZoomScale)
        }

        centerContentIfNeeded()
        updatePanGestureAvailability()
    }

    private func preferredZoomScale(boundsSize: CGSize, contentSize: CGSize) -> CGFloat {
        let widthScale = boundsSize.width / contentSize.width
        let heightScale = boundsSize.height / contentSize.height

        let preferredScale: CGFloat
        switch layout.fitMode {
        case .page:
            preferredScale = min(widthScale, heightScale)
        case .width:
            preferredScale = widthScale
        case .height:
            preferredScale = heightScale
        case .originalSize:
            preferredScale = 1
        }

        return max(preferredScale, 0.01)
    }

    private func centerContentIfNeeded() {
        let contentSize = CGSize(
            width: contentView.frame.width * scrollView.zoomScale,
            height: contentView.frame.height * scrollView.zoomScale
        )

        let horizontalInset = max(0, (scrollView.bounds.width - contentSize.width) * 0.5)
        let verticalInset = max(0, (scrollView.bounds.height - contentSize.height) * 0.5)
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContentIfNeeded()
        updatePanGestureAvailability()
    }

    @objc
    private func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            onTapRegion(.center)
            return
        }

        let tapLocation = gestureRecognizer.location(in: view)
        let viewWidth = max(view.bounds.width, 1)
        let horizontalRatio = tapLocation.x / viewWidth
        let edgeRatio = preferredTapEdgeRatio()

        if horizontalRatio < edgeRatio {
            onTapRegion(.leading)
        } else if horizontalRatio > 1 - edgeRatio {
            onTapRegion(.trailing)
        } else {
            onTapRegion(.center)
        }
    }

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard !loadedPages.isEmpty else {
            return
        }

        let minimumZoomScale = scrollView.minimumZoomScale
        let maximumZoomScale = scrollView.maximumZoomScale

        if scrollView.zoomScale > minimumZoomScale + 0.01 {
            scrollView.setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetZoomScale = min(maximumZoomScale, minimumZoomScale * 2.5)
        let tapLocation = gestureRecognizer.location(in: contentView)
        let zoomRectSize = CGSize(
            width: scrollView.bounds.width / targetZoomScale,
            height: scrollView.bounds.height / targetZoomScale
        )
        let zoomRect = CGRect(
            x: tapLocation.x - zoomRectSize.width * 0.5,
            y: tapLocation.y - zoomRectSize.height * 0.5,
            width: zoomRectSize.width,
            height: zoomRectSize.height
        )

        scrollView.zoom(to: zoomRect, animated: true)
    }

    private func presentError(_ message: String) {
        loadedPages = []
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        rotationContainerView.transform = .identity
        rotationContainerView.bounds = .zero
        contentView.frame = .zero
        scrollView.contentInset = .zero
        scrollView.contentSize = .zero
        updatePanGestureAvailability()
        messageLabel.text = message
        messageLabel.isHidden = false
    }

    private func preferredTapEdgeRatio() -> CGFloat {
        traitCollection.horizontalSizeClass == .regular ? 0.18 : 0.24
    }

    private func zoomedContentSize() -> CGSize {
        CGSize(
            width: contentView.bounds.width * scrollView.zoomScale,
            height: contentView.bounds.height * scrollView.zoomScale
        )
    }

    private func updatePanGestureAvailability() {
        let isZoomedBeyondMinimum = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        scrollView.panGestureRecognizer.isEnabled = isZoomedBeyondMinimum
    }

    private func preferredDecodeMaxPixelSize() -> Int {
        let bounds = view.bounds
        let baseDimension = max(bounds.width, bounds.height)
        let normalizedDimension = max(baseDimension, 720)
        let screenScale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let zoomFactor = min(max(scrollView.maximumZoomScale, 2.5), 3.5)
        let spreadFactor: CGFloat = spread.pageIndices.count > 1 ? 1.2 : 1.5
        let estimatedPixels = normalizedDimension * screenScale * zoomFactor * spreadFactor
        return max(1600, min(Int(estimatedPixels.rounded()), 8192))
    }

    nonisolated private static func decodeImage(
        from data: Data,
        maxPixelSize: Int,
        preferFullResolution: Bool
    ) -> UIImage? {
        guard !preferFullResolution else {
            return UIImage(data: data)
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            let maxSourceDimension = max(pixelWidth, pixelHeight)
            if maxSourceDimension <= CGFloat(maxPixelSize) * 1.1 {
                return UIImage(data: data)
            }
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

private enum ReaderSpreadImageError: LocalizedError {
    case decodeFailed(index: Int)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let index):
            return "The image data for page \(index + 1) could not be decoded."
        }
    }
}
