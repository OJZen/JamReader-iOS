import SwiftUI

struct ComicListRow: View {
    let comic: LibraryComic
    let coverURL: URL?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: AppLayout.listThumbnailSize,
                height: AppLayout.listThumbnailSize / AppLayout.coverAspectRatio
            )

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                titleLine

                Text(comic.subtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingMetadata
        }
        .frame(minHeight: AppLayout.listRowHeight)
    }

    // MARK: - Title

    private var titleLine: some View {
        HStack(spacing: Spacing.xs) {
            Text(comic.displayTitle)
                .font(AppFont.headline())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            if let issueLabel = comic.issueLabel {
                StatusBadge(title: "#\(issueLabel)", tint: .blue)
            }
        }
    }

    // MARK: - Status

    private var statusLine: some View {
        HStack(spacing: Spacing.xs) {
            Label(comic.progressText, systemImage: comic.read ? "checkmark.circle.fill" : "book.closed")
                .font(AppFont.caption(.medium))
                .foregroundStyle(comic.read ? Color.statusRead : Color.statusUnread)

            if comic.isFavorite {
                Label("Favorite", systemImage: "star.fill")
                    .font(AppFont.caption(.medium))
                    .foregroundStyle(Color.appFavorite)
                    .labelStyle(.iconOnly)
            }

            if !comic.bookmarkPageIndices.isEmpty {
                Label("\(comic.bookmarkPageIndices.count)", systemImage: "bookmark.fill")
                    .font(AppFont.caption(.medium))
                    .foregroundStyle(Color.appAccent)
            }
        }
    }

    // MARK: - Trailing Metadata

    private var trailingMetadata: some View {
        VStack(alignment: .trailing, spacing: Spacing.xxs) {
            if let pageCount = comic.pageCount, pageCount > 0 {
                Text("\(pageCount)p")
                    .font(AppFont.caption(.medium))
                    .foregroundStyle(Color.textTertiary)
            }

            if let rating = comic.rating, rating > 0 {
                HStack(spacing: Spacing.xxxs) {
                    Image(systemName: "star.fill")
                        .font(AppFont.caption2())
                        .foregroundStyle(Color.appFavorite)

                    Text(String(format: "%.0f", rating))
                        .font(AppFont.caption(.medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }
}
