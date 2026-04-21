import SwiftUI
import UIKit

struct ReaderThumbnailBrowserUIKitContainer: UIViewControllerRepresentable {
    let document: ComicDocument
    let currentPageIndex: Int
    let focusCurrentRequestID: Int
    let onSelectPage: (Int) -> Void

    func makeUIViewController(context: Context) -> ReaderThumbnailBrowserViewController {
        let viewController = ReaderThumbnailBrowserViewController()
        viewController.apply(
            document: document,
            currentPageIndex: currentPageIndex,
            focusCurrentRequestID: focusCurrentRequestID,
            onSelectPage: onSelectPage
        )
        return viewController
    }

    func updateUIViewController(_ viewController: ReaderThumbnailBrowserViewController, context: Context) {
        viewController.apply(
            document: document,
            currentPageIndex: currentPageIndex,
            focusCurrentRequestID: focusCurrentRequestID,
            onSelectPage: onSelectPage
        )
    }
}

@MainActor
final class ReaderThumbnailBrowserViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    private enum Section: Int, CaseIterable {
        case overview
        case pages
    }

    private enum OverviewItem: Int, CaseIterable {
        case summary
        case jump
    }

    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    private let thumbnailCache = NSCache<NSNumber, UIImage>()
    private var thumbnailTasks: [Int: Task<Void, Never>] = [:]
    private var summaryThumbnailTask: Task<Void, Never>?

    private weak var summaryCell: ReaderThumbnailBrowserSummaryCell?
    private weak var jumpCell: ReaderThumbnailBrowserJumpCell?
    private weak var pagesHeaderView: ReaderThumbnailBrowserSectionHeaderView?

    private var document: ComicDocument?
    private var currentPageIndex = 0
    private var selectedPageNumber = 1
    private var focusCurrentRequestID = 0
    private var hasPerformedInitialScroll = false
    private var isEditingJumpField = false
    private var currentMetrics = ReaderThumbnailBrowserMetrics(containerWidth: 0, isPadLayout: UIDevice.current.userInterfaceIdiom == .pad)
    private var onSelectPage: ((Int) -> Void)?

    private var pageCount: Int {
        max(document?.pageCount ?? 0, 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        configureCollectionView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        applyNavigationBarAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let metrics = makeMetrics(containerWidth: view.bounds.width)
        if metrics != currentMetrics {
            currentMetrics = metrics
            collectionView.collectionViewLayout = makeLayout()
            collectionView.reloadData()
            configureVisibleOverview()
        }

        collectionView.scrollIndicatorInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(view.safeAreaInsets.bottom, 0),
            right: 0
        )

        if !hasPerformedInitialScroll, pageCount > 0 {
            hasPerformedInitialScroll = true
            scrollToPage(currentPageIndex, animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard isBeingDismissed || navigationController?.isBeingDismissed == true else {
            return
        }

        summaryThumbnailTask?.cancel()
        cancelThumbnailTasks()
    }

    func apply(
        document: ComicDocument,
        currentPageIndex: Int,
        focusCurrentRequestID: Int,
        onSelectPage: @escaping (Int) -> Void
    ) {
        self.onSelectPage = onSelectPage

        let documentChanged = documentIdentityChanged(to: document)
        self.document = document

        let clampedPageIndex = clamp(pageIndex: currentPageIndex, pageCount: max(document.pageCount ?? 0, 0))
        let previousPageIndex = self.currentPageIndex
        self.currentPageIndex = clampedPageIndex

        if documentChanged {
            hasPerformedInitialScroll = false
            summaryThumbnailTask?.cancel()
            cancelThumbnailTasks()
            thumbnailCache.removeAllObjects()
            if !isEditingJumpField {
                selectedPageNumber = clampedPageIndex + 1
            }
            collectionView.reloadData()
        } else if previousPageIndex != clampedPageIndex {
            if !isEditingJumpField {
                selectedPageNumber = clampedPageIndex + 1
            }
            reloadPageIndicators(previous: previousPageIndex, current: clampedPageIndex)
            configureVisibleOverview()
        }

        if focusCurrentRequestID != self.focusCurrentRequestID {
            self.focusCurrentRequestID = focusCurrentRequestID
            selectedPageNumber = clampedPageIndex + 1
            configureVisibleOverview()
            scrollToPage(clampedPageIndex, animated: true)
        }

        configureVisibleOverview()
    }

    private func configureVisibleOverview() {
        let currentPageNumber = pageCount > 0 ? currentPageIndex + 1 : 0
        let progressPercent = pageCount > 0 ? Int((Double(currentPageNumber) / Double(pageCount) * 100).rounded()) : 0
        let remainingPageCount = max(pageCount - currentPageNumber, 0)

        summaryCell?.configure(
            currentPageNumber: currentPageNumber,
            pageCount: pageCount,
            progressPercent: progressPercent,
            remainingPageCount: remainingPageCount
        )
        jumpCell?.configure(
            selectedPageNumber: clampedSelectedPageNumber,
            pageCount: pageCount
        )
        pagesHeaderView?.configure(title: "All Pages", count: pageCount)
        loadSummaryThumbnailIfNeeded()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            return 0
        }

        switch section {
        case .overview:
            return OverviewItem.allCases.count
        case .pages:
            return pageCount
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UICollectionViewCell()
        }

        switch section {
        case .overview:
            return overviewCell(for: indexPath, in: collectionView)
        case .pages:
            return pageCell(for: indexPath, in: collectionView)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: ReaderThumbnailBrowserSectionHeaderView.reuseIdentifier,
                for: indexPath
              ) as? ReaderThumbnailBrowserSectionHeaderView
        else {
            return UICollectionReusableView()
        }

        headerView.configure(title: "All Pages", count: pageCount)
        pagesHeaderView = headerView
        return headerView
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.section == Section.pages.rawValue else {
            return
        }

        onSelectPage?(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.section == Section.pages.rawValue {
            ensureThumbnailLoaded(at: indexPath.item, priority: .utility)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.section == Section.pages.rawValue {
            guard !collectionView.indexPathsForVisibleItems.contains(indexPath) else {
                continue
            }

            thumbnailTasks[indexPath.item]?.cancel()
            thumbnailTasks[indexPath.item] = nil
        }
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self

        collectionView.register(
            ReaderThumbnailBrowserSummaryCell.self,
            forCellWithReuseIdentifier: ReaderThumbnailBrowserSummaryCell.reuseIdentifier
        )
        collectionView.register(
            ReaderThumbnailBrowserJumpCell.self,
            forCellWithReuseIdentifier: ReaderThumbnailBrowserJumpCell.reuseIdentifier
        )
        collectionView.register(
            ReaderThumbnailBrowserPageCell.self,
            forCellWithReuseIdentifier: ReaderThumbnailBrowserPageCell.reuseIdentifier
        )
        collectionView.register(
            ReaderThumbnailBrowserSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ReaderThumbnailBrowserSectionHeaderView.reuseIdentifier
        )

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self, let section = Section(rawValue: sectionIndex) else {
                return nil
            }

            let metrics = self.makeMetrics(containerWidth: environment.container.effectiveContentSize.width)
            switch section {
            case .overview:
                return self.overviewLayoutSection(metrics: metrics)
            case .pages:
                return self.pagesLayoutSection(metrics: metrics)
            }
        }
    }

    private func overviewLayoutSection(metrics: ReaderThumbnailBrowserMetrics) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(metrics.usesSplitCards ? 0.5 : 1.0),
            heightDimension: .absolute(metrics.overviewCardHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        if metrics.usesSplitCards {
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: metrics.columnSpacing * 0.5)
            let trailingItem = NSCollectionLayoutItem(layoutSize: itemSize)
            trailingItem.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: metrics.columnSpacing * 0.5, bottom: 0, trailing: 0)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(metrics.overviewCardHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, trailingItem])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: Spacing.md,
                leading: metrics.horizontalInset,
                bottom: Spacing.md,
                trailing: metrics.horizontalInset
            )
            return section
        } else {
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: metrics.rowSpacing * 0.5, trailing: 0)
            let secondItem = NSCollectionLayoutItem(layoutSize: itemSize)
            secondItem.contentInsets = NSDirectionalEdgeInsets(top: metrics.rowSpacing * 0.5, leading: 0, bottom: 0, trailing: 0)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute((metrics.overviewCardHeight * 2) + metrics.rowSpacing)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item, secondItem])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: Spacing.md,
                leading: metrics.horizontalInset,
                bottom: Spacing.md,
                trailing: metrics.horizontalInset
            )
            return section
        }
    }

    private func pagesLayoutSection(metrics: ReaderThumbnailBrowserMetrics) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(metrics.columns)),
            heightDimension: .absolute(metrics.pageCellHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: metrics.columnSpacing * 0.5,
            bottom: metrics.rowSpacing,
            trailing: metrics.columnSpacing * 0.5
        )

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(metrics.pageCellHeight + metrics.rowSpacing))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: metrics.columns)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: metrics.horizontalInset - (metrics.columnSpacing * 0.5),
            bottom: metrics.bottomInset,
            trailing: metrics.horizontalInset - (metrics.columnSpacing * 0.5)
        )

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(44)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        header.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: metrics.horizontalInset, bottom: Spacing.xs, trailing: metrics.horizontalInset)
        section.boundarySupplementaryItems = [header]
        return section
    }

    private func overviewCell(for indexPath: IndexPath, in collectionView: UICollectionView) -> UICollectionViewCell {
        guard let overviewItem = OverviewItem(rawValue: indexPath.item) else {
            return UICollectionViewCell()
        }

        switch overviewItem {
        case .summary:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ReaderThumbnailBrowserSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? ReaderThumbnailBrowserSummaryCell else {
                return UICollectionViewCell()
            }

            let currentPageNumber = pageCount > 0 ? currentPageIndex + 1 : 0
            let progressPercent = pageCount > 0 ? Int((Double(currentPageNumber) / Double(pageCount) * 100).rounded()) : 0
            let remainingPageCount = max(pageCount - currentPageNumber, 0)
            cell.configure(
                currentPageNumber: currentPageNumber,
                pageCount: pageCount,
                progressPercent: progressPercent,
                remainingPageCount: remainingPageCount
            )
            summaryCell = cell
            loadSummaryThumbnailIfNeeded()
            return cell

        case .jump:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ReaderThumbnailBrowserJumpCell.reuseIdentifier,
                for: indexPath
            ) as? ReaderThumbnailBrowserJumpCell else {
                return UICollectionViewCell()
            }

            cell.configure(
                selectedPageNumber: clampedSelectedPageNumber,
                pageCount: pageCount
            )
            cell.onPageNumberChanged = { [weak self] pageNumber in
                self?.handlePageNumberChanged(pageNumber)
            }
            cell.onSliderChanged = { [weak self] pageNumber in
                self?.handleSliderChanged(pageNumber)
            }
            cell.onGoTo = { [weak self] in
                self?.openSelectedPage()
            }
            cell.onLocate = { [weak self] in
                self?.locateSelectedPage()
            }
            cell.onEditingChanged = { [weak self] isEditing in
                self?.isEditingJumpField = isEditing
            }
            jumpCell = cell
            return cell
        }
    }

    private func pageCell(for indexPath: IndexPath, in collectionView: UICollectionView) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ReaderThumbnailBrowserPageCell.reuseIdentifier,
            for: indexPath
        ) as? ReaderThumbnailBrowserPageCell else {
            return UICollectionViewCell()
        }

        let pageIndex = indexPath.item
        cell.configure(pageNumber: pageIndex + 1, isCurrentPage: pageIndex == currentPageIndex)

        if let cachedImage = thumbnailCache.object(forKey: NSNumber(value: pageIndex)) {
            cell.setImage(cachedImage)
        } else if let previewImage = ReaderThumbnailBrowserImageResolver.previewImage(for: document, pageIndex: pageIndex) {
            cell.setImage(previewImage)
            ensureThumbnailLoaded(at: pageIndex, priority: .userInitiated)
        } else {
            cell.setLoadingState()
            ensureThumbnailLoaded(at: pageIndex, priority: .userInitiated)
        }

        return cell
    }

    private func ensureThumbnailLoaded(at pageIndex: Int, priority: TaskPriority) {
        guard pageIndex >= 0, pageIndex < pageCount else {
            return
        }

        let cacheKey = NSNumber(value: pageIndex)
        if thumbnailCache.object(forKey: cacheKey) != nil {
            return
        }

        guard thumbnailTasks[pageIndex] == nil, let document else {
            return
        }

        let maxPixelSize = currentMetrics.thumbnailMaxPixelSize
        thumbnailTasks[pageIndex] = Task(priority: priority) { [weak self] in
            guard let image = await ReaderThumbnailBrowserImageResolver.image(
                for: document,
                pageIndex: pageIndex,
                maxPixelSize: maxPixelSize
            ) else {
                await MainActor.run {
                    self?.thumbnailTasks[pageIndex] = nil
                }
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.thumbnailTasks[pageIndex] = nil
                self.thumbnailCache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: ReaderThumbnailBrowserImageResolver.cacheCost(for: image)
                )
                if let cell = self.collectionView.cellForItem(at: IndexPath(item: pageIndex, section: Section.pages.rawValue))
                    as? ReaderThumbnailBrowserPageCell {
                    cell.setImage(image)
                }
                if pageIndex == self.currentPageIndex {
                    self.summaryCell?.setThumbnailImage(image)
                }
            }
        }
    }

    private func loadSummaryThumbnailIfNeeded() {
        summaryThumbnailTask?.cancel()
        summaryCell?.setLoadingState()

        guard let document, pageCount > 0 else {
            summaryCell?.setUnavailableState()
            return
        }

        let currentPageIndex = self.currentPageIndex
        if let previewImage = ReaderThumbnailBrowserImageResolver.previewImage(for: document, pageIndex: currentPageIndex) {
            summaryCell?.setThumbnailImage(previewImage)
        }

        let maxPixelSize = currentMetrics.headerThumbnailMaxPixelSize
        summaryThumbnailTask = Task(priority: .userInitiated) { [weak self] in
            guard let image = await ReaderThumbnailBrowserImageResolver.image(
                for: document,
                pageIndex: currentPageIndex,
                maxPixelSize: maxPixelSize
            ) else {
                await MainActor.run {
                    if self?.currentPageIndex == currentPageIndex {
                        self?.summaryCell?.setUnavailableState()
                    }
                }
                return
            }

            await MainActor.run {
                guard let self, self.currentPageIndex == currentPageIndex else {
                    return
                }
                self.summaryCell?.setThumbnailImage(image)
            }
        }
    }

    private func handlePageNumberChanged(_ pageNumberText: String) {
        let digitsOnly = pageNumberText.filter(\.isNumber)
        if let pageNumber = Int(digitsOnly), pageCount > 0 {
            selectedPageNumber = min(max(pageNumber, 1), pageCount)
        } else if pageCount == 0 {
            selectedPageNumber = 0
        }
        jumpCell?.configure(selectedPageNumber: clampedSelectedPageNumber, pageCount: pageCount)
    }

    private func handleSliderChanged(_ pageNumber: Int) {
        guard pageCount > 0 else {
            return
        }

        selectedPageNumber = min(max(pageNumber, 1), pageCount)
        jumpCell?.configure(selectedPageNumber: clampedSelectedPageNumber, pageCount: pageCount)
    }

    private var clampedSelectedPageNumber: Int {
        guard pageCount > 0 else {
            return 0
        }

        return min(max(selectedPageNumber, 1), pageCount)
    }

    private func openSelectedPage() {
        guard pageCount > 0 else {
            return
        }

        onSelectPage?(clampedSelectedPageNumber - 1)
    }

    private func locateSelectedPage() {
        guard pageCount > 0 else {
            return
        }

        view.endEditing(true)
        scrollToPage(clampedSelectedPageNumber - 1, animated: true)
    }

    private func scrollToPage(_ pageIndex: Int, animated: Bool) {
        guard pageCount > 0 else {
            return
        }

        let indexPath = IndexPath(item: pageIndex, section: Section.pages.rawValue)
        guard collectionView.numberOfItems(inSection: Section.pages.rawValue) > pageIndex else {
            return
        }

        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }

    private func reloadPageIndicators(previous: Int, current: Int) {
        guard previous != current else {
            return
        }

        var indexPaths: [IndexPath] = []
        if previous >= 0, previous < pageCount {
            indexPaths.append(IndexPath(item: previous, section: Section.pages.rawValue))
        }
        if current >= 0, current < pageCount {
            indexPaths.append(IndexPath(item: current, section: Section.pages.rawValue))
        }

        if !indexPaths.isEmpty {
            collectionView.reloadItems(at: indexPaths)
        }
    }

    private func documentIdentityChanged(to newDocument: ComicDocument) -> Bool {
        guard let document else {
            return true
        }

        switch (document, newDocument) {
        case (.imageSequence(let lhs), .imageSequence(let rhs)):
            return lhs.url != rhs.url
                || lhs.pageNames != rhs.pageNames
                || ObjectIdentifier(lhs.pageSource) != ObjectIdentifier(rhs.pageSource)
        case (.pdf(let lhs), .pdf(let rhs)):
            return lhs.url != rhs.url
        case (.ebook(let lhs), .ebook(let rhs)):
            return lhs.url != rhs.url || lhs.documentID != rhs.documentID
        case (.unsupported(let lhs), .unsupported(let rhs)):
            return lhs.url != rhs.url || lhs.reason != rhs.reason
        default:
            return true
        }
    }

    private func clamp(pageIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else {
            return 0
        }

        return min(max(pageIndex, 0), pageCount - 1)
    }

    private func cancelThumbnailTasks() {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks.removeAll()
    }

    private func makeMetrics(containerWidth: CGFloat) -> ReaderThumbnailBrowserMetrics {
        ReaderThumbnailBrowserMetrics(
            containerWidth: containerWidth,
            isPadLayout: usesPadGridLayout(for: containerWidth)
        )
    }

    private func usesPadGridLayout(for containerWidth: CGFloat) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            || traitCollection.userInterfaceIdiom == .pad
            || containerWidth >= 700
    }

    private func applyNavigationBarAppearance() {
        if #available(iOS 26, *) {
            return
        }

        guard let navigationBar = navigationController?.navigationBar else {
            return
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.68)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.12)

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = appearance
        }
    }
}

private struct ReaderThumbnailBrowserMetrics: Equatable {
    let usesSplitCards: Bool
    let columns: Int
    let horizontalInset: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let overviewCardHeight: CGFloat
    let pageCellHeight: CGFloat
    let thumbnailMaxPixelSize: Int
    let headerThumbnailMaxPixelSize: Int
    let bottomInset: CGFloat

    init(containerWidth: CGFloat, isPadLayout: Bool) {
        let safeWidth = max(containerWidth, 320)
        usesSplitCards = safeWidth >= 900
        columns = isPadLayout ? 3 : 2
        horizontalInset = safeWidth >= 820 ? 24 : 16
        columnSpacing = safeWidth >= 820 ? 18 : 12
        rowSpacing = safeWidth >= 820 ? 18 : 14
        overviewCardHeight = safeWidth >= 900 ? 164 : 182

        let availableWidth = safeWidth - (horizontalInset * 2) - (CGFloat(columns - 1) * columnSpacing)
        let itemWidth = floor(max(availableWidth / CGFloat(columns), 118))
        let thumbnailHeight = floor(itemWidth * (3.0 / 2.0))
        pageCellHeight = thumbnailHeight

        let scale = UIScreen.main.scale
        thumbnailMaxPixelSize = max(300, Int(max(itemWidth, thumbnailHeight) * scale))
        headerThumbnailMaxPixelSize = max(320, Int(140 * scale))
        bottomInset = 28
    }
}

private enum ReaderThumbnailBrowserImageResolver {
    nonisolated static func previewImage(for document: ComicDocument?, pageIndex: Int) -> UIImage? {
        guard let document else {
            return nil
        }

        switch document {
        case .imageSequence(let imageSequence):
            return ReaderPagePreviewStore.shared.image(
                namespace: ReaderPageCache.namespace(for: imageSequence.url),
                pageIndex: pageIndex
            )
        case .pdf, .ebook, .unsupported:
            return nil
        }
    }

    static func image(for document: ComicDocument, pageIndex: Int, maxPixelSize: Int) async -> UIImage? {
        switch document {
        case .pdf(let pdfDocument):
            return await MainActor.run {
                PDFThumbnailStore.shared.image(
                    for: pdfDocument,
                    pageIndex: pageIndex,
                    maxPixelSize: maxPixelSize
                )
            }
        case .ebook(let ebookDocument):
            return await LocalEBookThumbnailExtractor.shared.thumbnail(
                from: ebookDocument.url,
                maxPixelSize: maxPixelSize
            )
        case .imageSequence(let imageSequence):
            guard let pageName = imageSequence.pageName(at: pageIndex) else {
                return nil
            }
            return await ReaderImageSequenceThumbnailPipeline.shared.image(
                documentURL: imageSequence.url,
                pageSource: imageSequence.pageSource,
                pageName: pageName,
                pageIndex: pageIndex,
                maxPixelSize: maxPixelSize
            )
        case .unsupported:
            return nil
        }
    }

    nonisolated static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}

private final class ReaderThumbnailBrowserSummaryCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderThumbnailBrowserSummaryCell"

    private let cardView = UIView()
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statsStackView = UIStackView()
    private let statusLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
    }

    func configure(currentPageNumber: Int, pageCount: Int, progressPercent: Int, remainingPageCount: Int) {
        titleLabel.text = pageCount > 0 ? "Page \(currentPageNumber)" : "No Pages"
        detailLabel.text = pageCount > 0
            ? "\(progressPercent)% completed across \(pageCount) pages"
            : "This document does not expose page thumbnails."
        progressView.progress = pageCount > 0 ? Float(Double(currentPageNumber) / Double(pageCount)) : 0
        statusLabel.text = "Now Reading"

        statsStackView.arrangedSubviews.forEach {
            statsStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let stats = [
            ("Progress", "\(progressPercent)%"),
            ("Left", "\(remainingPageCount)"),
            ("Total", "\(pageCount)")
        ]

        for (title, value) in stats {
            statsStackView.addArrangedSubview(ReaderThumbnailStatView(title: title, value: value))
        }
    }

    func setThumbnailImage(_ image: UIImage) {
        thumbnailView.image = image
    }

    func setLoadingState() {
        thumbnailView.image = nil
    }

    func setUnavailableState() {
        thumbnailView.image = UIImage(systemName: "photo")
        thumbnailView.tintColor = .secondaryLabel
        thumbnailView.contentMode = .center
    }

    private func configureView() {
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.96)
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.06
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let rootStack = UIStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .horizontal
        rootStack.alignment = .top
        rootStack.spacing = Spacing.md
        cardView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Spacing.md),
            rootStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Spacing.md),
            rootStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Spacing.md),
            rootStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Spacing.md)
        ])

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.backgroundColor = UIColor.tertiarySystemFill
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 18
        thumbnailView.layer.cornerCurve = .continuous
        rootStack.addArrangedSubview(thumbnailView)

        NSLayoutConstraint.activate([
            thumbnailView.widthAnchor.constraint(equalToConstant: 92),
            thumbnailView.heightAnchor.constraint(equalToConstant: 132)
        ])

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Spacing.xs
        rootStack.addArrangedSubview(textStack)

        statusLabel.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        statusLabel.textColor = .secondaryLabel
        textStack.addArrangedSubview(statusLabel)

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        textStack.addArrangedSubview(titleLabel)

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        textStack.addArrangedSubview(detailLabel)

        progressView.progressTintColor = tintColor
        progressView.trackTintColor = UIColor.systemFill
        textStack.addArrangedSubview(progressView)

        statsStackView.axis = .horizontal
        statsStackView.distribution = .fillEqually
        statsStackView.spacing = Spacing.xs
        textStack.addArrangedSubview(statsStackView)
    }
}

private final class ReaderThumbnailBrowserJumpCell: UICollectionViewCell, UITextFieldDelegate {
    static let reuseIdentifier = "ReaderThumbnailBrowserJumpCell"

    var onPageNumberChanged: ((String) -> Void)?
    var onSliderChanged: ((Int) -> Void)?
    var onGoTo: (() -> Void)?
    var onLocate: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let textField = UITextField()
    private let pageCountLabel = UILabel()
    private let goToButton = UIButton(type: .system)
    private let locateButton = UIButton(type: .system)
    private let slider = UISlider()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selectedPageNumber: Int, pageCount: Int) {
        titleLabel.text = "Quick Jump"
        detailLabel.text = pageCount > 0
            ? "Ready to jump to page \(selectedPageNumber) of \(pageCount)."
            : "No pages available in this document."
        pageCountLabel.text = "/ \(pageCount)"
        if !textField.isFirstResponder {
            textField.text = pageCount > 0 ? "\(selectedPageNumber)" : ""
        }
        slider.minimumValue = pageCount > 0 ? 1 : 0
        slider.maximumValue = Float(max(pageCount, 1))
        slider.value = pageCount > 0 ? Float(selectedPageNumber) : 0
        goToButton.isEnabled = pageCount > 0
        locateButton.isEnabled = pageCount > 0
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        onEditingChanged?(true)
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onEditingChanged?(false)
    }

    private func configureView() {
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.96)
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.06
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = Spacing.sm
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Spacing.md),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Spacing.md),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Spacing.md),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Spacing.md)
        ])

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        contentStack.addArrangedSubview(titleLabel)

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        contentStack.addArrangedSubview(detailLabel)

        let controls = UIStackView()
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = Spacing.xs
        contentStack.addArrangedSubview(controls)

        textField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        textField.keyboardType = .numberPad
        textField.borderStyle = .roundedRect
        textField.textAlignment = .center
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        NSLayoutConstraint.activate([
            textField.widthAnchor.constraint(equalToConstant: 74)
        ])
        controls.addArrangedSubview(textField)

        pageCountLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        pageCountLabel.textColor = .secondaryLabel
        controls.addArrangedSubview(pageCountLabel)

        var goToConfig = UIButton.Configuration.filled()
        goToConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        goToButton.configuration = goToConfig
        goToButton.setTitle("Go To", for: .normal)
        goToButton.addTarget(self, action: #selector(goToTapped), for: .touchUpInside)
        controls.addArrangedSubview(goToButton)

        var locateConfig = UIButton.Configuration.tinted()
        locateConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        locateButton.configuration = locateConfig
        locateButton.setTitle("Locate", for: .normal)
        locateButton.addTarget(self, action: #selector(locateTapped), for: .touchUpInside)
        controls.addArrangedSubview(locateButton)

        slider.minimumTrackTintColor = tintColor
        slider.maximumTrackTintColor = UIColor.systemFill
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        contentStack.addArrangedSubview(slider)
    }

    @objc private func textFieldChanged() {
        let digitsOnly = (textField.text ?? "").filter(\.isNumber)
        if digitsOnly != textField.text {
            textField.text = digitsOnly
        }
        onPageNumberChanged?(digitsOnly)
    }

    @objc private func sliderChanged() {
        onSliderChanged?(Int(slider.value.rounded()))
    }

    @objc private func goToTapped() {
        endEditing(true)
        onGoTo?()
    }

    @objc private func locateTapped() {
        endEditing(true)
        onLocate?()
    }
}

private final class ReaderThumbnailBrowserPageCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderThumbnailBrowserPageCell"

    private let cardView = UIView()
    private let thumbnailView = UIImageView()
    private let pageBadgeLabel = ReaderThumbnailInsetLabel()
    private let currentBadgeLabel = ReaderThumbnailInsetLabel()
    private let placeholderStack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        thumbnailView.contentMode = .scaleAspectFill
        spinner.stopAnimating()
        placeholderStack.isHidden = false
        currentBadgeLabel.isHidden = true
    }

    func configure(pageNumber: Int, isCurrentPage: Bool) {
        pageBadgeLabel.text = "\(pageNumber)"
        currentBadgeLabel.isHidden = !isCurrentPage
        cardView.backgroundColor = isCurrentPage
            ? tintColor.withAlphaComponent(0.14)
            : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.96)
        cardView.layer.borderColor = isCurrentPage
            ? tintColor.withAlphaComponent(0.78).cgColor
            : UIColor.black.withAlphaComponent(0.07).cgColor
    }

    func setLoadingState() {
        thumbnailView.image = nil
        thumbnailView.contentMode = .center
        spinner.startAnimating()
        placeholderStack.isHidden = false
    }

    func setImage(_ image: UIImage) {
        thumbnailView.image = image
        thumbnailView.contentMode = .scaleAspectFill
        spinner.stopAnimating()
        placeholderStack.isHidden = true
    }

    private func configureView() {
        contentView.backgroundColor = .clear
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 22
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.black.withAlphaComponent(0.07).cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.05
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.backgroundColor = UIColor.tertiarySystemFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 22
        thumbnailView.layer.cornerCurve = .continuous
        cardView.addSubview(thumbnailView)

        pageBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        pageBadgeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        pageBadgeLabel.textColor = .label
        pageBadgeLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        pageBadgeLabel.layer.cornerRadius = 12
        pageBadgeLabel.clipsToBounds = true
        pageBadgeLabel.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        cardView.addSubview(pageBadgeLabel)

        currentBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        currentBadgeLabel.text = "Now"
        currentBadgeLabel.textColor = tintColor
        currentBadgeLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        currentBadgeLabel.layer.cornerRadius = 12
        currentBadgeLabel.clipsToBounds = true
        currentBadgeLabel.insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        currentBadgeLabel.isHidden = true
        cardView.addSubview(currentBadgeLabel)

        placeholderStack.translatesAutoresizingMaskIntoConstraints = false
        placeholderStack.axis = .vertical
        placeholderStack.alignment = .center
        placeholderStack.spacing = 8
        cardView.addSubview(placeholderStack)

        placeholderStack.addArrangedSubview(spinner)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            pageBadgeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Spacing.sm),
            pageBadgeLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Spacing.sm),

            currentBadgeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Spacing.sm),
            currentBadgeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Spacing.sm),

            placeholderStack.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            placeholderStack.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor)
        ])
    }
}

private final class ReaderThumbnailBrowserSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ReaderThumbnailBrowserSectionHeaderView"

    private let titleLabel = UILabel()
    private let countLabel = ReaderThumbnailInsetLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Spacing.sm
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        stack.addArrangedSubview(titleLabel)

        let spacer = UIView()
        stack.addArrangedSubview(spacer)

        countLabel.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        countLabel.textColor = .secondaryLabel
        countLabel.insets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        countLabel.backgroundColor = UIColor.secondarySystemGroupedBackground
        countLabel.layer.cornerRadius = 12
        countLabel.clipsToBounds = true
        stack.addArrangedSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, count: Int) {
        titleLabel.text = title
        countLabel.text = "\(count)"
    }
}

private final class ReaderThumbnailStatView: UIView {
    init(title: String, value: String) {
        super.init(frame: .zero)

        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.withAlphaComponent(0.06).cgColor

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .caption2).withWeight(.semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.text = title
        stack.addArrangedSubview(titleLabel)

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.text = value
        stack.addArrangedSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ReaderThumbnailInsetLabel: UILabel {
    var insets = UIEdgeInsets.zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
