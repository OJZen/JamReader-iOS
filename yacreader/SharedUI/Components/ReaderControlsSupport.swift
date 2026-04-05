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
    /// Used to render a compact cover preview when the reader already has the document loaded.
    let coverDocument: ComicDocument?
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
    @State private var selectedDetent: PresentationDetent = .large

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
        .presentationDetents([.medium, .large], selection: $selectedDetent)
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
    let onOpenThumbnails: () -> Void

    init(
        pageIndicatorText _: String?,
        currentPageNumber _: Int?,
        pageCount _: Int?,
        onOpenThumbnails: @escaping () -> Void,
        onGoToPageNumber _: @escaping (Int) -> Void
    ) {
        self.onOpenThumbnails = onOpenThumbnails
    }

    var body: some View {
        Section("Pages") {
            Button(action: onOpenThumbnails) {
                Label("Browse Thumbnails", systemImage: "square.grid.3x2")
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
                    currentPageIsBookmarked ? "Remove Bookmark" : "Add Bookmark",
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

                    if supportsDoublePageSpread {
                        Picker("Page Layout", selection: spreadModeBinding) {
                            ForEach(ReaderSpreadMode.allCases, id: \.self) { spreadMode in
                                Text(spreadMode.title).tag(spreadMode)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        LabeledContent("Page Layout", value: ReaderSpreadMode.singlePage.title)
                    }

                    Picker("Reading Direction", selection: readingDirectionBinding) {
                        ForEach(ReaderReadingDirection.allCases, id: \.self) { readingDirection in
                            Text(readingDirection.title).tag(readingDirection)
                        }
                    }
                    .pickerStyle(.segmented)

                    if supportsDoublePageSpread, spreadMode == .doublePage {
                        Toggle("Show Covers as Single Page", isOn: coverAsSinglePageBinding)
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                if isVerticalContinuousMode {
                    Text("Page layout and rotation are unavailable in vertical scroll.")
                }
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
                LabeledContent("Current", value: rotation.title)

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
        Section {
            HStack(alignment: .top, spacing: 14) {
                coverPreview

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileInfo.fileName)
                            .font(AppFont.headline(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let subtitle = subtitleText {
                            Text(subtitle)
                                .font(AppFont.footnote())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    if !summaryChips.isEmpty {
                        FlexibleChipWrap(items: summaryChips)
                    }

                    if !detailRows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(detailRows, id: \.label) { row in
                                LabeledContent(row.label, value: row.value)
                                    .font(AppFont.caption())
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }
        .task(id: fileInfo.fileName) {
            fileSizeText = await resolveFileSize()
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let coverDocument = fileInfo.coverDocument {
            ReaderPageThumbnailView(
                document: coverDocument,
                pageIndex: 0,
                width: 84,
                height: 118,
                cornerRadius: 14,
                style: .browser
            )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 84, height: 118)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var subtitleText: String? {
        let components: [String] = [fileInfo.series, volumeText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        guard !components.isEmpty else {
            return nil
        }

        return components.joined(separator: " · ")
    }

    private var volumeText: String? {
        guard let volume = fileInfo.volume, !volume.isEmpty else {
            return nil
        }

        return "Vol. \(volume)"
    }

    private var summaryChips: [String] {
        var chips: [String] = []

        if let ext = fileInfo.fileExtension, !ext.isEmpty {
            chips.append(ext.uppercased())
        }

        if let pages = fileInfo.pageCount {
            chips.append("\(pages) pages")
        }

        if let fileSizeText, !fileSizeText.isEmpty {
            chips.append(fileSizeText)
        }

        return chips
    }

    private var detailRows: [ReaderFileInfoRow] {
        var rows: [ReaderFileInfoRow] = []

        if let added = fileInfo.addedAt {
            rows.append(.init(label: "Added", value: Self.dateFormatter.string(from: added)))
        }

        if let opened = fileInfo.lastOpenedAt {
            rows.append(.init(label: "Last Opened", value: Self.dateFormatter.string(from: opened)))
        }

        return rows
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

private struct ReaderFileInfoRow {
    let label: String
    let value: String
}

private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    chip(item)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(chunked(items, size: 2), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { item in
                            chip(item)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        stride(from: 0, to: items.count, by: size).map { index in
            Array(items[index..<min(index + size, items.count)])
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
