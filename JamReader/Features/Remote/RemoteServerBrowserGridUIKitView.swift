import SwiftUI
import UIKit

enum RemoteBrowserGridPresentationStyle: Equatable {
    case grid
    case listGrid
}

struct RemoteServerBrowserGridUIKitView: UIViewControllerRepresentable {
    let sections: [RemoteBrowserListSectionModel]
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    let layoutContext: RemoteServerBrowserLayoutContext
    let presentationStyle: RemoteBrowserGridPresentationStyle
    let onVisibleComicIDsChanged: (Set<String>) -> Void
    let onOpenItem: (RemoteDirectoryItem, CGRect) -> Void
    let onShowInfo: (RemoteDirectoryItem) -> Void
    let onOpenOffline: (RemoteDirectoryItem) -> Void
    let onSaveOffline: (RemoteDirectoryItem) -> Void
    let onRemoveOffline: (RemoteDirectoryItem) -> Void
    let onImport: (RemoteDirectoryItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sections: sections,
            profile: profile,
            browsingService: browsingService,
            layoutContext: layoutContext,
            presentationStyle: presentationStyle,
            onVisibleComicIDsChanged: onVisibleComicIDsChanged,
            onOpenItem: onOpenItem,
            onShowInfo: onShowInfo,
            onOpenOffline: onOpenOffline,
            onSaveOffline: onSaveOffline,
            onRemoveOffline: onRemoveOffline,
            onImport: onImport
        )
    }

    func makeUIViewController(context: Context) -> RemoteBrowserGridViewController {
        let controller = RemoteBrowserGridViewController()
        controller.coordinator = context.coordinator
        context.coordinator.attach(to: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: RemoteBrowserGridViewController, context: Context) {
        context.coordinator.update(
            sections: sections,
            profile: profile,
            browsingService: browsingService,
            layoutContext: layoutContext,
            presentationStyle: presentationStyle,
            onVisibleComicIDsChanged: onVisibleComicIDsChanged,
            onOpenItem: onOpenItem,
            onShowInfo: onShowInfo,
            onOpenOffline: onOpenOffline,
            onSaveOffline: onSaveOffline,
            onRemoveOffline: onRemoveOffline,
            onImport: onImport
        )
        uiViewController.reloadIfNeeded()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        private enum UpdatePlan {
            case none
            case fullReload
            case reconfigureVisibleItems([IndexPath])
        }

        private var sections: [RemoteBrowserListSectionModel]
        private var profile: RemoteServerProfile
        private var browsingService: RemoteServerBrowsingService
        private var layoutContext: RemoteServerBrowserLayoutContext
        private var presentationStyle: RemoteBrowserGridPresentationStyle
        private var onVisibleComicIDsChanged: (Set<String>) -> Void
        private var onOpenItem: (RemoteDirectoryItem, CGRect) -> Void
        private var onShowInfo: (RemoteDirectoryItem) -> Void
        private var onOpenOffline: (RemoteDirectoryItem) -> Void
        private var onSaveOffline: (RemoteDirectoryItem) -> Void
        private var onRemoveOffline: (RemoteDirectoryItem) -> Void
        private var onImport: (RemoteDirectoryItem) -> Void
        private weak var controller: RemoteBrowserGridViewController?
        private var pendingContextMenuAction: (() -> Void)?
        private var lastReportedVisibleComicIDs: Set<String> = []
        private var pendingVisibleComicIDReport: DispatchWorkItem?

        init(
            sections: [RemoteBrowserListSectionModel],
            profile: RemoteServerProfile,
            browsingService: RemoteServerBrowsingService,
            layoutContext: RemoteServerBrowserLayoutContext,
            presentationStyle: RemoteBrowserGridPresentationStyle,
            onVisibleComicIDsChanged: @escaping (Set<String>) -> Void,
            onOpenItem: @escaping (RemoteDirectoryItem, CGRect) -> Void,
            onShowInfo: @escaping (RemoteDirectoryItem) -> Void,
            onOpenOffline: @escaping (RemoteDirectoryItem) -> Void,
            onSaveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onRemoveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onImport: @escaping (RemoteDirectoryItem) -> Void
        ) {
            self.sections = sections
            self.profile = profile
            self.browsingService = browsingService
            self.layoutContext = layoutContext
            self.presentationStyle = presentationStyle
            self.onVisibleComicIDsChanged = onVisibleComicIDsChanged
            self.onOpenItem = onOpenItem
            self.onShowInfo = onShowInfo
            self.onOpenOffline = onOpenOffline
            self.onSaveOffline = onSaveOffline
            self.onRemoveOffline = onRemoveOffline
            self.onImport = onImport
        }

        func attach(to controller: RemoteBrowserGridViewController) {
            self.controller = controller
        }

        func update(
            sections: [RemoteBrowserListSectionModel],
            profile: RemoteServerProfile,
            browsingService: RemoteServerBrowsingService,
            layoutContext: RemoteServerBrowserLayoutContext,
            presentationStyle: RemoteBrowserGridPresentationStyle,
            onVisibleComicIDsChanged: @escaping (Set<String>) -> Void,
            onOpenItem: @escaping (RemoteDirectoryItem, CGRect) -> Void,
            onShowInfo: @escaping (RemoteDirectoryItem) -> Void,
            onOpenOffline: @escaping (RemoteDirectoryItem) -> Void,
            onSaveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onRemoveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onImport: @escaping (RemoteDirectoryItem) -> Void
        ) {
            let didChangeLayoutContext = self.layoutContext != layoutContext
            let didChangePresentationStyle = self.presentationStyle != presentationStyle
            let updatePlan = didChangePresentationStyle
                ? UpdatePlan.fullReload
                : Self.makeUpdatePlan(from: self.sections, to: sections)
            self.sections = sections
            self.profile = profile
            self.browsingService = browsingService
            self.layoutContext = layoutContext
            self.presentationStyle = presentationStyle
            self.onVisibleComicIDsChanged = onVisibleComicIDsChanged
            self.onOpenItem = onOpenItem
            self.onShowInfo = onShowInfo
            self.onOpenOffline = onOpenOffline
            self.onSaveOffline = onSaveOffline
            self.onRemoveOffline = onRemoveOffline
            self.onImport = onImport

            switch updatePlan {
            case .none:
                if didChangeLayoutContext || didChangePresentationStyle {
                    controller?.refreshLayout()
                }
            case .fullReload:
                controller?.markNeedsReload()
            case .reconfigureVisibleItems(let indexPaths):
                controller?.reconfigureVisibleItems(at: indexPaths)
            }

            reportVisibleComicIDsIfNeeded()
        }

        deinit {
            pendingVisibleComicIDReport?.cancel()
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            sections.count
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            sections[section].items.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let row = sections[indexPath.section].items[indexPath.item]
            switch presentationStyle {
            case .grid:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: RemoteBrowserGridCell.reuseIdentifier,
                    for: indexPath
                ) as? RemoteBrowserGridCell else {
                    return UICollectionViewCell()
                }

                cell.configure(
                    row: row,
                    profile: profile,
                    browsingService: browsingService,
                    itemWidth: itemWidth(for: collectionView)
                )
                return cell
            case .listGrid:
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: RemoteBrowserListGridCell.reuseIdentifier,
                    for: indexPath
                ) as? RemoteBrowserListGridCell else {
                    return UICollectionViewCell()
                }

                cell.configure(
                    row: row,
                    profile: profile,
                    browsingService: browsingService
                )
                return cell
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            let item = sections[indexPath.section].items[indexPath.item].item
            let sourceFrame: CGRect
            switch presentationStyle {
            case .grid:
                sourceFrame = (collectionView.cellForItem(at: indexPath) as? RemoteBrowserGridCell)?.heroSourceFrame() ?? .zero
            case .listGrid:
                sourceFrame = (collectionView.cellForItem(at: indexPath) as? RemoteBrowserListGridCell)?.heroSourceFrame() ?? .zero
            }
            onOpenItem(item, sourceFrame)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            let row = sections[indexPath.section].items[indexPath.item]
            let actions = menuElements(for: row)
            guard !actions.isEmpty else {
                return nil
            }

            return UIContextMenuConfiguration(identifier: row.item.id as NSString, previewProvider: nil) { _ in
                UIMenu(children: actions)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionAnimating?
        ) {
            guard let action = pendingContextMenuAction else {
                return
            }

            pendingContextMenuAction = nil

            if let animator {
                animator.addCompletion {
                    action()
                }
            } else {
                DispatchQueue.main.async {
                    action()
                }
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: RemoteBrowserGridSectionHeaderView.reuseIdentifier,
                    for: indexPath
                ) as? RemoteBrowserGridSectionHeaderView ?? RemoteBrowserGridSectionHeaderView()
                header.configure(with: sections[indexPath.section])
                return header
            default:
                let footer = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: RemoteBrowserGridSectionFooterView.reuseIdentifier,
                    for: indexPath
                ) as? RemoteBrowserGridSectionFooterView ?? RemoteBrowserGridSectionFooterView()
                footer.configure(text: sections[indexPath.section].footerText)
                return footer
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let width = itemWidth(for: collectionView)
            switch presentationStyle {
            case .grid:
                let imageHeight = width / AppLayout.coverAspectRatio
                let labelHeight: CGFloat = 72
                return CGSize(width: width, height: imageHeight + labelHeight)
            case .listGrid:
                return CGSize(width: width, height: RemoteBrowserListItemCardView.Metrics.preferredHeight)
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            guard sections[section].kind != .notice else {
                return .zero
            }
            return CGSize(width: collectionView.bounds.width, height: headerHeight(for: section))
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForFooterInSection section: Int
        ) -> CGSize {
            guard let footerText = sections[section].footerText, !footerText.isEmpty else {
                return .zero
            }
            return CGSize(width: collectionView.bounds.width, height: 24)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            insetForSectionAt section: Int
        ) -> UIEdgeInsets {
            sectionInsets(for: section)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumLineSpacingForSectionAt section: Int
        ) -> CGFloat {
            lineSpacing(for: section)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumInteritemSpacingForSectionAt section: Int
        ) -> CGFloat {
            interitemSpacing(for: section)
        }

        fileprivate func layoutSection(
            at sectionIndex: Int,
            environment: NSCollectionLayoutEnvironment
        ) -> NSCollectionLayoutSection {
            let sectionModel = sectionIndex < sections.count ? sections[sectionIndex] : nil
            let usesNoticeLayout = sectionModel?.kind == .notice
            let effectiveWidth = environment.container.effectiveContentSize.width
            let contentInsets = usesNoticeLayout == true
                ? noticeInsets
                : standardSectionInsets
            let interItemSpacing = interitemSpacing(for: sectionIndex)
            let columns = usesNoticeLayout
                ? 1
                : max(itemMetrics(for: effectiveWidth).columns, 1)

            let horizontalInset = contentInsets.left + contentInsets.right
            let availableWidth = max(effectiveWidth - horizontalInset, 1)
            let totalSpacing = CGFloat(max(columns - 1, 0)) * interItemSpacing
            let itemWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
            let itemHeight: CGFloat
            switch presentationStyle {
            case .grid:
                itemHeight = itemWidth / AppLayout.coverAspectRatio + 72
            case .listGrid:
                itemHeight = RemoteBrowserListItemCardView.Metrics.preferredHeight
            }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .fractionalHeight(1.0)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(itemHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: item,
                count: columns
            )
            group.interItemSpacing = NSCollectionLayoutSpacing.fixed(interItemSpacing)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: contentInsets.top,
                leading: contentInsets.left,
                bottom: contentInsets.bottom,
                trailing: contentInsets.right
            )
            section.interGroupSpacing = lineSpacing(for: sectionIndex)

            var boundaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []

            if let sectionModel, sectionModel.kind != RemoteBrowserListSectionModel.Kind.notice {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .absolute(headerHeight(for: sectionIndex))
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                boundaryItems.append(header)
            }

            if let footerText = sectionModel?.footerText, !footerText.isEmpty {
                let footer = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1.0),
                        heightDimension: .absolute(24)
                    ),
                    elementKind: UICollectionView.elementKindSectionFooter,
                    alignment: .bottom
                )
                boundaryItems.append(footer)
            }

            section.boundarySupplementaryItems = boundaryItems
            return section
        }

        private func itemWidth(for collectionView: UICollectionView) -> CGFloat {
            itemMetrics(for: collectionView.bounds.width).itemWidth
        }

        private var standardSectionInsets: UIEdgeInsets {
            switch presentationStyle {
            case .grid:
                return layoutContext.gridSectionInsets
            case .listGrid:
                return layoutContext.listGridSectionInsets
            }
        }

        private var noticeInsets: UIEdgeInsets {
            switch presentationStyle {
            case .grid:
                return layoutContext.gridNoticeInsets
            case .listGrid:
                return layoutContext.listGridNoticeInsets
            }
        }

        private func interitemSpacing(for section: Int) -> CGFloat {
            if section < sections.count, sections[section].kind == .notice {
                return 0
            }

            switch presentationStyle {
            case .grid:
                return layoutContext.gridInteritemSpacing
            case .listGrid:
                return layoutContext.listColumnSpacing
            }
        }

        private func lineSpacing(for section: Int) -> CGFloat {
            if section < sections.count, sections[section].kind == .notice {
                return 0
            }

            switch presentationStyle {
            case .grid:
                return layoutContext.gridLineSpacing
            case .listGrid:
                return layoutContext.listGridLineSpacing
            }
        }

        private func sectionInsets(for section: Int) -> UIEdgeInsets {
            if section < sections.count, sections[section].kind == .notice {
                return noticeInsets
            }

            return standardSectionInsets
        }

        private func itemMetrics(for collectionWidth: CGFloat) -> (columns: Int, itemWidth: CGFloat) {
            switch presentationStyle {
            case .grid:
                return layoutContext.gridItemMetrics(for: collectionWidth)
            case .listGrid:
                return layoutContext.listGridItemMetrics(for: collectionWidth)
            }
        }

        private func headerHeight(for sectionIndex: Int) -> CGFloat {
            guard sectionIndex < sections.count else {
                return 34
            }

            let section = sections[sectionIndex]
            guard section.kind != .notice else {
                return 0
            }

            return (section.metadataText?.isEmpty == false) ? 52 : 34
        }

        private func menuElements(for row: RemoteBrowserListRowModel) -> [UIMenuElement] {
            var actions: [UIMenuElement] = []

            if row.item.canOpenAsComic {
                actions.append(
                    UIAction(
                        title: "Info",
                        image: UIImage(systemName: "info.circle")
                    ) { [weak self] _ in
                        self?.pendingContextMenuAction = { [weak self] in
                            self?.onShowInfo(row.item)
                        }
                    }
                )

                actions.append(
                    UIAction(
                        title: "Import",
                        image: UIImage(systemName: "square.and.arrow.down")
                    ) { [weak self] _ in
                        self?.pendingContextMenuAction = { [weak self] in
                            self?.onImport(row.item)
                        }
                    }
                )

                if row.cacheAvailability.hasLocalCopy {
                    actions.append(
                        UIAction(
                            title: "Open Offline",
                            image: UIImage(systemName: "arrow.down.circle")
                        ) { [weak self] _ in
                            self?.pendingContextMenuAction = { [weak self] in
                                self?.onOpenOffline(row.item)
                            }
                        }
                    )
                }

                actions.append(
                    UIAction(
                        title: row.cacheAvailability.kind == .unavailable ? "Save Offline" : "Refresh Offline Copy",
                        image: UIImage(
                            systemName: row.cacheAvailability.kind == .unavailable
                                ? "icloud.and.arrow.down"
                                : "arrow.clockwise.icloud"
                        )
                    ) { [weak self] _ in
                        self?.pendingContextMenuAction = { [weak self] in
                            self?.onSaveOffline(row.item)
                        }
                    }
                )

                if row.cacheAvailability.hasLocalCopy {
                    actions.append(
                        UIAction(
                            title: "Remove Download",
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive
                        ) { [weak self] _ in
                            self?.pendingContextMenuAction = { [weak self] in
                                self?.onRemoveOffline(row.item)
                            }
                        }
                    )
                }
            } else if row.item.isDirectory {
                actions.append(
                    UIAction(
                        title: "Import",
                        image: UIImage(systemName: "square.and.arrow.down")
                    ) { [weak self] _ in
                        self?.pendingContextMenuAction = { [weak self] in
                            self?.onImport(row.item)
                        }
                    }
                )
            }

            return actions
        }

        fileprivate func configureVisibleCell(_ cell: RemoteBrowserGridCell, at indexPath: IndexPath, collectionView: UICollectionView) {
            guard indexPath.section < sections.count,
                  indexPath.item < sections[indexPath.section].items.count else {
                return
            }

            cell.configure(
                row: sections[indexPath.section].items[indexPath.item],
                profile: profile,
                browsingService: browsingService,
                itemWidth: itemWidth(for: collectionView)
            )
        }

        fileprivate func configureVisibleCell(
            _ cell: RemoteBrowserListGridCell,
            at indexPath: IndexPath
        ) {
            guard indexPath.section < sections.count,
                  indexPath.item < sections[indexPath.section].items.count else {
                return
            }

            cell.configure(
                row: sections[indexPath.section].items[indexPath.item],
                profile: profile,
                browsingService: browsingService
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scheduleVisibleComicIDsReport()
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            scheduleVisibleComicIDsReport()
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            scheduleVisibleComicIDsReport()
        }

        fileprivate func scheduleVisibleComicIDsReport() {
            pendingVisibleComicIDReport?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.reportVisibleComicIDsIfNeeded()
            }
            pendingVisibleComicIDReport = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        fileprivate func reportVisibleComicIDsIfNeeded() {
            guard let collectionView = controller?.collectionView else {
                return
            }

            pendingVisibleComicIDReport = nil

            let visibleIDs = Set(
                collectionView.indexPathsForVisibleItems.compactMap { indexPath -> String? in
                    guard indexPath.section < sections.count,
                          indexPath.item < sections[indexPath.section].items.count else {
                        return nil
                    }

                    let row = sections[indexPath.section].items[indexPath.item]
                    return row.item.canOpenAsComic ? row.item.id : nil
                }
            )

            guard visibleIDs != lastReportedVisibleComicIDs else {
                return
            }

            lastReportedVisibleComicIDs = visibleIDs
            onVisibleComicIDsChanged(visibleIDs)
        }

        private static func makeUpdatePlan(
            from oldSections: [RemoteBrowserListSectionModel],
            to newSections: [RemoteBrowserListSectionModel]
        ) -> UpdatePlan {
            guard oldSections.count == newSections.count else {
                return .fullReload
            }

            var changedIndexPaths: [IndexPath] = []

            for (sectionIndex, pair) in zip(oldSections.indices, zip(oldSections, newSections)) {
                let oldSection = pair.0
                let newSection = pair.1

                guard oldSection.kind == newSection.kind,
                      oldSection.title == newSection.title,
                      oldSection.metadataText == newSection.metadataText,
                      oldSection.footerText == newSection.footerText,
                      oldSection.items.count == newSection.items.count else {
                    return .fullReload
                }

                for itemIndex in oldSection.items.indices {
                    guard oldSection.items[itemIndex].id == newSection.items[itemIndex].id else {
                        return .fullReload
                    }

                    if oldSection.items[itemIndex] != newSection.items[itemIndex] {
                        changedIndexPaths.append(IndexPath(item: itemIndex, section: sectionIndex))
                    }
                }
            }

            if changedIndexPaths.isEmpty {
                return .none
            }

            return .reconfigureVisibleItems(changedIndexPaths)
        }
    }
}

final class RemoteBrowserGridViewController: UIViewController {
    weak var coordinator: RemoteServerBrowserGridUIKitView.Coordinator?
    private let navigationBridge = RemoteServerBrowserNativeNavigationBridge()
    private var lastMeasuredContentWidth: Int = 0

    private(set) lazy var collectionView: UICollectionView = {
        let layout = makeCollectionLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        collectionView.register(RemoteBrowserGridCell.self, forCellWithReuseIdentifier: RemoteBrowserGridCell.reuseIdentifier)
        collectionView.register(RemoteBrowserListGridCell.self, forCellWithReuseIdentifier: RemoteBrowserListGridCell.reuseIdentifier)
        collectionView.register(
            RemoteBrowserGridSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: RemoteBrowserGridSectionHeaderView.reuseIdentifier
        )
        collectionView.register(
            RemoteBrowserGridSectionFooterView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: RemoteBrowserGridSectionFooterView.reuseIdentifier
        )
        return collectionView
    }()

    private var needsReload = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationBridge.attach(scrollView: collectionView, from: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationBridge.attach(scrollView: collectionView, from: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationBridge.detach()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        handleWidthChangeIfNeeded()
        coordinator?.reportVisibleComicIDsIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.refreshLayout()
        })
    }

    func markNeedsReload() {
        needsReload = true
    }

    func refreshLayout() {
        collectionView.collectionViewLayout.invalidateLayout()
        updateVisibleCellLayout()
        collectionView.layoutIfNeeded()
    }

    func reconfigureVisibleItems(at indexPaths: [IndexPath]) {
        guard let coordinator else {
            return
        }

        let visibleSet = Set(collectionView.indexPathsForVisibleItems)
        let targetIndexPaths = indexPaths.filter { visibleSet.contains($0) }
        guard !targetIndexPaths.isEmpty else {
            return
        }

        UIView.performWithoutAnimation {
            for indexPath in targetIndexPaths {
                if let cell = collectionView.cellForItem(at: indexPath) as? RemoteBrowserGridCell {
                    coordinator.configureVisibleCell(cell, at: indexPath, collectionView: collectionView)
                } else if let cell = collectionView.cellForItem(at: indexPath) as? RemoteBrowserListGridCell {
                    coordinator.configureVisibleCell(cell, at: indexPath)
                }
            }
        }
    }

    func reloadIfNeeded() {
        guard needsReload else {
            return
        }
        needsReload = false
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        coordinator?.reportVisibleComicIDsIfNeeded()
    }

    private func handleWidthChangeIfNeeded() {
        let measuredWidth = Int(collectionView.bounds.width.rounded(.toNearestOrAwayFromZero))
        guard measuredWidth > 0, measuredWidth != lastMeasuredContentWidth else {
            return
        }

        lastMeasuredContentWidth = measuredWidth
        refreshLayout()
    }

    private func makeCollectionLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            self?.coordinator?.layoutSection(at: sectionIndex, environment: environment)
        }
    }

    private func updateVisibleCellLayout() {
        for case let cell as RemoteBrowserGridCell in collectionView.visibleCells {
            cell.setNeedsLayout()
        }

        for case let cell as RemoteBrowserListGridCell in collectionView.visibleCells {
            cell.setNeedsLayout()
        }
    }
}

private final class RemoteBrowserListGridCell: UICollectionViewCell {
    static let reuseIdentifier = "RemoteBrowserListGridCell"

    private let cardView = RemoteBrowserListItemCardView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.prepareForReuseCard()
    }

    func configure(
        row: RemoteBrowserListRowModel,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService
    ) {
        cardView.configure(
            row: row,
            profile: profile,
            browsingService: browsingService,
            usesEmbeddedTapHandler: false
        ) { _ in }
    }

    func heroSourceFrame() -> CGRect {
        cardView.heroSourceFrame()
    }

    private func buildUI() {
        contentView.backgroundColor = .clear
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

private final class RemoteBrowserGridCell: UICollectionViewCell {
    static let reuseIdentifier = "RemoteBrowserGridCell"
    private enum Metrics {
        static let cornerRadius: CGFloat = 22
        static let cardBorderWidth: CGFloat = 0.75
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 10
        static let textSpacing: CGFloat = 4
    }

    private let cardView = UIView()
    private let thumbnailImageView = UIImageView()
    private let thumbnailPlaceholderView = UIView()
    private let thumbnailPlaceholderImageView = UIImageView()
    private let symbolView = UIView()
    private let symbolImageView = UIImageView()
    private let titleIconContainer = UIView()
    private let titleIconView = UIImageView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let cacheBadgeView = UIImageView()
    private let progressTrackView = UIView()
    private let progressFillView = UIView()
    private var imageHeightConstraint: NSLayoutConstraint?
    private var progressWidthConstraint: NSLayoutConstraint?
    private var progressFraction: CGFloat = 0
    private var thumbnailTask: Task<Void, Never>?
    private var representedItemID: String?
    private var registeredHeroSourceID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        unregisterHeroSourceIfNeeded()
        representedItemID = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        thumbnailPlaceholderView.isHidden = true
        symbolView.isHidden = true
        cacheBadgeView.isHidden = true
        progressTrackView.isHidden = true
        progressWidthConstraint?.constant = 0
        progressFraction = 0
    }

    func configure(
        row: RemoteBrowserListRowModel,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        itemWidth: CGFloat
    ) {
        representedItemID = row.item.id
        configureTitleText(for: row.item)
        metadataLabel.text = metadataText(for: row)
        updateHeroSourceRegistration(for: row.item)
        imageHeightConstraint?.constant = itemWidth / AppLayout.coverAspectRatio

        if row.item.isDirectory, !row.item.previewItems.isEmpty {
            configureDirectoryPreview(
                item: row.item,
                profile: profile,
                browsingService: browsingService,
                itemWidth: itemWidth
            )
            cacheBadgeView.isHidden = true
            progressTrackView.isHidden = true
        } else if row.item.canOpenAsComic, !row.item.isPDFDocument {
            configureComicThumbnail(
                item: row.item,
                profile: profile,
                browsingService: browsingService,
                prefersLocalCache: row.cacheAvailability.hasLocalCopy,
                itemWidth: itemWidth
            )
            symbolView.isHidden = true
            updateCacheBadge(for: row.cacheAvailability)
            updateProgressBar(for: row.readingSession)
        } else if row.item.canOpenAsComic {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            thumbnailPlaceholderView.isHidden = true
            symbolView.isHidden = false
            configureSymbolView(for: row.item)
            updateCacheBadge(for: row.cacheAvailability)
            updateProgressBar(for: row.readingSession)
        } else {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            thumbnailPlaceholderView.isHidden = true
            symbolView.isHidden = false
            cacheBadgeView.isHidden = true
            progressTrackView.isHidden = true
            configureSymbolView(for: row.item)
        }
    }

    private func configureDirectoryPreview(
        item: RemoteDirectoryItem,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        itemWidth: CGFloat
    ) {
        thumbnailImageView.isHidden = false
        thumbnailPlaceholderView.isHidden = false
        thumbnailPlaceholderImageView.image = UIImage(systemName: "folder.fill")
        symbolView.isHidden = true
        thumbnailTask?.cancel()

        let targetSize = CGSize(
            width: itemWidth,
            height: itemWidth / AppLayout.coverAspectRatio
        )
        let itemID = item.id
        let seeded = RemoteDirectoryPreviewSupport.seededCompositeImage(
            for: item,
            browsingService: browsingService,
            targetSize: targetSize,
            scale: UIScreen.main.scale
        )
        if representedItemID == itemID {
            thumbnailImageView.image = seeded
            thumbnailPlaceholderView.isHidden = seeded != nil
        }

        thumbnailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await RemoteDirectoryPreviewSupport.loadCompositeImage(
                for: item,
                profile: profile,
                browsingService: browsingService,
                targetSize: targetSize,
                scale: UIScreen.main.scale
            )
            guard !Task.isCancelled, self.representedItemID == itemID else {
                return
            }
            self.thumbnailImageView.image = image
            self.thumbnailPlaceholderView.isHidden = image != nil
        }
    }

    private func buildUI() {
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(Color.surfaceSecondary)
        cardView.layer.cornerRadius = Metrics.cornerRadius
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = Metrics.cardBorderWidth
        cardView.layer.borderColor = UIColor.label.withAlphaComponent(0.05).cgColor
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        thumbnailPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPlaceholderView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        cardView.addSubview(thumbnailPlaceholderView)

        thumbnailPlaceholderImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPlaceholderImageView.contentMode = .scaleAspectFit
        thumbnailPlaceholderImageView.tintColor = UIColor.systemBlue.withAlphaComponent(0.85)
        thumbnailPlaceholderImageView.image = UIImage(systemName: "book.closed.fill")
        thumbnailPlaceholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 34,
            weight: .semibold
        )
        thumbnailPlaceholderView.addSubview(thumbnailPlaceholderImageView)

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .clear
        thumbnailImageView.isHidden = true
        cardView.addSubview(thumbnailImageView)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.isHidden = true
        cardView.addSubview(symbolView)

        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        symbolImageView.contentMode = .scaleAspectFit
        symbolView.addSubview(symbolImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).bold()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        titleIconContainer.translatesAutoresizingMaskIntoConstraints = false
        titleIconContainer.isHidden = true

        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.contentMode = .scaleAspectFit
        titleIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        titleIconContainer.addSubview(titleIconView)

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.numberOfLines = 1
        metadataLabel.lineBreakMode = .byTruncatingTail

        cacheBadgeView.translatesAutoresizingMaskIntoConstraints = false
        cacheBadgeView.isHidden = true
        cardView.addSubview(cacheBadgeView)

        progressTrackView.translatesAutoresizingMaskIntoConstraints = false
        progressTrackView.backgroundColor = UIColor.clear
        progressTrackView.isHidden = true
        cardView.addSubview(progressTrackView)

        progressFillView.translatesAutoresizingMaskIntoConstraints = false
        progressFillView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        progressTrackView.addSubview(progressFillView)

        let titleRow = UIStackView(arrangedSubviews: [titleIconContainer, titleLabel])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [titleRow, metadataLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = Metrics.textSpacing
        cardView.addSubview(textStack)

        imageHeightConstraint = thumbnailImageView.heightAnchor.constraint(equalToConstant: 180)
        progressWidthConstraint = progressFillView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnailPlaceholderView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbnailPlaceholderView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbnailPlaceholderView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            thumbnailPlaceholderImageView.centerXAnchor.constraint(equalTo: thumbnailPlaceholderView.centerXAnchor),
            thumbnailPlaceholderImageView.centerYAnchor.constraint(equalTo: thumbnailPlaceholderView.centerYAnchor),

            thumbnailImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageHeightConstraint!,

            thumbnailPlaceholderView.heightAnchor.constraint(equalTo: thumbnailImageView.heightAnchor),

            symbolView.topAnchor.constraint(equalTo: cardView.topAnchor),
            symbolView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            symbolView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            symbolView.heightAnchor.constraint(equalTo: thumbnailImageView.heightAnchor),

            symbolImageView.centerXAnchor.constraint(equalTo: symbolView.centerXAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: symbolView.centerYAnchor),

            cacheBadgeView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            cacheBadgeView.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: -10),
            cacheBadgeView.widthAnchor.constraint(equalToConstant: 22),
            cacheBadgeView.heightAnchor.constraint(equalToConstant: 22),

            progressTrackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            progressTrackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            progressTrackView.bottomAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor),
            progressTrackView.heightAnchor.constraint(equalToConstant: 3),

            progressFillView.leadingAnchor.constraint(equalTo: progressTrackView.leadingAnchor),
            progressFillView.topAnchor.constraint(equalTo: progressTrackView.topAnchor),
            progressFillView.bottomAnchor.constraint(equalTo: progressTrackView.bottomAnchor),
            progressWidthConstraint!,

            titleIconContainer.widthAnchor.constraint(equalToConstant: 15),
            titleIconContainer.heightAnchor.constraint(equalToConstant: ceil(titleLabel.font.lineHeight)),
            titleIconView.widthAnchor.constraint(equalToConstant: 15),
            titleIconView.heightAnchor.constraint(equalToConstant: 15),
            titleIconView.centerXAnchor.constraint(equalTo: titleIconContainer.centerXAnchor),
            titleIconView.centerYAnchor.constraint(equalTo: titleIconContainer.centerYAnchor, constant: 1.5),

            textStack.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: Metrics.verticalPadding),
            textStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.horizontalPadding),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.horizontalPadding),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -Metrics.verticalPadding)
        ])
    }

    private func configureComicThumbnail(
        item: RemoteDirectoryItem,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool,
        itemWidth: CGFloat
    ) {
        thumbnailImageView.isHidden = false
        thumbnailPlaceholderView.isHidden = false
        symbolView.isHidden = true
        thumbnailTask?.cancel()

        let pixelSize = Int(max(itemWidth, itemWidth / AppLayout.coverAspectRatio) * UIScreen.main.scale)
        let itemID = item.id

        let seeded = RemoteComicThumbnailPipeline.shared.cachedImage(
            for: item,
            browsingService: browsingService,
            maxPixelSize: pixelSize
        )
        if representedItemID == itemID {
            thumbnailImageView.image = seeded
            thumbnailPlaceholderView.isHidden = seeded != nil
        }

        thumbnailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await RemoteComicThumbnailPipeline.shared.image(
                for: profile,
                item: item,
                browsingService: browsingService,
                prefersLocalCache: prefersLocalCache,
                maxPixelSize: pixelSize,
                allowsRemoteFetch: true
            )
            guard !Task.isCancelled, self.representedItemID == itemID else {
                return
            }
            self.thumbnailImageView.image = image
            self.thumbnailPlaceholderView.isHidden = image != nil
        }
    }

    private func configureSymbolView(for item: RemoteDirectoryItem) {
        thumbnailPlaceholderImageView.image = UIImage(systemName: "book.closed.fill")
        let isDirectory = item.isDirectory
        let isPDF = item.isPDFDocument
        let tintColor: UIColor = isDirectory ? .systemBlue : (isPDF ? .systemRed : .systemBlue)
        let systemName: String
        if isDirectory {
            systemName = "folder.fill"
        } else if isPDF {
            systemName = "doc.text.fill"
        } else {
            systemName = "doc.fill"
        }

        symbolView.backgroundColor = tintColor.withAlphaComponent(0.16)
        symbolImageView.image = UIImage(systemName: systemName)
        symbolImageView.tintColor = tintColor
        symbolImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 34,
            weight: .semibold
        )
    }

    private func configureTitleText(for item: RemoteDirectoryItem) {
        let font = titleLabel.font ?? UIFont.preferredFont(forTextStyle: .subheadline).bold()
        let tintColor: UIColor
        if item.isDirectory {
            tintColor = .systemBlue
        } else if item.canOpenAsComic {
            tintColor = .systemGreen
        } else {
            tintColor = .secondaryLabel
        }

        let attributed = NSMutableAttributedString()
        if let symbolImage = UIImage(
            systemName: item.titleSystemImageName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: font.pointSize - 1,
                weight: .semibold
            )
        )?.withTintColor(tintColor, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = symbolImage
            let symbolSide = font.pointSize - 1
            attachment.bounds = CGRect(
                x: 0,
                y: (font.capHeight - symbolSide) / 2 - 1.5,
                width: symbolSide,
                height: symbolSide
            )
            attributed.append(NSAttributedString(attachment: attachment))
            attributed.append(NSAttributedString(string: " "))
        }

        attributed.append(
            NSAttributedString(
                string: item.name,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.label
                ]
            )
        )
        titleLabel.attributedText = attributed
    }

    func heroSourceFrame() -> CGRect {
        thumbnailPlaceholderView.convert(thumbnailPlaceholderView.bounds, to: nil)
    }

    private func updateHeroSourceRegistration(for item: RemoteDirectoryItem) {
        if registeredHeroSourceID != item.id {
            unregisterHeroSourceIfNeeded()
        }

        guard item.canOpenAsComic else {
            return
        }

        HeroSourceRegistry.shared.register(view: thumbnailPlaceholderView, for: item.id)
        registeredHeroSourceID = item.id
    }

    private func unregisterHeroSourceIfNeeded() {
        guard let registeredHeroSourceID else {
            return
        }

        HeroSourceRegistry.shared.unregister(view: thumbnailPlaceholderView, for: registeredHeroSourceID)
        self.registeredHeroSourceID = nil
    }

    private func updateCacheBadge(for availability: RemoteComicCachedAvailability) {
        switch availability.kind {
        case .current:
            cacheBadgeView.image = UIImage(systemName: "arrow.down.circle.fill")
            cacheBadgeView.tintColor = .systemBlue
            cacheBadgeView.isHidden = false
        case .stale:
            cacheBadgeView.image = UIImage(systemName: "arrow.down.circle.fill")
            cacheBadgeView.tintColor = .systemOrange
            cacheBadgeView.isHidden = false
        case .unavailable:
            cacheBadgeView.isHidden = true
        }
    }

    private func updateProgressBar(for session: RemoteComicReadingSession?) {
        guard let session,
              session.hasBeenOpened,
              !session.read,
              let fraction = session.readingProgressFraction
        else {
            progressTrackView.isHidden = true
            progressWidthConstraint?.constant = 0
            progressFraction = 0
            return
        }

        progressTrackView.isHidden = false
        progressFraction = CGFloat(fraction)
        progressWidthConstraint?.constant = bounds.width * progressFraction
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageHeightConstraint?.constant = max(contentView.bounds.width, 1) / AppLayout.coverAspectRatio
        if !progressTrackView.isHidden, let constraint = progressWidthConstraint {
            constraint.constant = bounds.width * progressFraction
        }
    }

    private func metadataText(for row: RemoteBrowserListRowModel) -> String {
        if row.item.isDirectory {
            return row.item.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Browse folder"
        }
        if let readingSession = row.readingSession {
            return readingSession.progressText
        }
        var parts: [String] = []
        if let badgeTitle = row.cacheAvailability.badgeTitle {
            parts.append(badgeTitle)
        }
        if row.item.isComicDirectory {
            if let pageCountHint = row.item.pageCountHint {
                parts.append("\(pageCountHint) pages")
            } else {
                parts.append("Image folder comic")
            }
        } else if let fileSize = row.item.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        if let modifiedAt = row.item.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

}

private final class RemoteBrowserGridSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "RemoteBrowserGridSectionHeaderView"

    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .preferredFont(forTextStyle: .caption1)
        metadataLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 2
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with section: RemoteBrowserListSectionModel) {
        titleLabel.text = section.title
        metadataLabel.text = section.metadataText
        metadataLabel.isHidden = section.metadataText?.isEmpty ?? true
    }
}

private final class RemoteBrowserGridSectionFooterView: UICollectionReusableView {
    static let reuseIdentifier = "RemoteBrowserGridSectionFooterView"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String?) {
        label.text = text
        label.isHidden = text?.isEmpty ?? true
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
