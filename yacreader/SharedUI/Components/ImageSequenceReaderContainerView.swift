import SwiftUI
import ImageIO
import UIKit

struct ImageSequenceReaderContainerView: UIViewControllerRepresentable {
    let document: ImageSequenceComicDocument
    let initialPageIndex: Int
    let layout: ReaderDisplayLayout
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void

    func makeUIViewController(context: Context) -> ReaderPagedCollectionViewController {
        ReaderPagedCollectionViewController(
            document: document,
            layout: layout,
            onPageChanged: onPageChanged,
            onReaderTap: onReaderTap,
            initialPageIndex: clampedPageIndex(initialPageIndex)
        )
    }

    func updateUIViewController(_ viewController: ReaderPagedCollectionViewController, context: Context) {
        viewController.onPageChanged = onPageChanged
        viewController.onReaderTap = onReaderTap
        viewController.update(
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
}

@MainActor
final class ReaderPagedCollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onPageChanged: (Int) -> Void
    var onReaderTap: (ReaderTapRegion) -> Void

    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.isPagingEnabled = true
        collectionView.alwaysBounceVertical = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ReaderPagedCollectionViewCell.self, forCellWithReuseIdentifier: ReaderPagedCollectionViewCell.reuseIdentifier)
        return collectionView
    }()

    private var document: ImageSequenceComicDocument
    private var layout: ReaderDisplayLayout
    private var spreads: [ReaderSpreadDescriptor]
    private var controllerCache: [Int: ComicImageSpreadViewController] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?
    private let pageTurnFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var lastReportedPageIndex: Int?
    private var currentPageIndex: Int
    private var currentSpreadIndex: Int
    private var lastViewportSize: CGSize = .zero
    private var pendingScrollSpreadIndex: Int?

    init(
        document: ImageSequenceComicDocument,
        layout: ReaderDisplayLayout,
        onPageChanged: @escaping (Int) -> Void,
        onReaderTap: @escaping (ReaderTapRegion) -> Void,
        initialPageIndex: Int
    ) {
        self.document = document
        self.layout = layout
        self.spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: document.pageCount, layout: layout)
        self.currentPageIndex = initialPageIndex
        self.currentSpreadIndex = ReaderSpreadDescriptor.spreadIndex(containing: initialPageIndex, in: spreads) ?? 0
        self.lastReportedPageIndex = initialPageIndex
        self.onPageChanged = onPageChanged
        self.onReaderTap = onReaderTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prefetchTask?.cancel()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        observeMemoryWarningsIfNeeded()
        pageTurnFeedbackGenerator.prepare()
        collectionView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        prepareAndScrollToCurrentSpreadIfNeeded(animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let viewportSize = collectionView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        if lastViewportSize != viewportSize {
            lastViewportSize = viewportSize
            flowLayout.itemSize = viewportSize
            flowLayout.invalidateLayout()
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            prepareAndScrollToCurrentSpreadIfNeeded(animated: false)
        } else if pendingScrollSpreadIndex != nil {
            prepareAndScrollToCurrentSpreadIfNeeded(animated: false)
        }
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
            self.spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: document.pageCount, layout: layout)
            clearControllerCache()
            collectionView.reloadData()
            displaySpread(containing: requestedPageIndex, animated: false)
            return
        }

        guard requestedPageIndex != currentPageIndex else {
            return
        }

        displaySpread(containing: requestedPageIndex, animated: false)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        spreads.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ReaderPagedCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? ReaderPagedCollectionViewCell else {
            return UICollectionViewCell()
        }

        guard let controller = controller(forSpreadIndex: indexPath.item) else {
            cell.clearHostedView()
            return cell
        }

        cell.setHostedView(controller.view)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        controller(forSpreadIndex: indexPath.item)?.prepareForPresentation()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finalizeVisibleSpread()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            finalizeVisibleSpread()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finalizeVisibleSpread()
    }

    private func displaySpread(containing pageIndex: Int, animated: Bool) {
        guard let spreadIndex = ReaderSpreadDescriptor.spreadIndex(containing: pageIndex, in: spreads) else {
            return
        }

        displaySpread(at: spreadIndex, animated: animated)
    }

    private func displaySpread(at spreadIndex: Int, animated: Bool) {
        guard spreads.indices.contains(spreadIndex) else {
            return
        }

        controller(forSpreadIndex: spreadIndex)?.prepareForPresentation()
        currentSpreadIndex = spreadIndex
        currentPageIndex = spreads[spreadIndex].primaryPageIndex
        scrollToSpread(spreadIndex, animated: animated)

        if !animated {
            finalizeVisibleSpread()
        }
    }

    private func scrollToSpread(_ spreadIndex: Int, animated: Bool) {
        guard collectionView.bounds.width > 0 else {
            pendingScrollSpreadIndex = spreadIndex
            return
        }

        pendingScrollSpreadIndex = nil
        let targetOffset = CGPoint(
            x: CGFloat(spreadIndex) * collectionView.bounds.width,
            y: 0
        )
        collectionView.setContentOffset(targetOffset, animated: animated)
    }

    private func prepareAndScrollToCurrentSpreadIfNeeded(animated: Bool) {
        guard spreads.indices.contains(currentSpreadIndex) else {
            return
        }

        controller(forSpreadIndex: currentSpreadIndex)?.prepareForPresentation()
        scrollToSpread(currentSpreadIndex, animated: animated)
    }

    private func finalizeVisibleSpread() {
        guard collectionView.bounds.width > 0, !spreads.isEmpty else {
            return
        }

        let rawIndex = Int(round(collectionView.contentOffset.x / collectionView.bounds.width))
        let spreadIndex = min(max(rawIndex, 0), spreads.count - 1)
        let spread = spreads[spreadIndex]
        let previousSpreadIndex = currentSpreadIndex

        currentSpreadIndex = spreadIndex
        currentPageIndex = spread.primaryPageIndex
        if spreadIndex != previousSpreadIndex {
            controller(forSpreadIndex: spreadIndex)?.prepareForPresentation()
        }
        notifyPageChangedIfNeeded(spread.primaryPageIndex)
        trimCache(around: spreadIndex)
        prefetchAround(spreadIndex: spreadIndex)
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
        addChild(controller)
        controller.didMove(toParent: self)
        controllerCache[spreadIndex] = controller
        return controller
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

    private func trimCache(around spreadIndex: Int) {
        let allowedRange = max(0, spreadIndex - 2)...(spreadIndex + 2)
        let obsoleteKeys = controllerCache.keys.filter { !allowedRange.contains($0) }
        for key in obsoleteKeys {
            removeCachedController(forSpreadIndex: key)
        }
    }

    private func clearControllerCache() {
        let keys = Array(controllerCache.keys)
        for key in keys {
            removeCachedController(forSpreadIndex: key)
        }
    }

    private func removeCachedController(forSpreadIndex spreadIndex: Int) {
        guard let controller = controllerCache.removeValue(forKey: spreadIndex) else {
            return
        }

        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
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
            Task { @MainActor [weak self] in
                self?.handleMemoryWarning()
            }
        }
    }

    private func handleMemoryWarning() {
        prefetchTask?.cancel()
        prefetchTask = nil

        let keys = Array(controllerCache.keys)
        for key in keys where key != currentSpreadIndex {
            removeCachedController(forSpreadIndex: key)
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

    @objc
    private func handleAdvance() {
        navigateByReadingOrder(step: 1)
    }

    @objc
    private func handleRetreat() {
        navigateByReadingOrder(step: -1)
    }
}

private final class ReaderPagedCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderPagedCollectionViewCell"

    private weak var hostedView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black
        clipsToBounds = true
        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearHostedView()
    }

    func setHostedView(_ view: UIView) {
        guard hostedView !== view else {
            return
        }

        clearHostedView()
        hostedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func clearHostedView() {
        hostedView?.removeFromSuperview()
        hostedView = nil
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

    func prepareForPresentation() {
        loadViewIfNeeded()
        needsViewportResetOnNextLayout = true
        view.setNeedsLayout()

        guard !loadedPages.isEmpty else {
            return
        }

        view.layoutIfNeeded()
        if layoutLoadedPages(resetZoomScale: true) {
            needsViewportResetOnNextLayout = false
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
