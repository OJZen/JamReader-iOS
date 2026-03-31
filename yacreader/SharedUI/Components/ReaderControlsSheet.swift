import SwiftUI

struct ReaderControlsSheet: View {
    let pageState: ReaderControlsPageState
    let displayState: ReaderControlsDisplayState
    let capabilities: ReaderControlsCapabilities
    let actions: ReaderControlsActions
    var metadata: ReaderControlsMetadata? = nil

    var body: some View {
        ReaderControlsContainer(title: "Settings", onDone: actions.onDone) {
            ReaderLayoutControlsSection(
                supportsImageLayoutControls: capabilities.supportsImageLayoutControls,
                supportsDoublePageSpread: capabilities.supportsDoublePageSpread,
                pagingMode: displayState.pagingMode,
                spreadMode: displayState.spreadMode,
                readingDirection: displayState.readingDirection,
                coverAsSinglePage: displayState.coverAsSinglePage,
                onSetPagingMode: actions.onSetPagingMode,
                onSetSpreadMode: actions.onSetSpreadMode,
                onSetReadingDirection: actions.onSetReadingDirection,
                onSetCoverAsSinglePage: actions.onSetCoverAsSinglePage
            )

            ReaderViewControlsSection(
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
