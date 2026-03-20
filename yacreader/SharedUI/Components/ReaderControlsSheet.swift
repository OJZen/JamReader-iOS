import SwiftUI

struct ReaderControlsSheet: View {
    let pageIndicatorText: String?
    let currentPageNumber: Int?
    let pageCount: Int?
    let currentPageIsBookmarked: Bool
    let bookmarkItems: [ReaderBookmarkItem]
    let supportsImageLayoutControls: Bool
    let supportsDoublePageSpread: Bool
    let supportsRotationControls: Bool
    let fitMode: ReaderFitMode
    let pagingMode: ReaderPagingMode
    let spreadMode: ReaderSpreadMode
    let readingDirection: ReaderReadingDirection
    let coverAsSinglePage: Bool
    let rotation: ReaderRotationAngle
    let onDone: () -> Void
    let onOpenThumbnails: () -> Void
    let onToggleBookmark: () -> Void
    let onGoToBookmark: (Int) -> Void
    let onGoToPageNumber: (Int) -> Void
    let onSetFitMode: (ReaderFitMode) -> Void
    let onSetPagingMode: (ReaderPagingMode) -> Void
    let onSetSpreadMode: (ReaderSpreadMode) -> Void
    let onSetReadingDirection: (ReaderReadingDirection) -> Void
    let onSetCoverAsSinglePage: (Bool) -> Void
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onResetRotation: () -> Void
    var isFavorite: Bool? = nil
    var isRead: Bool? = nil
    var rating: Int? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var onToggleReadStatus: (() -> Void)? = nil
    var onSetRating: ((Int) -> Void)? = nil
    var onOpenQuickMetadata: (() -> Void)? = nil
    var onOpenMetadata: (() -> Void)? = nil
    var onOpenOrganization: (() -> Void)? = nil

    init(
        pageIndicatorText: String?,
        currentPageNumber: Int?,
        pageCount: Int?,
        currentPageIsBookmarked: Bool,
        bookmarkItems: [ReaderBookmarkItem],
        isFavorite: Bool? = nil,
        isRead: Bool? = nil,
        rating: Int? = nil,
        supportsImageLayoutControls: Bool,
        supportsDoublePageSpread: Bool,
        supportsRotationControls: Bool,
        fitMode: ReaderFitMode,
        pagingMode: ReaderPagingMode,
        spreadMode: ReaderSpreadMode,
        readingDirection: ReaderReadingDirection,
        coverAsSinglePage: Bool,
        rotation: ReaderRotationAngle,
        onDone: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        onToggleReadStatus: (() -> Void)? = nil,
        onOpenQuickMetadata: (() -> Void)? = nil,
        onOpenMetadata: (() -> Void)? = nil,
        onOpenOrganization: (() -> Void)? = nil,
        onOpenThumbnails: @escaping () -> Void,
        onToggleBookmark: @escaping () -> Void,
        onSetRating: ((Int) -> Void)? = nil,
        onGoToBookmark: @escaping (Int) -> Void,
        onGoToPageNumber: @escaping (Int) -> Void,
        onSetFitMode: @escaping (ReaderFitMode) -> Void,
        onSetPagingMode: @escaping (ReaderPagingMode) -> Void,
        onSetSpreadMode: @escaping (ReaderSpreadMode) -> Void,
        onSetReadingDirection: @escaping (ReaderReadingDirection) -> Void,
        onSetCoverAsSinglePage: @escaping (Bool) -> Void,
        onRotateCounterClockwise: @escaping () -> Void,
        onRotateClockwise: @escaping () -> Void,
        onResetRotation: @escaping () -> Void
    ) {
        self.pageIndicatorText = pageIndicatorText
        self.currentPageNumber = currentPageNumber
        self.pageCount = pageCount
        self.currentPageIsBookmarked = currentPageIsBookmarked
        self.bookmarkItems = bookmarkItems
        self.supportsImageLayoutControls = supportsImageLayoutControls
        self.supportsDoublePageSpread = supportsDoublePageSpread
        self.supportsRotationControls = supportsRotationControls
        self.fitMode = fitMode
        self.pagingMode = pagingMode
        self.spreadMode = spreadMode
        self.readingDirection = readingDirection
        self.coverAsSinglePage = coverAsSinglePage
        self.rotation = rotation
        self.onDone = onDone
        self.onOpenThumbnails = onOpenThumbnails
        self.onToggleBookmark = onToggleBookmark
        self.onGoToBookmark = onGoToBookmark
        self.onGoToPageNumber = onGoToPageNumber
        self.onSetFitMode = onSetFitMode
        self.onSetPagingMode = onSetPagingMode
        self.onSetSpreadMode = onSetSpreadMode
        self.onSetReadingDirection = onSetReadingDirection
        self.onSetCoverAsSinglePage = onSetCoverAsSinglePage
        self.onRotateCounterClockwise = onRotateCounterClockwise
        self.onRotateClockwise = onRotateClockwise
        self.onResetRotation = onResetRotation
        self.isFavorite = isFavorite
        self.isRead = isRead
        self.rating = rating
        self.onToggleFavorite = onToggleFavorite
        self.onToggleReadStatus = onToggleReadStatus
        self.onSetRating = onSetRating
        self.onOpenQuickMetadata = onOpenQuickMetadata
        self.onOpenMetadata = onOpenMetadata
        self.onOpenOrganization = onOpenOrganization
    }

    var body: some View {
        ReaderControlsContainer(title: "Reader Controls", onDone: onDone) {
            ReaderNavigationControlsSection(
                pageIndicatorText: pageIndicatorText,
                currentPageNumber: currentPageNumber,
                pageCount: pageCount,
                onOpenThumbnails: onOpenThumbnails,
                onGoToPageNumber: onGoToPageNumber
            )

            ReaderReadingStatusControlsSection(
                currentPageIsBookmarked: currentPageIsBookmarked,
                isFavorite: isFavorite,
                isRead: isRead,
                rating: rating,
                onToggleFavorite: onToggleFavorite,
                onToggleReadStatus: onToggleReadStatus,
                onToggleBookmark: onToggleBookmark,
                onSetRating: onSetRating
            )

            ReaderBookmarksControlsSection(
                bookmarkItems: bookmarkItems,
                onGoToBookmark: onGoToBookmark
            )

            ReaderLibraryActionsControlsSection(
                onOpenQuickMetadata: onOpenQuickMetadata,
                onOpenMetadata: onOpenMetadata,
                onOpenOrganization: onOpenOrganization
            )

            ReaderDisplaySettingsControlsSection(
                supportsImageLayoutControls: supportsImageLayoutControls,
                supportsDoublePageSpread: supportsDoublePageSpread,
                fitMode: fitMode,
                pagingMode: pagingMode,
                spreadMode: spreadMode,
                readingDirection: readingDirection,
                coverAsSinglePage: coverAsSinglePage,
                onSetFitMode: onSetFitMode,
                onSetPagingMode: onSetPagingMode,
                onSetSpreadMode: onSetSpreadMode,
                onSetReadingDirection: onSetReadingDirection,
                onSetCoverAsSinglePage: onSetCoverAsSinglePage
            )

            ReaderRotationControlsSection(
                supportsRotationControls: supportsRotationControls,
                rotation: rotation,
                onRotateCounterClockwise: onRotateCounterClockwise,
                onRotateClockwise: onRotateClockwise,
                onResetRotation: onResetRotation
            )
        }
    }
}
