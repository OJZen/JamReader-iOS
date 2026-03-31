import SwiftUI

struct ReaderControlsSheet: View {
    let pageState: ReaderControlsPageState
    let displayState: ReaderControlsDisplayState
    let capabilities: ReaderControlsCapabilities
    let actions: ReaderControlsActions
    var metadata: ReaderControlsMetadata? = nil

    var body: some View {
        ReaderControlsContainer(title: "Settings", onDone: actions.onDone) {
            ReaderNavigationControlsSection(
                pageIndicatorText: pageState.pageIndicatorText,
                currentPageNumber: pageState.currentPageNumber,
                pageCount: pageState.pageCount,
                onOpenThumbnails: actions.onOpenThumbnails,
                onGoToPageNumber: actions.onGoToPageNumber
            )

            ReaderReadingStatusControlsSection(
                currentPageIsBookmarked: pageState.currentPageIsBookmarked,
                isFavorite: metadata?.isFavorite,
                isRead: metadata?.isRead,
                rating: metadata?.rating,
                onToggleFavorite: actions.onToggleFavorite,
                onToggleReadStatus: actions.onToggleReadStatus,
                onToggleBookmark: actions.onToggleBookmark,
                onSetRating: actions.onSetRating
            )

            ReaderLibraryActionsControlsSection(
                onOpenQuickMetadata: actions.onOpenQuickMetadata,
                onOpenMetadata: actions.onOpenMetadata,
                onOpenOrganization: actions.onOpenOrganization
            )

            ReaderDisplaySettingsControlsSection(
                supportsImageLayoutControls: capabilities.supportsImageLayoutControls,
                supportsDoublePageSpread: capabilities.supportsDoublePageSpread,
                fitMode: displayState.fitMode,
                pagingMode: displayState.pagingMode,
                spreadMode: displayState.spreadMode,
                readingDirection: displayState.readingDirection,
                coverAsSinglePage: displayState.coverAsSinglePage,
                onSetFitMode: actions.onSetFitMode,
                onSetPagingMode: actions.onSetPagingMode,
                onSetSpreadMode: actions.onSetSpreadMode,
                onSetReadingDirection: actions.onSetReadingDirection,
                onSetCoverAsSinglePage: actions.onSetCoverAsSinglePage
            )

            ReaderRotationControlsSection(
                supportsRotationControls: capabilities.supportsRotationControls,
                rotation: displayState.rotation,
                onRotateCounterClockwise: actions.onRotateCounterClockwise,
                onRotateClockwise: actions.onRotateClockwise,
                onResetRotation: actions.onResetRotation
            )

            ReaderBookmarksControlsSection(
                bookmarkItems: pageState.bookmarkItems,
                onGoToBookmark: actions.onGoToBookmark
            )
        }
    }
}
