import SwiftUI

struct ComicGridItem: View {
    let comic: LibraryComic
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            coverThumbnail

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(comic.displayTitle)
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if comic.subtitle != comic.fileName || comic.issueLabel != nil {
                    subtitleLine
                }
            }

            statusIndicators
        }
    }

    // MARK: - Cover

    private var coverThumbnail: some View {
        LocalCoverThumbnailView(
            url: coverURL,
            placeholderSystemName: "book.closed.fill",
            width: AppLayout.gridItemMaxWidth,
            height: AppLayout.gridItemMaxWidth / AppLayout.coverAspectRatio
        )
        .aspectRatio(AppLayout.coverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))
        .appShadow(AppShadow.thumbnail)
        .overlay(alignment: .topLeading) {
            readBadgeOverlay
        }
        .overlay(alignment: .topTrailing) {
            favoriteBadgeOverlay
        }
    }

    @ViewBuilder
    private var readBadgeOverlay: some View {
        if comic.read {
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.caption(.bold))
                .foregroundStyle(.white)
                .padding(Spacing.xxs)
                .background(Color.statusRead, in: Circle())
                .padding(Spacing.xs)
        }
    }

    @ViewBuilder
    private var favoriteBadgeOverlay: some View {
        if comic.isFavorite {
            Image(systemName: "star.fill")
                .font(AppFont.caption2(.bold))
                .foregroundStyle(Color.appFavorite)
                .padding(Spacing.xxs)
                .background(.ultraThinMaterial, in: Circle())
                .padding(Spacing.xs)
        }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleLine: some View {
        HStack(spacing: Spacing.xxs) {
            if let issueLabel = comic.issueLabel {
                Text("#\(issueLabel)")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.appAccent)
            }

            Text(comic.subtitle)
                .font(AppFont.caption2())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusIndicators: some View {
        HStack(spacing: Spacing.xxs) {
            if let rating = comic.rating, rating > 0 {
                ratingLabel(rating)
            }

            Text(comic.progressText)
                .font(AppFont.caption2(.medium))
                .foregroundStyle(comic.read ? Color.statusRead : Color.statusUnread)
        }
    }

    private func ratingLabel(_ rating: Double) -> some View {
        HStack(spacing: Spacing.xxxs) {
            Image(systemName: "star.fill")
                .font(AppFont.caption2())
                .foregroundStyle(Color.appFavorite)

            Text(String(format: "%.0f", rating))
                .font(AppFont.caption2(.medium))
                .foregroundStyle(Color.textSecondary)
        }
    }
}
