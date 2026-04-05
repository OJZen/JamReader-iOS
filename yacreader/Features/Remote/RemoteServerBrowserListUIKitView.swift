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

struct RemoteServerBrowserListUIKitView: UIViewControllerRepresentable {
    let sections: [RemoteBrowserListSectionModel]
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    let onOpenItem: (RemoteDirectoryItem) -> Void
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
        private var sections: [RemoteBrowserListSectionModel]
        private var profile: RemoteServerProfile
        private var browsingService: RemoteServerBrowsingService
        private var onOpenItem: (RemoteDirectoryItem) -> Void
        private var onShowInfo: (RemoteDirectoryItem) -> Void
        private var onOpenOffline: (RemoteDirectoryItem) -> Void
        private var onSaveOffline: (RemoteDirectoryItem) -> Void
        private var onRemoveOffline: (RemoteDirectoryItem) -> Void
        private var onImport: (RemoteDirectoryItem) -> Void
        private weak var controller: RemoteBrowserListViewController?

        init(
            sections: [RemoteBrowserListSectionModel],
            profile: RemoteServerProfile,
            browsingService: RemoteServerBrowsingService,
            onOpenItem: @escaping (RemoteDirectoryItem) -> Void,
            onShowInfo: @escaping (RemoteDirectoryItem) -> Void,
            onOpenOffline: @escaping (RemoteDirectoryItem) -> Void,
            onSaveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onRemoveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onImport: @escaping (RemoteDirectoryItem) -> Void
        ) {
            self.sections = sections
            self.profile = profile
            self.browsingService = browsingService
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
            onOpenItem: @escaping (RemoteDirectoryItem) -> Void,
            onShowInfo: @escaping (RemoteDirectoryItem) -> Void,
            onOpenOffline: @escaping (RemoteDirectoryItem) -> Void,
            onSaveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onRemoveOffline: @escaping (RemoteDirectoryItem) -> Void,
            onImport: @escaping (RemoteDirectoryItem) -> Void
        ) {
            let sectionsChanged = self.sections != sections
            self.sections = sections
            self.profile = profile
            self.browsingService = browsingService
            self.onOpenItem = onOpenItem
            self.onShowInfo = onShowInfo
            self.onOpenOffline = onOpenOffline
            self.onSaveOffline = onSaveOffline
            self.onRemoveOffline = onRemoveOffline
            self.onImport = onImport

            if sectionsChanged {
                controller?.markNeedsReload()
            }
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            sections[section].items.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: RemoteBrowserListCell.reuseIdentifier,
                for: indexPath
            ) as? RemoteBrowserListCell else {
                return UITableViewCell()
            }

            let row = sections[indexPath.section].items[indexPath.row]
            cell.configure(
                row: row,
                profile: profile,
                browsingService: browsingService
            )
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            onOpenItem(sections[indexPath.section].items[indexPath.row].item)
        }

        func tableView(
            _ tableView: UITableView,
            contextMenuConfigurationForRowAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            let row = sections[indexPath.section].items[indexPath.row]
            let actions = menuElements(for: row)
            guard !actions.isEmpty else {
                return nil
            }

            return UIContextMenuConfiguration(identifier: row.item.id as NSString, previewProvider: nil) { _ in
                UIMenu(children: actions)
            }
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            nil
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
            .leastNormalMagnitude
        }

        func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
            .leastNormalMagnitude
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            sections[section].footerText == nil ? .leastNormalMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat {
            sections[section].footerText == nil ? .leastNormalMagnitude : 24
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let row = sections[indexPath.section].items[indexPath.row]
            var actions: [UIContextualAction] = []

            if row.item.canOpenAsComic {
                let saveAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
                    self?.onSaveOffline(row.item)
                    completion(true)
                }
                saveAction.image = UIImage(
                    systemName: row.cacheAvailability.kind == .unavailable
                        ? "icloud.and.arrow.down"
                        : "arrow.clockwise.icloud"
                )
                saveAction.backgroundColor = row.cacheAvailability.kind == .unavailable
                    ? .systemBlue
                    : .systemOrange
                actions.append(saveAction)

                if row.cacheAvailability.hasLocalCopy {
                    let removeAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
                        self?.onRemoveOffline(row.item)
                        completion(true)
                    }
                    removeAction.image = UIImage(systemName: "trash")
                    actions.append(removeAction)
                }
            } else if row.item.isDirectory {
                let importAction = UIContextualAction(style: .normal, title: nil) { [weak self] _, _, completion in
                    self?.onImport(row.item)
                    completion(true)
                }
                importAction.image = UIImage(systemName: "square.and.arrow.down")
                importAction.backgroundColor = .systemTeal
                actions.append(importAction)
            }

            guard !actions.isEmpty else {
                return nil
            }

            let configuration = UISwipeActionsConfiguration(actions: actions)
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }

        private func menuElements(for row: RemoteBrowserListRowModel) -> [UIMenuElement] {
            var actions: [UIMenuElement] = []

            if row.item.canOpenAsComic {
                actions.append(
                    UIAction(
                        title: "Info",
                        image: UIImage(systemName: "info.circle")
                    ) { [weak self] _ in
                        self?.onShowInfo(row.item)
                    }
                )

                if row.cacheAvailability.hasLocalCopy {
                    actions.append(
                        UIAction(
                            title: "Open Offline",
                            image: UIImage(systemName: "arrow.down.circle")
                        ) { [weak self] _ in
                            self?.onOpenOffline(row.item)
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
                        self?.onSaveOffline(row.item)
                    }
                )

                if row.cacheAvailability.hasLocalCopy {
                    actions.append(
                        UIAction(
                            title: "Remove Download",
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive
                        ) { [weak self] _ in
                            self?.onRemoveOffline(row.item)
                        }
                    )
                }
            } else if row.item.isDirectory {
                actions.append(
                    UIAction(
                        title: "Import",
                        image: UIImage(systemName: "square.and.arrow.down")
                    ) { [weak self] _ in
                        self?.onImport(row.item)
                    }
                )
            }

            return actions
        }

    }
}

final class RemoteBrowserListViewController: UIViewController {
    weak var coordinator: RemoteServerBrowserListUIKitView.Coordinator?
    private let navigationBridge = RemoteServerBrowserNativeNavigationBridge()

    private(set) lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = true
        tableView.contentInsetAdjustmentBehavior = .automatic
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

    func markNeedsReload() {
        needsReload = true
    }

    func reloadIfNeeded() {
        guard needsReload else {
            return
        }

        needsReload = false
        tableView.reloadData()
    }
}

private final class RemoteBrowserListCell: UITableViewCell {
    static let reuseIdentifier = "RemoteBrowserListCell"
    private enum Metrics {
        static let coverWidth: CGFloat = 58
        static let coverHeight: CGFloat = 87
    }

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let thumbnailImageView = UIImageView()
    private let symbolTileView = UIView()
    private let symbolImageView = UIImageView()
    private let cacheDotView = UIView()
    private var thumbnailTask: Task<Void, Never>?
    private var representedItemID: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedItemID = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        symbolTileView.isHidden = true
        cacheDotView.isHidden = true
    }

    func configure(
        row: RemoteBrowserListRowModel,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService
    ) {
        representedItemID = row.item.id
        titleLabel.text = row.item.name
        metadataLabel.text = metadataText(for: row)

        if row.item.canOpenAsComic {
            configureComicThumbnail(
                item: row.item,
                profile: profile,
                browsingService: browsingService,
                prefersLocalCache: row.cacheAvailability.hasLocalCopy
            )
            symbolTileView.isHidden = true
            updateCacheDot(for: row.cacheAvailability)
        } else {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            symbolTileView.isHidden = false
            cacheDotView.isHidden = true
            configureSymbolTile(for: row.item)
        }
    }

    private func buildUI() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 20
        cardView.layer.cornerCurve = .continuous
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.black.withAlphaComponent(0.04).cgColor
        contentView.addSubview(cardView)

        let visualContainer = UIView()
        visualContainer.translatesAutoresizingMaskIntoConstraints = false

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = 16
        thumbnailImageView.layer.cornerCurve = .continuous
        thumbnailImageView.backgroundColor = .secondarySystemBackground
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

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .preferredFont(forTextStyle: .footnote)
        metadataLabel.textColor = .secondaryLabel
        metadataLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        cardView.addSubview(visualContainer)
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            visualContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            visualContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            visualContainer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),
            visualContainer.widthAnchor.constraint(equalToConstant: Metrics.coverWidth),
            visualContainer.heightAnchor.constraint(equalToConstant: Metrics.coverHeight),

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

            textStack.leadingAnchor.constraint(equalTo: visualContainer.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            textStack.centerYAnchor.constraint(equalTo: visualContainer.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    private func configureComicThumbnail(
        item: RemoteDirectoryItem,
        profile: RemoteServerProfile,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool
    ) {
        symbolTileView.isHidden = true
        thumbnailImageView.isHidden = false
        thumbnailTask?.cancel()

        let pixelSize = Int(max(Metrics.coverWidth, Metrics.coverHeight) * UIScreen.main.scale)
        let itemID = item.id

        Task { @MainActor in
            let seeded = RemoteComicThumbnailPipeline.shared.cachedImage(
                for: item,
                browsingService: browsingService,
                maxPixelSize: pixelSize
            )
            if self.representedItemID == itemID, let seeded {
                self.thumbnailImageView.image = seeded
            }
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
        }
    }

    private func configureSymbolTile(for item: RemoteDirectoryItem) {
        let isDirectory = item.isDirectory
        symbolTileView.backgroundColor = (isDirectory ? UIColor.systemBlue : UIColor.systemGreen).withAlphaComponent(0.14)
        symbolImageView.image = UIImage(
            systemName: isDirectory ? "folder.fill" : "doc.richtext.fill"
        )
        symbolImageView.tintColor = isDirectory ? .systemBlue : .systemGreen
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
        if let fileSize = row.item.fileSize {
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
