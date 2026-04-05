import SwiftUI
import UIKit

struct RemoteServerBrowserGridUIKitView: UIViewControllerRepresentable {
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
        private var sections: [RemoteBrowserListSectionModel]
        private var profile: RemoteServerProfile
        private var browsingService: RemoteServerBrowsingService
        private var onOpenItem: (RemoteDirectoryItem) -> Void
        private var onShowInfo: (RemoteDirectoryItem) -> Void
        private var onOpenOffline: (RemoteDirectoryItem) -> Void
        private var onSaveOffline: (RemoteDirectoryItem) -> Void
        private var onRemoveOffline: (RemoteDirectoryItem) -> Void
        private var onImport: (RemoteDirectoryItem) -> Void
        private weak var controller: RemoteBrowserGridViewController?

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

        func attach(to controller: RemoteBrowserGridViewController) {
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
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RemoteBrowserGridCell.reuseIdentifier,
                for: indexPath
            ) as? RemoteBrowserGridCell else {
                return UICollectionViewCell()
            }

            let row = sections[indexPath.section].items[indexPath.item]
            cell.configure(
                row: row,
                profile: profile,
                browsingService: browsingService,
                itemWidth: itemWidth(for: collectionView)
            )
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            onOpenItem(sections[indexPath.section].items[indexPath.item].item)
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
            let imageHeight = width / AppLayout.coverAspectRatio
            let labelHeight: CGFloat = 72
            return CGSize(width: width, height: imageHeight + labelHeight)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            guard sections[section].kind != .notice else {
                return .zero
            }
            return CGSize(width: collectionView.bounds.width, height: 40)
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
            if sections[section].kind == .notice {
                return UIEdgeInsets(top: 0, left: 16, bottom: 20, right: 16)
            }
            return UIEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumLineSpacingForSectionAt section: Int
        ) -> CGFloat {
            collectionView.traitCollection.horizontalSizeClass == .regular ? 16 : 12
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            minimumInteritemSpacingForSectionAt section: Int
        ) -> CGFloat {
            collectionView.traitCollection.horizontalSizeClass == .regular ? 14 : 10
        }

        private func itemWidth(for collectionView: UICollectionView) -> CGFloat {
            let horizontalInset: CGFloat = 32
            let spacing: CGFloat = collectionView.traitCollection.horizontalSizeClass == .regular ? 14 : 10
            let availableWidth = max(collectionView.bounds.width - horizontalInset, 0)
            let minimumWidth: CGFloat = collectionView.traitCollection.horizontalSizeClass == .regular ? 214 : 160
            let maximumWidth: CGFloat = collectionView.traitCollection.horizontalSizeClass == .regular ? 292 : 212
            let columns = max(Int((availableWidth + spacing) / (minimumWidth + spacing)), 1)
            let totalSpacing = CGFloat(max(columns - 1, 0)) * spacing
            let rawWidth = floor((availableWidth - totalSpacing) / CGFloat(columns))
            return min(maximumWidth, rawWidth)
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

final class RemoteBrowserGridViewController: UIViewController {
    weak var coordinator: RemoteServerBrowserGridUIKitView.Coordinator?
    private let navigationBridge = RemoteServerBrowserNativeNavigationBridge()

    private(set) lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.sectionInsetReference = .fromSafeArea
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        collectionView.register(RemoteBrowserGridCell.self, forCellWithReuseIdentifier: RemoteBrowserGridCell.reuseIdentifier)
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

    func markNeedsReload() {
        needsReload = true
    }

    func reloadIfNeeded() {
        guard needsReload else {
            return
        }
        needsReload = false
        collectionView.reloadData()
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
    private let symbolView = UIView()
    private let symbolImageView = UIImageView()
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
        representedItemID = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
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
        titleLabel.text = row.item.name
        metadataLabel.text = metadataText(for: row)
        imageHeightConstraint?.constant = itemWidth / AppLayout.coverAspectRatio

        if row.item.canOpenAsComic {
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
        } else {
            thumbnailTask?.cancel()
            thumbnailTask = nil
            thumbnailImageView.isHidden = true
            symbolView.isHidden = false
            cacheBadgeView.isHidden = true
            progressTrackView.isHidden = true
            configureSymbolView(for: row.item)
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

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .tertiarySystemGroupedBackground
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

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
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

            thumbnailImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageHeightConstraint!,

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
        symbolView.isHidden = true
        thumbnailTask?.cancel()

        let pixelSize = Int(max(itemWidth, itemWidth / AppLayout.coverAspectRatio) * UIScreen.main.scale)
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
                maxPixelSize: pixelSize,
                allowsRemoteFetch: true
            )
            guard !Task.isCancelled, self.representedItemID == itemID else {
                return
            }
            self.thumbnailImageView.image = image
        }
    }

    private func configureSymbolView(for item: RemoteDirectoryItem) {
        let isDirectory = item.isDirectory
        symbolView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.16)
        symbolImageView.image = UIImage(systemName: isDirectory ? "folder.fill" : "doc.fill")
        symbolImageView.tintColor = .systemBlue
        symbolImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 34,
            weight: .semibold
        )
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
        if let badgeTitle = row.cacheAvailability.badgeTitle {
            return badgeTitle
        }
        var parts: [String] = []
        if let fileSize = row.item.fileSize {
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
