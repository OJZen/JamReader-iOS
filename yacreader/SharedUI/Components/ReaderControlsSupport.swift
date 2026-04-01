import SwiftUI

// MARK: - Config Objects

/// Groups the current page navigation state for the reader controls sheet.
struct ReaderControlsPageState {
    let pageIndicatorText: String?
    let currentPageNumber: Int?
    let pageCount: Int?
    let currentPageIsBookmarked: Bool
    let bookmarkItems: [ReaderBookmarkItem]
}

/// Groups the current display/layout settings for the reader controls sheet.
struct ReaderControlsDisplayState {
    let fitMode: ReaderFitMode
    let pagingMode: ReaderPagingMode
    let spreadMode: ReaderSpreadMode
    let readingDirection: ReaderReadingDirection
    let coverAsSinglePage: Bool
    let rotation: ReaderRotationAngle
}

/// Feature capability flags for the reader controls sheet.
struct ReaderControlsCapabilities {
    let supportsImageLayoutControls: Bool
    let supportsDoublePageSpread: Bool
    let supportsRotationControls: Bool
}

/// Optional library metadata for the reader controls sheet.
/// Nil when viewing remote comics without library integration.
struct ReaderControlsMetadata {
    let isFavorite: Bool?
    let isRead: Bool?
    let rating: Int?
}

/// File-level info displayed in the reader controls sheet.
/// All fields are optional so the section degrades gracefully for remote comics.
struct ReaderControlsFileInfo {
    let fileName: String
    let fileExtension: String?
    let pageCount: Int?
    let series: String?
    let volume: String?
    let addedAt: Date?
    let lastOpenedAt: Date?
    /// Used to compute file size lazily — may be nil for remote comics.
    let fileURL: URL?
}

/// All callback actions for the reader controls sheet.
struct ReaderControlsActions {
    // Navigation
    let onDone: () -> Void
    let onOpenThumbnails: () -> Void
    let onGoToBookmark: (Int) -> Void
    let onGoToPageNumber: (Int) -> Void

    // Bookmarks
    let onToggleBookmark: () -> Void

    // Layout
    let onSetFitMode: (ReaderFitMode) -> Void
    let onSetPagingMode: (ReaderPagingMode) -> Void
    let onSetSpreadMode: (ReaderSpreadMode) -> Void
    let onSetReadingDirection: (ReaderReadingDirection) -> Void
    let onSetCoverAsSinglePage: (Bool) -> Void

    // Rotation
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onResetRotation: () -> Void

    // Optional metadata actions (nil for remote reader)
    var onToggleFavorite: (() -> Void)? = nil
    var onToggleReadStatus: (() -> Void)? = nil
    var onSetRating: ((Int) -> Void)? = nil
    var onOpenQuickMetadata: (() -> Void)? = nil
    var onOpenMetadata: (() -> Void)? = nil
    var onOpenOrganization: (() -> Void)? = nil
}

// MARK: - Sheet Container

struct ReaderControlsContainer<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            Form {
                content()
            }
            .scrollContentBackground(.hidden)
            .background(Color.surfaceGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .adaptiveSheetWidth(680)
        .presentationBackground(Color.surfaceGrouped)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Layout Section (Page Mode + Direction)

struct ReaderLayoutControlsSection: View {
    let supportsImageLayoutControls: Bool
    let supportsDoublePageSpread: Bool
    let pagingMode: ReaderPagingMode
    let spreadMode: ReaderSpreadMode
    let readingDirection: ReaderReadingDirection
    let coverAsSinglePage: Bool
    let onSetPagingMode: (ReaderPagingMode) -> Void
    let onSetSpreadMode: (ReaderSpreadMode) -> Void
    let onSetReadingDirection: (ReaderReadingDirection) -> Void
    let onSetCoverAsSinglePage: (Bool) -> Void

    private var pagingModeBinding: Binding<ReaderPagingMode> {
        Binding(get: { pagingMode }, set: onSetPagingMode)
    }

    private var spreadModeBinding: Binding<ReaderSpreadMode> {
        Binding(get: { spreadMode }, set: onSetSpreadMode)
    }

    private var readingDirectionBinding: Binding<ReaderReadingDirection> {
        Binding(get: { readingDirection }, set: onSetReadingDirection)
    }

    private var coverAsSinglePageBinding: Binding<Bool> {
        Binding(get: { coverAsSinglePage }, set: onSetCoverAsSinglePage)
    }

    private var isVerticalContinuousMode: Bool {
        pagingMode == .verticalContinuous
    }

    var body: some View {
        if supportsImageLayoutControls {
            Section("Layout") {
                Picker("Page Mode", selection: pagingModeBinding) {
                    ForEach(ReaderPagingMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if !isVerticalContinuousMode {
                    if supportsDoublePageSpread {
                        Picker("Spread", selection: spreadModeBinding) {
                            ForEach(ReaderSpreadMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if spreadMode == .doublePage {
                            Toggle("Cover as Single Page", isOn: coverAsSinglePageBinding)
                                .font(AppFont.subheadline())
                        }
                    }

                    Picker("Direction", selection: readingDirectionBinding) {
                        ForEach(ReaderReadingDirection.allCases, id: \.self) { dir in
                            Text(dir.title).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

// MARK: - View Section (Rotation Lock)

struct ReaderViewControlsSection: View {
    let supportsRotationControls: Bool
    let rotation: ReaderRotationAngle
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onResetRotation: () -> Void

    var body: some View {
        if supportsRotationControls {
            Section("View") {
                HStack {
                    Text("Rotation")
                        .font(AppFont.subheadline())

                    Spacer()

                    Text(rotation.title)
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.md) {
                    Button(action: onRotateCounterClockwise) {
                        Label("Left", systemImage: "rotate.left")
                    }

                    Spacer()

                    Button(action: onRotateClockwise) {
                        Label("Right", systemImage: "rotate.right")
                    }

                    Spacer()

                    if rotation != .degrees0 {
                        Button(action: onResetRotation) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Bookmarks Section

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

// MARK: - Navigation Section (kept for external callers)

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
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Quick Scrub")
                                .font(AppFont.subheadline(.medium))

                            Spacer()

                            Text("Page \(normalizedSelectedPageNumber) / \(pageCount)")
                                .font(AppFont.caption().monospacedDigit())
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
                    .padding(.vertical, Spacing.xxs)
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

// MARK: - Reading Status Section

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

// MARK: - Library Actions Section

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

// MARK: - Display Settings Section

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

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Page Layout")
                            .font(AppFont.subheadline(.medium))

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
                                .font(AppFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Reading Direction")
                            .font(AppFont.subheadline(.medium))

                        Picker("Reading Direction", selection: readingDirectionBinding) {
                            ForEach(ReaderReadingDirection.allCases, id: \.self) { readingDirection in
                                Text(readingDirection.title).tag(readingDirection)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, Spacing.xxs)

                    if supportsDoublePageSpread, spreadMode == .doublePage {
                        Toggle("Show Covers as Single Page", isOn: coverAsSinglePageBinding)
                    }
                } else {
                    Text("Vertical mode is optimized for mobile scrolling. Page spread and rotation controls are hidden for consistency.")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Spacing.xxs)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Layout preferences are remembered separately for comics and manga, matching mobile reading habits.")
            }
        }
    }
}

// MARK: - Rotation Section

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

// MARK: - File Info Section

struct ReaderFileInfoSection: View {
    let fileInfo: ReaderControlsFileInfo

    @State private var fileSizeText: String? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Section("File Info") {
            LabeledContent("File Name", value: fileInfo.fileName)

            if let ext = fileInfo.fileExtension, !ext.isEmpty {
                LabeledContent("Format", value: ext.uppercased())
            }

            if let pages = fileInfo.pageCount {
                LabeledContent("Pages", value: "\(pages)")
            }

            if let series = fileInfo.series, !series.isEmpty {
                LabeledContent("Series", value: series)
            }

            if let volume = fileInfo.volume, !volume.isEmpty {
                LabeledContent("Volume", value: volume)
            }

            if let size = fileSizeText {
                LabeledContent("File Size", value: size)
            }

            if let added = fileInfo.addedAt {
                LabeledContent("Added", value: Self.dateFormatter.string(from: added))
            }

            if let opened = fileInfo.lastOpenedAt {
                LabeledContent("Last Opened", value: Self.dateFormatter.string(from: opened))
            }
        }
        .task(id: fileInfo.fileName) {
            fileSizeText = await resolveFileSize()
        }
    }

    private func resolveFileSize() async -> String? {
        guard let url = fileInfo.fileURL else { return nil }
        return await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            guard let bytes = values?.fileSize, bytes > 0 else { return nil }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }.value
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
