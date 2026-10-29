import SwiftUI

// Grid and list items for local comics and folders. See
// docs/design-system/components/ComicCover, ComicRow and FolderAndCollection.

/// Grid item: cover, two-line title and one status line. Tapping it reads.
struct LibraryComicCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var showsSelectionState = false
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LibraryComicCardCover(
                comic: comic,
                coverURL: coverURL,
                coverSource: coverSource,
                heroSourceID: heroSourceID,
                showsSelectionState: showsSelectionState,
                isSelected: isSelected
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(comic.displayTitle)
                    .font(AppFont.footnote(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                LibraryComicStatusLine(comic: comic)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilitySelectionState(
            isPresented: showsSelectionState,
            isSelected: isSelected
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

private struct LibraryComicCardCover: View {
    let comic: LibraryComic
    let coverURL: URL?
    let coverSource: LocalComicCoverSource?
    let heroSourceID: String?
    let showsSelectionState: Bool
    let isSelected: Bool

    var body: some View {
        Color.clear
            .aspectRatio(AppLayout.coverAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    LocalCoverThumbnailView(
                        url: coverURL,
                        fallbackSource: coverSource,
                        placeholderSystemName: "book.closed",
                        transitionKey: heroSourceID,
                        heroSourceID: heroSourceID,
                        width: max(proxy.size.width, 1),
                        height: max(proxy.size.height, 1)
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if let fraction = comic.readingFraction {
                    LibraryCoverProgressBar(fraction: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // One corner badge at a time; local comics only show the favorite star.
                if comic.isFavorite, !showsSelectionState {
                    LibraryCoverCornerBadge(systemImage: "star.fill", tint: .appFavorite)
                        .padding(Spacing.xxs)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsSelectionState {
                    LibrarySelectionMark(isSelected: isSelected)
                        .padding(Spacing.xs)
                }
            }
            .appShadow(AppShadow.sm)
    }
}

/// 3pt jam bar along the bottom edge of a cover, on a translucent white track.
struct LibraryCoverProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.55))

                Rectangle()
                    .fill(Color.appJam)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct LibraryCoverCornerBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .background(Color(.systemBackground).opacity(0.92), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Round selection mark; unselected items are not dimmed.
struct LibrarySelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.appJam)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appOnJam)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.18))
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Status line under a cover or title: Unread, Read to 42% or Read.
struct LibraryComicStatusLine: View {
    let comic: LibraryComic

    var body: some View {
        HStack(spacing: Spacing.xxxs) {
            if comic.read {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appSuccess)
            }

            Text(comic.coverStatusText)
                .foregroundStyle(Color.textSecondary)
        }
        .font(AppFont.caption().monospacedDigit())
        .lineLimit(1)
    }
}

/// List row: small cover, one-line title, "status · fact" and a progress bar
/// while reading. The trailing More button is added by the page.
struct LibraryComicRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var showsSelectionState = false
    var isSelected = false
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if showsSelectionState {
                LibraryListSelectionMark(isSelected: isSelected)
            }

            LocalCoverThumbnailView(
                url: coverURL,
                fallbackSource: coverSource,
                placeholderSystemName: "book.closed",
                transitionKey: heroSourceID,
                heroSourceID: heroSourceID,
                width: AppLayout.listThumbnailSize * AppLayout.coverAspectRatio,
                height: AppLayout.listThumbnailSize
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(comic.displayTitle)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                HStack(spacing: Spacing.xxxs) {
                    if comic.read {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.appSuccess)
                    }

                    Text(comic.rowStatusLine)
                        .foregroundStyle(Color.textSecondary)
                }
                .font(AppFont.footnote().monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                if let fraction = comic.readingFraction {
                    JamProgressBar(fraction: fraction, height: 3)
                        .frame(width: 120)
                        .padding(.top, Spacing.xxxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: AppLayout.listRowHeight)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilitySelectionState(
            isPresented: showsSelectionState,
            isSelected: isSelected
        )
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

struct LibraryListSelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.appJam : Color.textTertiary)
            .accessibilityHidden(true)
    }
}

/// Folder grid item: same 2:3 size as a cover, up to three covers fanned on
/// `surface-2`, with the item count in the lower-left corner.
struct LibraryFolderCard: View {
    let folder: LibraryFolder
    let coverURL: URL?
    let previewCoverURLs: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Color.clear
                .aspectRatio(AppLayout.coverAspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        LibraryFolderCoverStack(
                            coverURLs: folderCoverURLs,
                            size: proxy.size
                        )
                    }
                }
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if let count = folder.numChildren {
                        Label("\(count)", systemImage: "folder.fill")
                            .font(AppFont.caption2().monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                            .labelStyle(.titleAndIcon)
                            .padding(Spacing.xs)
                    }
                }

            Text(folder.displayName)
                .font(AppFont.footnote(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(folder.accessibilitySummary)
    }

    private var folderCoverURLs: [URL] {
        let previews = Array(previewCoverURLs.prefix(3))
        if previews.isEmpty, let coverURL {
            return [coverURL]
        }
        return previews
    }
}

private struct LibraryFolderCoverStack: View {
    let coverURLs: [URL]
    let size: CGSize

    var body: some View {
        let coverWidth = size.width * 0.6
        let coverHeight = coverWidth / AppLayout.coverAspectRatio

        ZStack {
            if coverURLs.isEmpty {
                Image(systemName: "folder.fill")
                    .font(.system(size: size.width * 0.28, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            } else {
                // Back to front: the first cover is drawn last, on top.
                ForEach(Array(coverURLs.enumerated().reversed()), id: \.offset) { index, url in
                    LocalCoverThumbnailView(
                        url: url,
                        placeholderSystemName: "book.closed",
                        width: coverWidth,
                        height: coverHeight
                    )
                    .rotationEffect(.degrees(Self.angles[index]))
                    .offset(x: Self.offsets[index] * size.width)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(y: -size.height * 0.04)
    }

    private static let angles: [Double] = [0, -7, 7]
    private static let offsets: [CGFloat] = [0, -0.08, 0.08]
}

/// Folder list row: accent folder icon in place of a cover, then the name and count.
struct LibraryFolderRow: View {
    let folder: LibraryFolder
    let coverURL: URL?
    let previewCoverURLs: [URL]

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Color.appAccent)
                .frame(
                    width: AppLayout.listThumbnailSize * AppLayout.coverAspectRatio,
                    height: AppLayout.listThumbnailSize
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(folder.displayName)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if let countText = folder.childCountText {
                    Text(countText)
                        .font(AppFont.footnote().monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(AppFont.footnote(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: AppLayout.listRowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Collection entry on the library root: name, count and a tinted icon on `surface-2`.
struct LibraryCollectionCard: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            LibraryCollectionBadge(systemImageName: item.systemImageName, tint: item.tint)
                // Large text gives the width to the name; the icon stops growing.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text(item.title)
                .font(AppFont.body(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let metadataText = item.metadataText {
                Text(metadataText)
                    .font(AppFont.subheadline().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Tinted icon in a circle that grows with the glyph.
private struct LibraryCollectionBadge: View {
    let systemImageName: String
    let tint: Color

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImageName)
            .font(AppFont.subheadline(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

extension LibraryComic {
    /// Fraction read while a comic is in progress; `nil` when unread or finished.
    var readingFraction: Double? {
        guard !read, hasBeenOpened, currentPage > 0,
              let pageCount, pageCount > 0 else {
            return nil
        }

        return min(max(Double(currentPage) / Double(pageCount), 0), 1)
    }

    /// The single status shown under a cover: Unread, Read to 42% or Read.
    var coverStatusText: String {
        if read {
            return String(localized: "Read")
        }

        if let readingFraction {
            let percent = Int((readingFraction * 100).rounded())
            return String(localized: "Read to \(percent)%")
        }

        return String(localized: "Unread")
    }

    /// "Status · fact" for list rows.
    var rowStatusLine: String {
        let status: String
        if read {
            status = String(localized: "Read")
        } else if hasBeenOpened, currentPage > 0, let pageCount, pageCount > 0 {
            return String(localized: "Page \(currentPage) / \(pageCount)")
        } else {
            status = String(localized: "Unread")
        }

        if read, let lastOpenedAt {
            return "\(status) · \(lastOpenedAt.formatted(.relative(presentation: .named)))"
        }

        if let pageCount, pageCount > 0 {
            return "\(status) · \(String(localized: "\(pageCount) pages"))"
        }

        if let fileSizeText {
            return "\(status) · \(fileSizeText)"
        }

        return status
    }
}

extension LibraryFolder {
    var accessibilitySummary: String {
        if let childCountText {
            return "\(displayName), \(childCountText)"
        }
        return displayName
    }
}
