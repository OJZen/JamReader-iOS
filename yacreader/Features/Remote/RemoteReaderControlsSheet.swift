import SwiftUI

struct RemoteReaderControlsSheet: View {
    let pageIndicatorText: String?
    let currentPageNumber: Int?
    let pageCount: Int?
    let currentPageIsBookmarked: Bool
    let bookmarkItems: [ReaderBookmarkItem]
    let isRefreshingRemoteCopy: Bool
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
    let onOpenPageJump: () -> Void
    let onToggleBookmark: () -> Void
    let onGoToBookmark: (Int) -> Void
    let onGoToPageNumber: (Int) -> Void
    let onRefreshRemoteCopy: () -> Void
    let onSetFitMode: (ReaderFitMode) -> Void
    let onSetPagingMode: (ReaderPagingMode) -> Void
    let onSetSpreadMode: (ReaderSpreadMode) -> Void
    let onSetReadingDirection: (ReaderReadingDirection) -> Void
    let onSetCoverAsSinglePage: (Bool) -> Void
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onResetRotation: () -> Void

    var body: some View {
        ReaderControlsContainer(title: "Reader Controls", onDone: onDone) {
            ReaderNavigationControlsSection(
                pageIndicatorText: pageIndicatorText,
                currentPageNumber: currentPageNumber,
                pageCount: pageCount,
                onOpenThumbnails: onOpenThumbnails,
                onOpenPageJump: onOpenPageJump,
                onGoToPageNumber: onGoToPageNumber
            )

            Section("Reading Status") {
                Button(action: onToggleBookmark) {
                    Label(
                        currentPageIsBookmarked ? "Remove Current Bookmark" : "Bookmark Current Page",
                        systemImage: currentPageIsBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }
            }

            ReaderBookmarksControlsSection(
                bookmarkItems: bookmarkItems,
                onGoToBookmark: onGoToBookmark
            )

            Section("Remote") {
                Button(action: onRefreshRemoteCopy) {
                    Label(
                        isRefreshingRemoteCopy ? "Refreshing Remote Copy..." : "Refresh Remote Copy",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isRefreshingRemoteCopy)
            }

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
