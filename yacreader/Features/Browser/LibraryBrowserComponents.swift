import SwiftUI

struct LibraryShortcutCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImageName: String
    let tint: Color
    let badgeTitle: String?
    let destination: AnyView

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImageName: String,
        tint: Color,
        badgeTitle: String? = nil,
        destination: AnyView
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.tint = tint
        self.badgeTitle = badgeTitle
        self.destination = destination
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

    var body: some View {
        LibraryBrowserListRowShell {
            EmptyView()
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "folder.fill"
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

                AdaptiveStatusBadgeGroup(badges: folder.browserBadgeItems)
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
                }
            } icon: {
                Image(systemName: item.systemImageName)
                    .font(AppFont.title2(.semibold))
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)

            if let badgeTitle = item.badgeTitle {
                StatusBadge(title: badgeTitle, tint: item.tint)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? 108 : 132, alignment: .topLeading)
    }
}

struct LibraryShortcutRow: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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

            if let badgeTitle = item.badgeTitle {
                StatusBadge(title: badgeTitle, tint: item.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContinueReadingRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        LibraryBrowserListRowShell(spacing: 14, trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            EmptyView()
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: 64,
                height: 92
            )
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AdaptiveStatusBadgeGroup(badges: comic.continueReadingRowBadges)
            }
        } trailingAccessory: {
            Image(systemName: "play.fill")
                .foregroundStyle(.blue)
        }
    }
}

struct ContinueReadingCard: View {
    let comic: LibraryComic
    let coverURL: URL?

    var body: some View {
        LibraryBrowserContentCard(minHeight: 188, cornerRadius: 20, contentPadding: 20) {
            HStack(spacing: 18) {
                LocalCoverThumbnailView(
                    url: coverURL,
                    placeholderSystemName: "book.closed.fill",
                    width: 104,
                    height: 148
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(comic.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(comic.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    AdaptiveStatusBadgeGroup(badges: comic.continueReadingCardBadges)

                    Spacer(minLength: 0)

                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct LibraryFolderCard: View {
    let folder: LibraryFolder
    let coverURL: URL?

    var body: some View {
        LibraryBrowserContentCard(minHeight: 250) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "folder.fill",
                width: 96,
                height: 120
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(folder.displayName)
                    .font(.headline)
                    .lineLimit(2)

                Text(folder.childCountText ?? folder.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                AdaptiveStatusBadgeGroup(badges: folder.browserBadgeItems)
            }
        }
    }
}

struct LibraryComicRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var showsSelectionState = false
    var isSelected = false
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        LibraryBrowserListRowShell(trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
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
                placeholderSystemName: "book.closed.fill"
            )
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(comic.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let issueLabel = comic.issueLabel {
                        StatusBadge(title: "#\(issueLabel)", tint: .blue)
                    }
                }

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AdaptiveStatusBadgeGroup(badges: comic.browserRowBadges)
            }
        } trailingAccessory: {
            EmptyView()
        }
    }
}

extension LibraryComicRow: Equatable {
    static func == (lhs: LibraryComicRow, rhs: LibraryComicRow) -> Bool {
        lhs.comic == rhs.comic
            && lhs.coverURL == rhs.coverURL
            && lhs.showsSelectionState == rhs.showsSelectionState
            && lhs.isSelected == rhs.isSelected
            && lhs.trailingAccessoryReservedWidth == rhs.trailingAccessoryReservedWidth
    }
}

struct LibraryComicCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var showsSelectionState = false
    var isSelected = false

    var body: some View {
        LibraryBrowserContentCard(minHeight: 330, isSelected: showsSelectionState && isSelected) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: 120,
                height: 168
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                AdaptiveStatusBadgeGroup(badges: comic.browserCardBadges)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                    .padding(14)
            }
        }
    }
}

extension LibraryComicCard: Equatable {
    static func == (lhs: LibraryComicCard, rhs: LibraryComicCard) -> Bool {
        lhs.comic == rhs.comic
            && lhs.coverURL == rhs.coverURL
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
    var spacing: CGFloat = 12
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
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

extension LibraryFolder {
    var browserBadgeItems: [StatusBadgeItem] {
        var badges = [StatusBadgeItem(title: type.title, tint: .orange)]

        if finished {
            badges.append(StatusBadgeItem(title: "Finished", tint: .green))
        } else if completed {
            badges.append(StatusBadgeItem(title: "Complete", tint: .blue))
        }

        return badges
    }
}

extension LibraryComic {
    var issueBadgeItem: StatusBadgeItem? {
        issueLabel.map { StatusBadgeItem(title: "#\($0)", tint: .blue) }
    }

    var continueReadingRowBadges: [StatusBadgeItem] {
        var badges = [StatusBadgeItem(title: progressText, tint: read ? .green : .orange)]

        if !bookmarkPageIndices.isEmpty {
            badges.append(StatusBadgeItem(title: "\(bookmarkPageIndices.count) bookmarks", tint: .blue))
        }

        return badges
    }

    var continueReadingCardBadges: [StatusBadgeItem] {
        [
            StatusBadgeItem(title: progressText, tint: read ? .green : .orange),
            StatusBadgeItem(title: type.title, tint: .gray)
        ]
    }

    var browserRowBadges: [StatusBadgeItem] {
        var badges: [StatusBadgeItem] = []
        badges.append(StatusBadgeItem(title: progressText, tint: read ? .green : .orange))
        badges.append(StatusBadgeItem(title: type.title, tint: .gray))

        if isFavorite {
            badges.append(StatusBadgeItem(title: "Favorite", tint: .yellow))
        }

        if !bookmarkPageIndices.isEmpty {
            badges.append(StatusBadgeItem(title: "\(bookmarkPageIndices.count) bookmarks", tint: .blue))
        }

        return badges
    }

    var browserCardBadges: [StatusBadgeItem] {
        var badges = browserRowBadges

        if let issueBadgeItem {
            badges.insert(issueBadgeItem, at: 0)
        }

        return badges
    }
}
