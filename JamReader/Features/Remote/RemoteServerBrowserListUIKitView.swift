import SwiftUI
import UIKit

struct RemoteBrowserListSectionModel: Equatable, Identifiable {
    enum Kind: String {
        case directories
        case comics
        case notice
    }

    let kind: Kind
    let title: String
    let metadataText: String?
    let footerText: String?
    let items: [RemoteBrowserListRowModel]

    var id: String { kind.rawValue }
}

struct RemoteBrowserListRowModel: Equatable, Identifiable {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability

    var id: String { item.id }
}

struct RemoteServerBrowserLayoutContext: Equatable {
    private enum GridDensity {
        case compact
        case medium
        case wide
    }

    let containerWidth: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var normalizedWidth: CGFloat {
        max(containerWidth.rounded(.toNearestOrAwayFromZero), 0)
    }

    private var gridDensity: GridDensity {
        if horizontalSizeClass == .regular {
            if normalizedWidth >= 960 {
                return .wide
            }

            if normalizedWidth >= 360 {
                return .medium
            }

            return .compact
        }

        if normalizedWidth >= 760 {
            return .wide
        }

        if normalizedWidth >= 460 {
            return .medium
        }

        return .compact
    }

    var usesWideGridMetrics: Bool {
        gridItemMetrics().columns >= 4
    }

    var usesMediumGridMetrics: Bool {
        gridItemMetrics().columns >= 2
    }

    var gridSectionInsets: UIEdgeInsets {
        let horizontalInset: CGFloat
        switch gridDensity {
        case .wide:
            horizontalInset = 18
        case .medium:
            horizontalInset = 14
        case .compact:
            horizontalInset = 10
        }
        return UIEdgeInsets(top: 4, left: horizontalInset, bottom: 20, right: horizontalInset)
    }

    var gridNoticeInsets: UIEdgeInsets {
        let horizontalInset = gridSectionInsets.left
        return UIEdgeInsets(top: 0, left: horizontalInset, bottom: 20, right: horizontalInset)
    }

    var gridLineSpacing: CGFloat {
        switch gridDensity {
        case .wide:
            return 16
        case .medium:
            return 14
        case .compact:
            return 12
        }
    }

    var gridInteritemSpacing: CGFloat {
        switch gridDensity {
        case .wide:
            return 16
        case .medium:
            return 12
        case .compact:
            return 10
        }
    }

    private var gridTargetItemWidth: CGFloat {
        switch gridDensity {
        case .wide:
            return 196
        case .medium:
            return 178
        case .compact:
            return 160
        }
    }

    private var minimumGridItemWidth: CGFloat {
        switch gridDensity {
        case .wide:
            return 170
        case .medium:
            return 156
        case .compact:
            return 140
        }
    }

    private func minimumGridColumns(for width: CGFloat) -> Int {
        if horizontalSizeClass == .regular {
            if width >= 720 {
                return 4
            }

            if width >= 360 {
                return 2
            }

            return 1
        }

        if width >= 760 {
            return 4
        }

        if width >= 560 {
            return 3
        }

        if width >= 320 {
            return 2
        }

        return 1
    }

    func gridItemMetrics(for actualContainerWidth: CGFloat? = nil) -> (columns: Int, itemWidth: CGFloat) {
        let resolvedWidth = max((actualContainerWidth ?? normalizedWidth).rounded(.toNearestOrAwayFromZero), 0)
        let horizontalInset = gridSectionInsets.left + gridSectionInsets.right
        let availableWidth = max(resolvedWidth - horizontalInset, 1)
        let spacing = gridInteritemSpacing
        let minimumColumns = minimumGridColumns(for: resolvedWidth)

        func itemWidth(for columns: Int) -> CGFloat {
            let totalSpacing = CGFloat(max(columns - 1, 0)) * spacing
            return floor((availableWidth - totalSpacing) / CGFloat(columns))
        }

        var columns = max(
            minimumColumns,
            Int((availableWidth + spacing) / (gridTargetItemWidth + spacing)),
            1
        )

        while columns > minimumColumns && itemWidth(for: columns) < minimumGridItemWidth {
            columns -= 1
        }

        return (columns, max(itemWidth(for: columns), 1))
    }

    var estimatedGridItemWidth: CGFloat {
        gridItemMetrics().itemWidth
    }

    var listColumnCount: Int {
        AppLayout.adaptiveListColumnCount(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: normalizedWidth
        )
    }

    var listColumnSpacing: CGFloat {
        AppLayout.adaptiveListColumnSpacing(for: listColumnCount)
    }

    static func == (lhs: RemoteServerBrowserLayoutContext, rhs: RemoteServerBrowserLayoutContext) -> Bool {
        lhs.horizontalSizeClass == rhs.horizontalSizeClass
            && Int(lhs.normalizedWidth) == Int(rhs.normalizedWidth)
    }
}

struct RemoteServerBrowserListUIKitView: UIViewControllerRepresentable {
    let sections: [RemoteBrowserListSectionModel]
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    let layoutContext: RemoteServerBrowserLayoutContext
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
            onVisibleComicIDsChanged: onVisibleComicIDsChanged,
            onOpenItem: onOpenItem,
            onShowInfo: onShowInfo,
            onOpenOffline: onOpenOffline,
            onSaveOffline: onSaveOffline,
            onRemoveOffline: onRemoveOffline,
            onImport: onImport
        )
    }

    func makeUIViewController(context: Context) -> RemoteBrowserListViewController {
        let controller = RemoteBrowserListViewController()
        controller.coordinator = context.coordinator
        context.coordinator.attach(to: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: RemoteBrowserListViewController, context: Context) {
        context.coordinator.update(
            sections: sections,
            profile: profile,
            browsingService: browsingService,
            layoutContext: layoutContext,
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

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        private enum UpdatePlan {
            case none
            case fullReload
            case reconfigureVisibleRows([IndexPath])
        }

        private var sections: [RemoteBrowserListSectionModel]
        private var profile: RemoteServerProfile
        private var browsingService: RemoteServerBrowsingService
        private var layoutContext: RemoteServerBrowserLayoutContext
        private var onVisibleComicIDsChanged: (Set<String>) -> Void
        private var onOpenItem: (RemoteDirectoryItem, CGRect) -> Void
        private var onShowInfo: (RemoteDirectoryItem) -> Void
        private var onOpenOffline: (RemoteDirectoryItem) -> Void
        private var onSaveOffline: (RemoteDirectoryItem) -> Void
        private var onRemoveOffline: (RemoteDirectoryItem) -> Void
        private var onImport: (RemoteDirectoryItem) -> Void
        private weak var controller: RemoteBrowserListViewController?
        private var pendingContextMenuAction: (() -> Void)?
        private var lastReportedVisibleComicIDs: Set<String> = []
        private var pendingVisibleComicIDReport: DispatchWorkItem?

        init(
            sections: [RemoteBrowserListSectionModel],
            profile: RemoteServerProfile,
            browsingService: RemoteServerBrowsingService,
            layoutContext: RemoteServerBrowserLayoutContext,
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
            self.onVisibleComicIDsChanged = onVisibleComicIDsChanged
            self.onOpenItem = onOpenItem
            self.onShowInfo = onShowInfo
            self.onOpenOffline = onOpenOffline
            self.onSaveOffline = onSaveOffline
            self.onRemoveOffline = onRemoveOffline
            self.onImport = onImport
        }

        func attach(to controller: RemoteBrowserListViewController) {
            self.controller = controller
        }

        func update(
            sections: [RemoteBrowserListSectionModel],
            profile: RemoteServerProfile,
            browsingService: RemoteServerBrowsingService,
            layoutContext: RemoteServerBrowserLayoutContext,
            onVisibleComicIDsChanged: @escaping (Set<String>) -> Void,
            onOpenItem: @escaping (RemoteDirectoryItem, CGRect) -> Void,
            onShowInfo: @escaping (RemoteDirectoryItem) -> Void,
            onOpenOffline: @escaping (RemoteDirectoryItem) -> Void,
            onSaveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onRemoveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onImport: @escaping (RemoteDirectoryItem) -> Void
        ) {
            let didChangeListColumnCount = self.layoutContext.listColumnCount != layoutContext.listColumnCount
            let updatePlan = didChangeListColumnCount
                ? UpdatePlan.fullReload
                : Self.makeUpdatePlan(
                    from: self.sections,
                    to: sections,
                    groupSize: layoutContext.listColumnCount
                )
            let didChangeLayoutContext = self.layoutContext != layoutContext
            self.sections = sections
            self.profile = profile
            self.browsingService = browsingService
            self.layoutContext = layoutContext
            self.onVisibleComicIDsChanged = onVisibleComicIDsChanged
            self.onOpenItem = onOpenItem
            self.onShowInfo = onShowInfo
            self.onOpenOffline = onOpenOffline
            self.onSaveOffline = onSaveOffline
            self.onRemoveOffline = onRemoveOffline
            self.onImport = onImport

            switch updatePlan {
            case .none:
                if didChangeLayoutContext {
                    controller?.refreshLayout()
                }
            case .fullReload:
                controller?.markNeedsReload()
            case .reconfigureVisibleRows(let indexPaths):
                controller?.reconfigureVisibleRows(at: indexPaths)
            }

            reportVisibleComicIDsIfNeeded()
        }

        deinit {
            pendingVisibleComicIDReport?.cancel()
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            rowGroups(in: section).count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: RemoteBrowserListCell.reuseIdentifier,
                for: indexPath
            ) as? RemoteBrowserListCell else {
                return UITableViewCell()
            }

            let rows = rowGroup(at: indexPath)
            cell.configure(
                rows: rows,
                profile: profile,
                browsingService: browsingService,
                layoutContext: layoutContext,
                onOpenItem: onOpenItem
            )
            return cell
        }

        func tableView(
            _ tableView: UITableView,
            contextMenuConfigurationForRowAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            let row: RemoteBrowserListRowModel
            if let cell = tableView.cellForRow(at: indexPath) as? RemoteBrowserListCell {
                let pointInCell = tableView.convert(point, to: cell)
                guard let resolvedRow = cell.row(at: pointInCell) else {
                    return nil
                }
                row = resolvedRow
            } else {
                guard let fallbackRow = rowGroup(at: indexPath).first else {
                    return nil
                }
                row = fallbackRow
            }

            let actions = menuElements(for: row)
            guard !actions.isEmpty else {
                return nil
            }

            return UIContextMenuConfiguration(identifier: row.item.id as NSString, previewProvider: nil) { _ in
                UIMenu(children: actions)
            }
        }

        func tableView(
            _ tableView: UITableView,
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

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            guard sections[section].kind != .notice else {
                return nil
            }

            let header = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: RemoteBrowserListSectionHeaderView.reuseIdentifier
            ) as? RemoteBrowserListSectionHeaderView ?? RemoteBrowserListSectionHeaderView(
                reuseIdentifier: RemoteBrowserListSectionHeaderView.reuseIdentifier
            )
            header.configure(with: sections[section])
            return header
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            guard let footerText = sections[section].footerText, !footerText.isEmpty else {
                return nil
            }

            let footer = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: RemoteBrowserListSectionFooterView.reuseIdentifier
            ) as? RemoteBrowserListSectionFooterView ?? RemoteBrowserListSectionFooterView(
                reuseIdentifier: RemoteBrowserListSectionFooterView.reuseIdentifier
            )
            footer.configure(text: footerText)
            return footer
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            sections[section].kind == .notice ? .leastNormalMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
            sections[section].kind == .notice ? .leastNormalMagnitude : 40
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            sections[section].footerText == nil ? .leastNormalMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat {
            sections[section].footerText == nil ? .leastNormalMagnitude : 24
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

        fileprivate func configureVisibleCell(_ cell: RemoteBrowserListCell, at indexPath: IndexPath) {
            let rows = rowGroup(at: indexPath)
            guard !rows.isEmpty else {
                return
            }

            cell.configure(
                rows: rows,
                profile: profile,
                browsingService: browsingService,
                layoutContext: layoutContext,
                onOpenItem: onOpenItem
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scheduleVisibleComicIDsReport()
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            scheduleVisibleComicIDsReport()
        }

        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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
            guard let tableView = controller?.tableView else {
                return
            }

            pendingVisibleComicIDReport = nil

            let visibleIDs = Set(
                (tableView.indexPathsForVisibleRows ?? []).flatMap { indexPath in
                    rowGroup(at: indexPath)
                        .filter { $0.item.canOpenAsComic }
                        .map(\.item.id)
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
            to newSections: [RemoteBrowserListSectionModel],
            groupSize: Int
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

                for rowIndex in oldSection.items.indices {
                    guard oldSection.items[rowIndex].id == newSection.items[rowIndex].id else {
                        return .fullReload
                    }

                    if oldSection.items[rowIndex] != newSection.items[rowIndex] {
                        changedIndexPaths.append(
                            IndexPath(
                                row: rowIndex / max(groupSize, 1),
                                section: sectionIndex
                            )
                        )
                    }
                }
            }

            if changedIndexPaths.isEmpty {
                return .none
            }

            return .reconfigureVisibleRows(Array(Set(changedIndexPaths)))
        }

        private func rowGroup(at indexPath: IndexPath) -> [RemoteBrowserListRowModel] {
            let groups = rowGroups(in: indexPath.section)
            guard indexPath.row >= 0, indexPath.row < groups.count else {
                return []
            }

            return groups[indexPath.row]
        }

        private func rowGroups(in section: Int) -> [[RemoteBrowserListRowModel]] {
            guard section >= 0, section < sections.count else {
                return []
            }

            return Self.chunked(
                sections[section].items,
                size: layoutContext.listColumnCount
            )
        }

        private static func chunked(
            _ items: [RemoteBrowserListRowModel],
            size: Int
        ) -> [[RemoteBrowserListRowModel]] {
            guard size > 1 else {
                return items.map { [$0] }
            }

            var result: [[RemoteBrowserListRowModel]] = []
            var index = 0
            while index < items.count {
                let endIndex = min(index + size, items.count)
                result.append(Array(items[index..<endIndex]))
                index = endIndex
            }
            return result
        }

    }
}

final class RemoteBrowserListViewController: UIViewController {
    weak var coordinator: RemoteServerBrowserListUIKitView.Coordinator?
    private let navigationBridge = RemoteServerBrowserNativeNavigationBridge()
    private var lastMeasuredContentWidth: Int = 0

    private(set) lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = true
        tableView.contentInsetAdjustmentBehavior = .automatic
        tableView.allowsSelection = false
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 24
        tableView.sectionHeaderTopPadding = 0
        tableView.register(RemoteBrowserListCell.self, forCellReuseIdentifier: RemoteBrowserListCell.reuseIdentifier)
        tableView.register(
            RemoteBrowserListSectionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: RemoteBrowserListSectionHeaderView.reuseIdentifier
        )
        tableView.register(
            RemoteBrowserListSectionFooterView.self,
            forHeaderFooterViewReuseIdentifier: RemoteBrowserListSectionFooterView.reuseIdentifier
        )
        return tableView
    }()

    private var needsReload = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        tableView.dataSource = coordinator
        tableView.delegate = coordinator
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationBridge.attach(scrollView: tableView, from: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationBridge.attach(scrollView: tableView, from: self)
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
        tableView.beginUpdates()
        tableView.endUpdates()
        tableView.layoutIfNeeded()
    }

    func reconfigureVisibleRows(at indexPaths: [IndexPath]) {
        guard let coordinator,
              let visibleIndexPaths = tableView.indexPathsForVisibleRows,
              !visibleIndexPaths.isEmpty else {
            return
        }

        let visibleSet = Set(visibleIndexPaths)
        let targetIndexPaths = indexPaths.filter { visibleSet.contains($0) }
        guard !targetIndexPaths.isEmpty else {
            return
        }

        UIView.performWithoutAnimation {
            for indexPath in targetIndexPaths {
                guard let cell = tableView.cellForRow(at: indexPath) as? RemoteBrowserListCell else {
                    continue
                }

                coordinator.configureVisibleCell(cell, at: indexPath)
            }
        }
    }

    func reloadIfNeeded() {
        guard needsReload else {
            return
        }

        needsReload = false
        tableView.reloadData()
        coordinator?.reportVisibleComicIDsIfNeeded()
    }

    private func handleWidthChangeIfNeeded() {
        let measuredWidth = Int(tableView.bounds.width.rounded(.toNearestOrAwayFromZero))
        guard measuredWidth > 0, measuredWidth != lastMeasuredContentWidth else {
            return
        }

        lastMeasuredContentWidth = measuredWidth
        refreshLayout()
    }
}

private final class RemoteBrowserListCell: UITableViewCell {
    static let reuseIdentifier = "RemoteBrowserListCell"

    private enum Metrics {
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 6
    }

    private let cardViews = [
        RemoteBrowserListItemCardView(),
        RemoteBrowserListItemCardView(),
        RemoteBrowserListItemCardView()
    ]
    private let cardsStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardViews.forEach { $0.prepareForReuseCard() }
    }

    func configure(
        rows: [RemoteBrowserListRowModel],
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        layoutContext: RemoteServerBrowserLayoutContext,
        onOpenItem: @escaping (RemoteDirectoryItem, CGRect) -> Void
    ) {
        let visibleCardCount = min(layoutContext.listColumnCount, cardViews.count)
        cardsStackView.spacing = layoutContext.listColumnSpacing

        for (index, cardView) in cardViews.enumerated() {
            let shouldParticipateInLayout = index < visibleCardCount
            cardView.isHidden = !shouldParticipateInLayout

            guard shouldParticipateInLayout else {
                cardView.prepareForReuseCard()
                continue
            }

            let row = index < rows.count ? rows[index] : nil
            cardView.configure(
                row: row,
                profile: profile,
                browsingService: browsingService
            ) { [weak cardView] item in
                onOpenItem(item, cardView?.heroSourceFrame() ?? .zero)
            }
        }
    }

    func row(at point: CGPoint) -> RemoteBrowserListRowModel? {
        for cardView in cardViews where !cardView.isHidden {
            let pointInCard = contentView.convert(point, to: cardView)
            if cardView.bounds.contains(pointInCard),
               let row = cardView.rowModel {
                return row
            }
        }

        return nil
    }

    private func buildUI() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear

        cardsStackView.translatesAutoresizingMaskIntoConstraints = false
        cardsStackView.axis = .horizontal
        cardsStackView.alignment = .fill
        cardsStackView.distribution = .fillEqually
        contentView.addSubview(cardsStackView)

        cardViews.forEach { cardsStackView.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            cardsStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.verticalInset),
            cardsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.horizontalInset),
            cardsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.horizontalInset),
            cardsStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.verticalInset)
        ])
    }
}

private final class RemoteBrowserListItemCardView: UIView {
    fileprivate enum Metrics {
        static let coverWidth: CGFloat = 58
        static let coverHeight: CGFloat = 87
    }

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let titleIconView = UIImageView()
    private let metadataLabel = UILabel()
    private let thumbnailImageView = UIImageView()
    private let thumbnailPlaceholderView = UIView()
    private let thumbnailPlaceholderImageView = UIImageView()
    private let symbolTileView = UIView()
    private let symbolImageView = UIImageView()
    private let cacheDotView = UIView()
    private var thumbnailTask: Task<Void, Never>?
    private var representedItemID: String?
    private var registeredHeroSourceID: String?
    private var onOpenItem: ((RemoteDirectoryItem) -> Void)?

    fileprivate private(set) var rowModel: RemoteBrowserListRowModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func prepareForReuseCard() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        unregisterHeroSourceIfNeeded()
        rowModel = nil
        representedItemID = nil
        onOpenItem = nil
        titleLabel.text = nil
        metadataLabel.text = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        thumbnailPlaceholderView.isHidden = true
        symbolTileView.isHidden = true
        cacheDotView.isHidden = true
        cardView.alpha = 0
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    fileprivate func configure(
        row: RemoteBrowserListRowModel?,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        onOpenItem: @escaping (RemoteDirectoryItem) -> Void
    ) {
        prepareForReuseCard()

        guard let row else {
            return
        }

        rowModel = row
        self.onOpenItem = onOpenItem
        representedItemID = row.item.id
        titleLabel.text = row.item.name
        configureTitlePrefix(for: row.item)
        metadataLabel.text = metadataText(for: row)
        updateHeroSourceRegistration(for: row.item)
        cardView.alpha = 1
        isUserInteractionEnabled = true
        accessibilityElementsHidden = false

        if row.item.isDirectory, !row.item.previewItems.isEmpty {
            configureDirectoryPreview(
                item: row.item,
                profile: profile,
                browsingService: browsingService
            )
            cacheDotView.isHidden = true
        } else if row.item.canOpenAsComic, !row.item.isPDFDocument {
            configureComicThumbnail(
                item: row.item,
                profile: profile,
                browsingService: browsingService,
                prefersLocalCache: row.cacheAvailability.hasLocalCopy
            )
            symbolTileView.isHidden = true
            updateCacheDot(for: row.cacheAvailability)
        } else if row.item.canOpenAsComic {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            thumbnailPlaceholderView.isHidden = true
            symbolTileView.isHidden = false
            configureSymbolTile(for: row.item)
            updateCacheDot(for: row.cacheAvailability)
        } else {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            thumbnailPlaceholderView.isHidden = true
            symbolTileView.isHidden = false
            cacheDotView.isHidden = true
            configureSymbolTile(for: row.item)
        }
    }

    fileprivate func heroSourceFrame() -> CGRect {
        thumbnailPlaceholderView.convert(thumbnailPlaceholderView.bounds, to: nil)
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 20
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.black.withAlphaComponent(0.04).cgColor
        addSubview(cardView)

        let visualContainer = UIView()
        visualContainer.translatesAutoresizingMaskIntoConstraints = false

        thumbnailPlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPlaceholderView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        thumbnailPlaceholderView.layer.cornerRadius = 16
        thumbnailPlaceholderView.layer.cornerCurve = .continuous
        thumbnailPlaceholderView.isHidden = true
        visualContainer.addSubview(thumbnailPlaceholderView)

        thumbnailPlaceholderImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPlaceholderImageView.contentMode = .scaleAspectFit
        thumbnailPlaceholderImageView.tintColor = UIColor.systemBlue.withAlphaComponent(0.85)
        thumbnailPlaceholderImageView.image = UIImage(systemName: "book.closed.fill")
        thumbnailPlaceholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .semibold
        )
        thumbnailPlaceholderView.addSubview(thumbnailPlaceholderImageView)

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 16
        thumbnailImageView.layer.cornerCurve = .continuous
        thumbnailImageView.backgroundColor = .clear
        thumbnailImageView.isHidden = true
        visualContainer.addSubview(thumbnailImageView)

        symbolTileView.translatesAutoresizingMaskIntoConstraints = false
        symbolTileView.layer.cornerRadius = 16
        symbolTileView.layer.cornerCurve = .continuous
        symbolTileView.isHidden = true
        visualContainer.addSubview(symbolTileView)

        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        symbolImageView.contentMode = .scaleAspectFit
        symbolTileView.addSubview(symbolImageView)

        cacheDotView.translatesAutoresizingMaskIntoConstraints = false
        cacheDotView.layer.cornerRadius = 4
        cacheDotView.layer.cornerCurve = .continuous
        cacheDotView.layer.shadowColor = UIColor.black.cgColor
        cacheDotView.layer.shadowOpacity = 0.25
        cacheDotView.layer.shadowRadius = 1
        cacheDotView.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        cacheDotView.isHidden = true
        visualContainer.addSubview(cacheDotView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline).bold()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.contentMode = .scaleAspectFit
        titleIconView.transform = CGAffineTransform(translationX: 0, y: 1)
        titleIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 14,
            weight: .semibold
        )

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .preferredFont(forTextStyle: .footnote)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.numberOfLines = 1

        let titleRow = UIStackView(arrangedSubviews: [titleIconView, titleLabel])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [titleRow, metadataLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        cardView.addSubview(visualContainer)
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            visualContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            visualContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            visualContainer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),
            visualContainer.widthAnchor.constraint(equalToConstant: Metrics.coverWidth),
            visualContainer.heightAnchor.constraint(equalToConstant: Metrics.coverHeight),

            thumbnailPlaceholderView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            thumbnailPlaceholderView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            thumbnailPlaceholderView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            thumbnailPlaceholderView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            thumbnailPlaceholderImageView.centerXAnchor.constraint(equalTo: thumbnailPlaceholderView.centerXAnchor),
            thumbnailPlaceholderImageView.centerYAnchor.constraint(equalTo: thumbnailPlaceholderView.centerYAnchor),

            thumbnailImageView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            symbolTileView.topAnchor.constraint(equalTo: visualContainer.topAnchor),
            symbolTileView.leadingAnchor.constraint(equalTo: visualContainer.leadingAnchor),
            symbolTileView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor),
            symbolTileView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor),

            symbolImageView.centerXAnchor.constraint(equalTo: symbolTileView.centerXAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: symbolTileView.centerYAnchor),

            cacheDotView.widthAnchor.constraint(equalToConstant: 8),
            cacheDotView.heightAnchor.constraint(equalToConstant: 8),
            cacheDotView.trailingAnchor.constraint(equalTo: visualContainer.trailingAnchor, constant: 2),
            cacheDotView.bottomAnchor.constraint(equalTo: visualContainer.bottomAnchor, constant: 2),

            titleIconView.widthAnchor.constraint(equalToConstant: 16),
            titleIconView.heightAnchor.constraint(equalToConstant: 16),

            textStack.leadingAnchor.constraint(equalTo: visualContainer.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            textStack.centerYAnchor.constraint(equalTo: visualContainer.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12)
        ])

        prepareForReuseCard()
    }

    @objc
    private func handleTap() {
        guard let item = rowModel?.item else {
            return
        }

        onOpenItem?(item)
    }

    private func configureDirectoryPreview(
        item: RemoteDirectoryItem,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService
    ) {
        symbolTileView.isHidden = true
        thumbnailImageView.isHidden = false
        thumbnailPlaceholderView.isHidden = false
        thumbnailPlaceholderImageView.image = UIImage(systemName: "folder.fill")
        thumbnailTask?.cancel()

        let targetSize = CGSize(width: Metrics.coverWidth, height: Metrics.coverHeight)
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

    private func configureComicThumbnail(
        item: RemoteDirectoryItem,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool
    ) {
        symbolTileView.isHidden = true
        thumbnailImageView.isHidden = false
        thumbnailPlaceholderView.isHidden = false
        thumbnailTask?.cancel()

        let pixelSize = Int(max(Metrics.coverWidth, Metrics.coverHeight) * UIScreen.main.scale)
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
                maxPixelSize: pixelSize
            )

            guard !Task.isCancelled, self.representedItemID == itemID else {
                return
            }

            self.thumbnailImageView.image = image
            self.thumbnailPlaceholderView.isHidden = image != nil
        }
    }

    private func configureSymbolTile(for item: RemoteDirectoryItem) {
        thumbnailPlaceholderImageView.image = UIImage(systemName: "book.closed.fill")
        let isDirectory = item.isDirectory
        let isPDF = item.isPDFDocument
        let tintColor: UIColor = isDirectory ? .systemBlue : (isPDF ? .systemRed : .systemGreen)
        let systemName: String
        if isDirectory {
            systemName = "folder.fill"
        } else if isPDF {
            systemName = "doc.text.fill"
        } else {
            systemName = "doc.richtext.fill"
        }

        symbolTileView.backgroundColor = tintColor.withAlphaComponent(0.14)
        symbolImageView.image = UIImage(systemName: systemName)
        symbolImageView.tintColor = tintColor
    }

    private func configureTitlePrefix(for item: RemoteDirectoryItem) {
        titleIconView.image = UIImage(systemName: item.titleSystemImageName)

        if item.isDirectory {
            titleIconView.tintColor = .systemBlue
        } else if item.canOpenAsComic {
            titleIconView.tintColor = .systemGreen
        } else {
            titleIconView.tintColor = .secondaryLabel
        }
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

    private func updateCacheDot(for availability: RemoteComicCachedAvailability) {
        switch availability.kind {
        case .current:
            cacheDotView.backgroundColor = .systemBlue
            cacheDotView.isHidden = false
        case .stale:
            cacheDotView.backgroundColor = .systemOrange
            cacheDotView.isHidden = false
        case .unavailable:
            cacheDotView.isHidden = true
        }
    }

    private func metadataText(for row: RemoteBrowserListRowModel) -> String {
        if row.item.isDirectory {
            let dateText = row.item.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Browse folder"
            return "Folder · \(dateText)"
        }

        if let readingSession = row.readingSession {
            return readingSession.progressText
        }

        if let badgeTitle = row.cacheAvailability.badgeTitle {
            return badgeTitle
        }

        var parts: [String] = []
        if row.item.isComicDirectory {
            if let pageCountHint = row.item.pageCountHint {
                parts.append("\(pageCountHint) pages")
            } else {
                parts.append("Image folder comic")
            }
        } else if let fileSize = row.item.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        } else {
            parts.append(row.item.canOpenAsComic ? "Comic file" : "Remote file")
        }

        if let modifiedAt = row.item.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .omitted))
        }

        return parts.joined(separator: " · ")
    }
}

private final class RemoteBrowserListSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "RemoteBrowserListSectionHeaderView"

    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with section: RemoteBrowserListSectionModel) {
        titleLabel.text = section.title
        metadataLabel.text = section.metadataText
        metadataLabel.isHidden = section.metadataText?.isEmpty ?? true
    }

    private func buildUI() {
        contentView.backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .preferredFont(forTextStyle: .caption1)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 2
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
    }
}

private final class RemoteBrowserListSectionFooterView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "RemoteBrowserListSectionFooterView"

    private let label = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .clear

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        label.text = text
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
