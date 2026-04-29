import SwiftUI

struct LibraryShortcutCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImageName: String
    let tint: Color
    let metadataText: String?
    let destination: AnyView
    let route: LibraryNavigationRoute?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImageName: String,
        tint: Color,
        metadataText: String? = nil,
        destination: AnyView,
        route: LibraryNavigationRoute? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.tint = tint
        self.metadataText = metadataText
        self.destination = destination
        self.route = route
    }
}

struct ScanCompletionBanner: View {
    let completion: LibraryScanCompletionState
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.title3(.semibold))
                .foregroundStyle(Color.appSuccess)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(completion.title)
                    .font(AppFont.subheadline(.semibold))

                Text(completion.message)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Spacing.sm)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(AppFont.caption(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(Spacing.xxs + Spacing.xxxs)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm + Spacing.xxxs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sheet, style: .continuous)
                .fill(Color.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sheet, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .appShadow(AppShadow.lg)
        .padding(.horizontal, Spacing.md)
    }
}

struct LibraryFolderRow: View {
    let folder: LibraryFolder
    let coverURL: URL?
    let previewCoverURLs: [URL]

    var body: some View {
        LibraryBrowserListRowShell {
            EmptyView()
        } thumbnail: {
            LibraryFolderThumbnailView(
                previewCoverURLs: previewCoverURLs,
                fallbackCoverURL: coverURL,
                width: 44,
                height: 62
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(folder.displayName)
                    .font(AppFont.headline())
                    .lineLimit(2)

                if let childCountText = folder.childCountText {
                    Text(childCountText)
                        .font(AppFont.subheadline())
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text(folder.path)
                        .font(AppFont.subheadline())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                if let metadataText = folder.browserMetadataText {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } trailingAccessory: {
            EmptyView()
        }
    }
}

struct LibraryShortcutCard: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        InsetCard(cornerRadius: CornerRadius.sheet, contentPadding: CornerRadius.sheet, strokeOpacity: 0.06) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(item.title)
                        .font(AppFont.headline())

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }

                    if let metadataText = item.metadataText {
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: item.systemImageName)
                    .font(AppFont.title2(.semibold))
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? 108 : 132, alignment: .topLeading)
    }
}

struct LibraryShortcutRow: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(item.title)
                        .font(.headline)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let metadataText = item.metadataText {
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: item.systemImageName)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

struct ContinueReadingRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        LibraryBrowserListRowShell(spacing: Spacing.md, trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            EmptyView()
        } thumbnail: {
            ContinueReadingCoverThumbnail(
                url: coverURL,
                heroSourceID: heroSourceID,
                coverSource: coverSource,
                width: 78,
                height: 112,
                badgeSize: 30
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let metadataText = comic.browserMetadataText {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                ComicStatusMetaRow(
                    progressText: comic.progressText,
                    isRead: comic.read,
                    isFavorite: comic.isFavorite,
                    bookmarkCount: comic.bookmarkPageIndices.count
                )
            }
        } trailingAccessory: {
            EmptyView()
        }
    }
}

struct ContinueReadingCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil

    var body: some View {
        LibraryBrowserContentCard(minHeight: 188, cornerRadius: 20, contentPadding: 20) {
            HStack(spacing: Spacing.md) {
                ContinueReadingCoverThumbnail(
                    url: coverURL,
                    heroSourceID: heroSourceID,
                    coverSource: coverSource,
                    width: 104,
                    height: 148,
                    badgeSize: 34
                )

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(comic.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(comic.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let metadataText = comic.browserMetadataText {
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    ComicStatusMetaRow(
                        progressText: comic.progressText,
                        isRead: comic.read,
                        isFavorite: comic.isFavorite,
                        bookmarkCount: comic.bookmarkPageIndices.count
                    )

                    Spacer(minLength: 0)

                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct ContinueReadingCoverThumbnail: View {
    let url: URL?
    let heroSourceID: String?
    let coverSource: LocalComicCoverSource?
    let width: CGFloat
    let height: CGFloat
    let badgeSize: CGFloat

    var body: some View {
        LocalCoverThumbnailView(
            url: url,
            fallbackSource: coverSource,
            placeholderSystemName: "book.closed.fill",
            transitionKey: heroSourceID,
            heroSourceID: heroSourceID,
            width: width,
            height: height
        )
        .overlay(alignment: .bottomTrailing) {
            ContinueReadingPlayBadge(size: badgeSize)
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}

private struct ContinueReadingPlayBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.58))

            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 0.75)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

struct LibraryFolderCard: View {
    let folder: LibraryFolder
    let coverURL: URL?
    let previewCoverURLs: [URL]

    var body: some View {
        LibraryBrowserContentCard(minHeight: 250) {
            LibraryFolderThumbnailView(
                previewCoverURLs: previewCoverURLs,
                fallbackCoverURL: coverURL,
                width: 96,
                height: 120
            )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(folder.displayName)
                    .font(.headline)
                    .lineLimit(2)

                Text(folder.childCountText ?? folder.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let metadataText = folder.browserMetadataText {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct LibraryFolderThumbnailView: View {
    let previewCoverURLs: [URL]
    let fallbackCoverURL: URL?
    let width: CGFloat
    let height: CGFloat

    private let outerCornerRadius: CGFloat = 12
    private let inset: CGFloat = 4
    private let gap: CGFloat = 4

    var body: some View {
        let covers = Array(previewCoverURLs.prefix(4))

        Group {
            if covers.isEmpty {
                LocalCoverThumbnailView(
                    url: fallbackCoverURL,
                    placeholderSystemName: "folder.fill",
                    width: width,
                    height: height
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))

                    folderCoverLayout(for: covers)
                        .padding(inset)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func folderCoverLayout(for covers: [URL]) -> some View {
        switch covers.count {
        case 1:
            coverCell(url: covers[0], width: width - (inset * 2), height: height - (inset * 2))
        case 2:
            HStack(spacing: gap) {
                ForEach(covers.indices, id: \.self) { index in
                    coverCell(
                        url: covers[index],
                        width: twoColumnCellWidth,
                        height: height - (inset * 2)
                    )
                }
            }
        case 3:
            HStack(spacing: gap) {
                coverCell(
                    url: covers[0],
                    width: threeCoverLeadWidth,
                    height: height - (inset * 2)
                )

                VStack(spacing: gap) {
                    coverCell(url: covers[1], width: threeCoverTrailingWidth, height: twoRowCellHeight)
                    coverCell(url: covers[2], width: threeCoverTrailingWidth, height: twoRowCellHeight)
                }
            }
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    coverCell(url: covers[0], width: twoColumnCellWidth, height: twoRowCellHeight)
                    coverCell(url: covers[1], width: twoColumnCellWidth, height: twoRowCellHeight)
                }

                HStack(spacing: gap) {
                    coverCell(url: covers[2], width: twoColumnCellWidth, height: twoRowCellHeight)
                    coverCell(url: covers[3], width: twoColumnCellWidth, height: twoRowCellHeight)
                }
            }
        }
    }

    private func coverCell(url: URL, width: CGFloat, height: CGFloat) -> some View {
        LocalCoverThumbnailView(
            url: url,
            placeholderSystemName: "book.closed.fill",
            width: width,
            height: height
        )
    }

    private var innerWidth: CGFloat {
        width - (inset * 2)
    }

    private var innerHeight: CGFloat {
        height - (inset * 2)
    }

    private var twoColumnCellWidth: CGFloat {
        max(0, (innerWidth - gap) / 2)
    }

    private var twoRowCellHeight: CGFloat {
        max(0, (innerHeight - gap) / 2)
    }

    private var threeCoverLeadWidth: CGFloat {
        max(0, innerWidth * 0.58)
    }

    private var threeCoverTrailingWidth: CGFloat {
        max(0, innerWidth - threeCoverLeadWidth - gap)
    }
}

struct LibraryComicRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var showsSelectionState = false
    var isSelected = false
    var trailingAccessoryReservedWidth: CGFloat = 0

    private let coverWidth: CGFloat = 72
    private let coverHeight: CGFloat = 104

    var body: some View {
        LibraryBrowserListRowShell(
            spacing: Spacing.md,
            trailingAccessoryReservedWidth: trailingAccessoryReservedWidth
        ) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            } else {
                EmptyView()
            }
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                fallbackSource: coverSource,
                placeholderSystemName: "book.closed.fill",
                transitionKey: heroSourceID,
                heroSourceID: heroSourceID,
                width: coverWidth,
                height: coverHeight
            )
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comic.displayTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if comic.subtitle != comic.fileName {
                            Text(comic.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if let badgeTitle = comic.rowPrimaryBadgeTitle {
                        LibraryComicRowBadge(title: badgeTitle)
                    }
                }

                InlineMetadataLine(
                    items: comic.rowMetadataItems,
                    horizontalSpacing: 12,
                    verticalSpacing: 4
                )

                ComicStatusMetaRow(
                    progressText: comic.progressText,
                    isRead: comic.read,
                    isFavorite: comic.isFavorite,
                    bookmarkCount: comic.bookmarkPageIndices.count
                )
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        } trailingAccessory: {
            EmptyView()
        }
    }
}

extension LibraryComicRow: Equatable {
    static func == (lhs: LibraryComicRow, rhs: LibraryComicRow) -> Bool {
        lhs.comic == rhs.comic
            && lhs.coverURL == rhs.coverURL
            && lhs.coverSource == rhs.coverSource
            && lhs.heroSourceID == rhs.heroSourceID
            && lhs.showsSelectionState == rhs.showsSelectionState
            && lhs.isSelected == rhs.isSelected
            && lhs.trailingAccessoryReservedWidth == rhs.trailingAccessoryReservedWidth
    }
}

private struct LibraryComicRowBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.accentColor.opacity(0.12),
                in: Capsule(style: .continuous)
            )
    }
}

struct LibraryComicCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var showsSelectionState = false
    var isSelected = false

    var body: some View {
        LibraryBrowserContentCard(
            minHeight: 0,
            cornerRadius: 20,
            contentPadding: 0,
            strokeOpacity: 0.05,
            isSelected: showsSelectionState && isSelected
        ) {
            VStack(alignment: .leading, spacing: 0) {
                LibraryComicCardCover(
                    comic: comic,
                    coverURL: coverURL,
                    coverSource: coverSource,
                    heroSourceID: heroSourceID
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(comic.displayTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if comic.subtitle != comic.fileName {
                        Text(comic.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    InlineMetadataLine(
                        items: comic.rowMetadataItems,
                        horizontalSpacing: 8,
                        verticalSpacing: 4
                    )

                    ComicStatusMetaRow(
                        progressText: comic.progressText,
                        isRead: comic.read,
                        isFavorite: comic.isFavorite,
                        bookmarkCount: comic.bookmarkPageIndices.count
                    )
                    .padding(.top, 2)
                }
                .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                    .padding(Spacing.sm)
            }
        }
    }
}

private struct LibraryComicCardCover: View {
    let comic: LibraryComic
    let coverURL: URL?
    let coverSource: LocalComicCoverSource?
    let heroSourceID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LocalCoverThumbnailView(
                    url: coverURL,
                    fallbackSource: coverSource,
                    placeholderSystemName: "book.closed.fill",
                    transitionKey: heroSourceID,
                    heroSourceID: heroSourceID,
                    width: max(proxy.size.width, 1),
                    height: max(proxy.size.height, 1)
                )

                if let badgeTitle = comic.rowPrimaryBadgeTitle {
                    LibraryComicRowBadge(title: badgeTitle)
                        .padding(10)
                }
            }
        }
        .aspectRatio(AppLayout.coverAspectRatio, contentMode: .fit)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
    }
}

extension LibraryComicCard: Equatable {
    static func == (lhs: LibraryComicCard, rhs: LibraryComicCard) -> Bool {
        lhs.comic == rhs.comic
            && lhs.coverURL == rhs.coverURL
            && lhs.coverSource == rhs.coverSource
            && lhs.heroSourceID == rhs.heroSourceID
            && lhs.showsSelectionState == rhs.showsSelectionState
            && lhs.isSelected == rhs.isSelected
    }
}

struct LibraryBrowserContentCard<Content: View>: View {
    let minHeight: CGFloat
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 18
    var strokeOpacity: Double = 0.06
    var isSelected = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            strokeOpacity: strokeOpacity
        ) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

struct LibraryBrowserListRowShell<
    LeadingAccessory: View,
    Thumbnail: View,
    Content: View,
    TrailingAccessory: View
>: View {
    var spacing: CGFloat = Spacing.sm
    var trailingAccessoryReservedWidth: CGFloat = 0
    @ViewBuilder let leadingAccessory: () -> LeadingAccessory
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailingAccessory: () -> TrailingAccessory

    var body: some View {
        HStack(spacing: spacing) {
            leadingAccessory()
            thumbnail()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingAccessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .contentShape(Rectangle())
    }
}

extension LibraryFolder {
    var browserMetadataText: String? {
        var parts: [String] = []

        if !isRoot && type != .comic {
            parts.append(type.title)
        }

        if finished {
            parts.append("Finished")
        } else if completed {
            parts.append("Complete")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension LibraryComic {
    var browserMetadataText: String? {
        var parts: [String] = []

        if let issueLabel {
            parts.append("#\(issueLabel)")
        }

        if type != .comic || parts.isEmpty {
            parts.append(type.title)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var rowPrimaryBadgeTitle: String? {
        if let issueLabel {
            return "#\(issueLabel)"
        }

        guard type != .comic else {
            return nil
        }

        return type.title.uppercased()
    }

    var rowMetadataItems: [InlineMetadataItem] {
        var items: [InlineMetadataItem] = []

        if issueLabel == nil, type != .comic {
            items.append(
                InlineMetadataItem(
                    systemImage: "doc.text.image",
                    text: type.title
                )
            )
        }

        if let pageCount, pageCount > 0, hasBeenOpened || read {
            items.append(
                InlineMetadataItem(
                    systemImage: "rectangle.stack.fill",
                    text: "\(pageCount) pages"
                )
            )
        }

        if let fileSizeText {
            items.append(
                InlineMetadataItem(
                    systemImage: "internaldrive",
                    text: fileSizeText
                )
            )
        }

        if let rating, rating > 0 {
            items.append(
                InlineMetadataItem(
                    systemImage: "star.fill",
                    text: rating.formatted(.number.precision(.fractionLength(1))),
                    tint: Color.appFavorite
                )
            )
        }

        if hasBeenOpened, let lastOpenedAt {
            items.append(
                InlineMetadataItem(
                    systemImage: "clock",
                    text: lastOpenedAt.formatted(.relative(presentation: .named))
                )
            )
        }

        return items
    }
}
