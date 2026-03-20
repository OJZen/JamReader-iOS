import SwiftUI

struct ReaderControlsContainer<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ReaderControlsHeader(title: title)

                Form {
                    content()
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReaderControlsHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))

                Image(systemName: "book.pages.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text("Adjust navigation, reading layout, and library actions without leaving the page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }
}

struct ReaderNavigationControlsSection: View {
    let pageIndicatorText: String?
    let currentPageNumber: Int?
    let pageCount: Int?
    let onOpenThumbnails: () -> Void
    let onGoToPageNumber: (Int) -> Void

    @State private var selectedPageNumber: Double

    init(
        pageIndicatorText: String?,
        currentPageNumber: Int?,
        pageCount: Int?,
        onOpenThumbnails: @escaping () -> Void,
        onGoToPageNumber: @escaping (Int) -> Void
    ) {
        self.pageIndicatorText = pageIndicatorText
        self.currentPageNumber = currentPageNumber
        self.pageCount = pageCount
        self.onOpenThumbnails = onOpenThumbnails
        self.onGoToPageNumber = onGoToPageNumber
        _selectedPageNumber = State(initialValue: Double(currentPageNumber ?? 1))
    }

    private var canUsePageSlider: Bool {
        guard let pageCount else {
            return false
        }

        return pageCount > 1
    }

    private var normalizedSelectedPageNumber: Int {
        guard let pageCount else {
            return Int(selectedPageNumber.rounded())
        }

        return min(max(1, Int(selectedPageNumber.rounded())), pageCount)
    }

    var body: some View {
        if let pageIndicatorText {
            Section("Navigate") {
                LabeledContent("Current Page", value: pageIndicatorText)

                Button(action: onOpenThumbnails) {
                    Label("Browse Thumbnails", systemImage: "square.grid.3x2")
                }

                if canUsePageSlider, let pageCount {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Quick Scrub")
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Text("Page \(normalizedSelectedPageNumber) / \(pageCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: $selectedPageNumber,
                            in: 1...Double(pageCount),
                            step: 1
                        )

                        Button {
                            onGoToPageNumber(normalizedSelectedPageNumber)
                        } label: {
                            Label("Open Selected Page", systemImage: "play.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onChange(of: currentPageNumber) { _, newValue in
                if let newValue {
                    selectedPageNumber = Double(newValue)
                }
            }
        }
    }
}

struct ReaderBookmarksControlsSection: View {
    let bookmarkItems: [ReaderBookmarkItem]
    let onGoToBookmark: (Int) -> Void

    var body: some View {
        if !bookmarkItems.isEmpty {
            Section("Bookmarks") {
                ForEach(bookmarkItems) { bookmark in
                    Button {
                        onGoToBookmark(bookmark.pageIndex)
                    } label: {
                        Label("Page \(bookmark.pageNumber)", systemImage: "bookmark.fill")
                    }
                }
            }
        }
    }
}

struct ReaderReadingStatusControlsSection: View {
    let currentPageIsBookmarked: Bool
    let isFavorite: Bool?
    let isRead: Bool?
    let rating: Int?
    let onToggleFavorite: (() -> Void)?
    let onToggleReadStatus: (() -> Void)?
    let onToggleBookmark: () -> Void
    let onSetRating: ((Int) -> Void)?

    private var ratingBinding: Binding<Int>? {
        guard let rating, let onSetRating else {
            return nil
        }

        return Binding(
            get: { rating },
            set: onSetRating
        )
    }

    var body: some View {
        Section("Reading Status") {
            if let onToggleFavorite, let isFavorite {
                Button(action: onToggleFavorite) {
                    Label(
                        isFavorite ? "Remove Favorite" : "Add Favorite",
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
            }

            if let onToggleReadStatus, let isRead {
                Button(action: onToggleReadStatus) {
                    Label(
                        isRead ? "Mark Unread" : "Mark Read",
                        systemImage: isRead ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                }
            }

            Button(action: onToggleBookmark) {
                Label(
                    currentPageIsBookmarked ? "Remove Current Bookmark" : "Bookmark Current Page",
                    systemImage: currentPageIsBookmarked ? "bookmark.slash" : "bookmark"
                )
            }

            if let ratingBinding {
                Picker("Rating", selection: ratingBinding) {
                    Text("Unrated").tag(0)
                    ForEach(1...5, id: \.self) { value in
                        Text(value == 1 ? "1 Star" : "\(value) Stars").tag(value)
                    }
                }
            }
        }
    }
}

struct ReaderLibraryActionsControlsSection: View {
    let onOpenQuickMetadata: (() -> Void)?
    let onOpenMetadata: (() -> Void)?
    let onOpenOrganization: (() -> Void)?

    private var hasActions: Bool {
        onOpenQuickMetadata != nil || onOpenMetadata != nil || onOpenOrganization != nil
    }

    var body: some View {
        if hasActions {
            Section("Library") {
                if let onOpenQuickMetadata {
                    Button(action: onOpenQuickMetadata) {
                        Label("Quick Edit Metadata", systemImage: "pencil")
                    }
                }

                if let onOpenMetadata {
                    Button(action: onOpenMetadata) {
                        Label("Edit Metadata", systemImage: "square.and.pencil")
                    }
                }

                if let onOpenOrganization {
                    Button(action: onOpenOrganization) {
                        Label("Tags and Reading Lists", systemImage: "tag")
                    }
                }
            }
        }
    }
}

struct ReaderDisplaySettingsControlsSection: View {
    let supportsImageLayoutControls: Bool
    let supportsDoublePageSpread: Bool
    let fitMode: ReaderFitMode
    let pagingMode: ReaderPagingMode
    let spreadMode: ReaderSpreadMode
    let readingDirection: ReaderReadingDirection
    let coverAsSinglePage: Bool
    let onSetFitMode: (ReaderFitMode) -> Void
    let onSetPagingMode: (ReaderPagingMode) -> Void
    let onSetSpreadMode: (ReaderSpreadMode) -> Void
    let onSetReadingDirection: (ReaderReadingDirection) -> Void
    let onSetCoverAsSinglePage: (Bool) -> Void

    private var fitModeBinding: Binding<ReaderFitMode> {
        Binding(
            get: { fitMode },
            set: onSetFitMode
        )
    }

    private var spreadModeBinding: Binding<ReaderSpreadMode> {
        Binding(
            get: { spreadMode },
            set: onSetSpreadMode
        )
    }

    private var pagingModeBinding: Binding<ReaderPagingMode> {
        Binding(
            get: { pagingMode },
            set: onSetPagingMode
        )
    }

    private var readingDirectionBinding: Binding<ReaderReadingDirection> {
        Binding(
            get: { readingDirection },
            set: onSetReadingDirection
        )
    }

    private var coverAsSinglePageBinding: Binding<Bool> {
        Binding(
            get: { coverAsSinglePage },
            set: onSetCoverAsSinglePage
        )
    }

    private var isVerticalContinuousMode: Bool {
        pagingMode == .verticalContinuous
    }

    var body: some View {
        if supportsImageLayoutControls {
            Section {
                Picker("Reading Mode", selection: pagingModeBinding) {
                    ForEach(ReaderPagingMode.allCases, id: \.self) { pagingMode in
                        Text(pagingMode.title).tag(pagingMode)
                    }
                }
                .pickerStyle(.segmented)

                if !isVerticalContinuousMode {
                    Picker("Fit Mode", selection: fitModeBinding) {
                        ForEach(ReaderFitMode.allCases, id: \.self) { fitMode in
                            Text(fitMode.title).tag(fitMode)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Page Layout")
                            .font(.subheadline.weight(.medium))

                        if supportsDoublePageSpread {
                            Picker("Page Layout", selection: spreadModeBinding) {
                                ForEach(ReaderSpreadMode.allCases, id: \.self) { spreadMode in
                                    Text(spreadMode.title).tag(spreadMode)
                                }
                            }
                            .pickerStyle(.segmented)
                        } else {
                            LabeledContent("Mode", value: ReaderSpreadMode.singlePage.title)
                            Text("iPhone uses single-page reading. Double-page mode is available on iPad.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Reading Direction")
                            .font(.subheadline.weight(.medium))

                        Picker("Reading Direction", selection: readingDirectionBinding) {
                            ForEach(ReaderReadingDirection.allCases, id: \.self) { readingDirection in
                                Text(readingDirection.title).tag(readingDirection)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    if supportsDoublePageSpread, spreadMode == .doublePage {
                        Toggle("Show Covers as Single Page", isOn: coverAsSinglePageBinding)
                    }
                } else {
                    Text("Vertical mode is optimized for mobile scrolling. Page spread and rotation controls are hidden for consistency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Layout preferences are remembered separately for comics and manga, matching mobile reading habits.")
            }
        }
    }
}

struct ReaderRotationControlsSection: View {
    let supportsRotationControls: Bool
    let rotation: ReaderRotationAngle
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onResetRotation: () -> Void

    var body: some View {
        if supportsRotationControls {
            Section("Rotation") {
                LabeledContent("Current Rotation", value: rotation.title)

                Button(action: onRotateCounterClockwise) {
                    Label("Rotate Left", systemImage: "rotate.left")
                }

                Button(action: onRotateClockwise) {
                    Label("Rotate Right", systemImage: "rotate.right")
                }

                if rotation != .degrees0 {
                    Button(action: onResetRotation) {
                        Label("Reset Rotation", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
    }
}

struct ReaderRotatedContentHost<Content: View>: View {
    let rotation: ReaderRotationAngle
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let outerSize = proxy.size
            let innerSize = rotation.isQuarterTurn
                ? CGSize(width: outerSize.height, height: outerSize.width)
                : outerSize

            content()
                .frame(width: innerSize.width, height: innerSize.height)
                .rotationEffect(.degrees(Double(rotation.rawValue)))
                .position(x: outerSize.width * 0.5, y: outerSize.height * 0.5)
        }
        .clipped()
    }
}
