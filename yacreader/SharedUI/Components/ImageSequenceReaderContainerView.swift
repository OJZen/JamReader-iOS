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
        private var lastReportedPageIndex: Int?

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
            self.lastReportedPageIndex = currentPageIndex
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

        func update(
            document: ImageSequenceComicDocument,
            layout: ReaderDisplayLayout,
            requestedPageIndex: Int
        ) {
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
            ) { [weak self] completed in
                guard let self, completed else {
                    return
                }

                self.notifyPageChangedIfNeeded(spread.primaryPageIndex)
                self.trimCache(around: spreadIndex)
                self.prefetchAround(spreadIndex: spreadIndex)
            }
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
            notifyPageChangedIfNeeded(spread.primaryPageIndex)
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

        private func notifyPageChangedIfNeeded(_ pageIndex: Int) {
            guard lastReportedPageIndex != pageIndex else {
                return
            }

            lastReportedPageIndex = pageIndex
            DispatchQueue.main.async { [onPageChanged] in
                onPageChanged(pageIndex)
            }
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
private final class ComicImageSpreadViewController: UIViewController {
    let spreadIndex: Int

    private let spread: ReaderSpreadDescriptor
    private let document: ImageSequenceComicDocument
    private let layout: ReaderDisplayLayout
    private let zoomablePageView = ZoomableImagePageView()
    private let rotationContainerView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    private var imageViews: [UIImageView] = []
    private var loadedPages: [LoadedComicPage] = []
    private var hasStartedLoading = false
    private var loadTask: Task<Void, Never>?
    private var lastViewportSize: CGSize = .zero
    private var needsViewportResetOnNextLayout = true
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        needsViewportResetOnNextLayout = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        zoomablePageView.tapEdgeRatio = preferredTapEdgeRatio()

        let viewportSize = zoomablePageView.bounds.size
        let viewportDidChange = lastViewportSize != .zero && !lastViewportSize.equalTo(viewportSize)
        lastViewportSize = viewportSize
        let shouldResetViewport = viewportDidChange || needsViewportResetOnNextLayout
        if layoutLoadedPages(resetZoomScale: shouldResetViewport), shouldResetViewport {
            needsViewportResetOnNextLayout = false
        }
    }

    private func configureSubviews() {
        zoomablePageView.translatesAutoresizingMaskIntoConstraints = false
        zoomablePageView.tapEdgeRatio = preferredTapEdgeRatio()
        zoomablePageView.onTapRegion = { [weak self] tapRegion in
            self?.onTapRegion(tapRegion)
        }

        rotationContainerView.backgroundColor = .black
        zoomablePageView.contentContainerView.addSubview(rotationContainerView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        view.addSubview(zoomablePageView)
        view.addSubview(activityIndicator)
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            zoomablePageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomablePageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            zoomablePageView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomablePageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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
                if self.layoutLoadedPages(resetZoomScale: true) {
                    self.needsViewportResetOnNextLayout = false
                }
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
            imageView.contentMode = .scaleToFill
            imageView.backgroundColor = .black
            rotationContainerView.addSubview(imageView)
            return imageView
        }
    }

    @discardableResult
    private func layoutLoadedPages(resetZoomScale: Bool) -> Bool {
        guard !loadedPages.isEmpty else {
            zoomablePageView.clearContentLayout()
            return false
        }

        let boundsSize = zoomablePageView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else {
            return false
        }

        let spacing: CGFloat = loadedPages.count > 1 ? 12 : 0
        let naturalSizes = loadedPages.map(\.image.size)
        let naturalContentHeight = naturalSizes.map(\.height).max() ?? 0
        let naturalContentWidth = naturalSizes.reduce(CGFloat(0)) { partialResult, size in
            partialResult + size.width
        } + CGFloat(max(0, loadedPages.count - 1)) * spacing

        guard naturalContentWidth > 0, naturalContentHeight > 0 else {
            return false
        }

        var currentX: CGFloat = 0
        for (imageView, imageSize) in zip(imageViews, naturalSizes) {
            let originY = (naturalContentHeight - imageSize.height) * 0.5
            imageView.frame = CGRect(origin: CGPoint(x: currentX, y: originY), size: imageSize)
            currentX += imageSize.width + spacing
        }

        let naturalContentSize = CGSize(width: naturalContentWidth, height: naturalContentHeight)
        let rotatedContentSize = layout.rotation.rotatedSize(for: naturalContentSize)
        let shouldSnapToPreferredViewport = resetZoomScale || zoomablePageView.isAtPreferredZoom

        rotationContainerView.transform = .identity
        rotationContainerView.frame = CGRect(origin: .zero, size: rotatedContentSize)
        rotationContainerView.bounds = CGRect(origin: .zero, size: naturalContentSize)
        rotationContainerView.center = CGPoint(
            x: rotatedContentSize.width * 0.5,
            y: rotatedContentSize.height * 0.5
        )
        rotationContainerView.transform = CGAffineTransform(rotationAngle: layout.rotation.radians)

        zoomablePageView.configureContentLayout(
            size: rotatedContentSize,
            fitMode: layout.fitMode,
            resetZoomScale: shouldSnapToPreferredViewport
        )
        return true
    }

    private func presentError(_ message: String) {
        loadedPages = []
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        rotationContainerView.transform = .identity
        rotationContainerView.bounds = .zero
        rotationContainerView.frame = .zero
        zoomablePageView.clearContentLayout()
        messageLabel.text = message
        messageLabel.isHidden = false
    }

    func restorePreferredViewportState() {
        guard !loadedPages.isEmpty else {
            return
        }

        needsViewportResetOnNextLayout = true
        if layoutLoadedPages(resetZoomScale: true) {
            needsViewportResetOnNextLayout = false
        } else {
            zoomablePageView.restorePreferredViewportState()
        }
    }

    private func preferredTapEdgeRatio() -> CGFloat {
        traitCollection.horizontalSizeClass == .regular ? 0.18 : 0.24
    }

    private func preferredDecodeMaxPixelSize() -> Int {
        let bounds = zoomablePageView.bounds == .zero ? view.bounds : zoomablePageView.bounds
        let baseDimension = max(bounds.width, bounds.height)
        let normalizedDimension = max(baseDimension, 720)
        let screenScale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let zoomFactor = min(max(zoomablePageView.maximumZoomScale, 2.5), 3.5)
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
