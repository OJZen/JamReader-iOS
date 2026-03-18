import SwiftUI
import UIKit

struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let dependencies: AppDependencies

    @StateObject private var viewModel: ComicReaderViewModel
    @State private var isShowingMetadataSheet = false
    @State private var isShowingQuickMetadataSheet = false
    @State private var isShowingOrganizationSheet = false
    @State private var isShowingReaderControls = false
    @State private var isShowingThumbnailBrowser = false
    @State private var isReaderChromeHidden = true
    @State private var pendingReaderAction: ReaderSecondaryAction?
    @State private var readerViewportRefreshToken = 0

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext? = nil,
        onComicUpdated: ((LibraryComic) -> Void)? = nil,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: ComicReaderViewModel(
                descriptor: descriptor,
                comic: comic,
                navigationContext: navigationContext,
                storageManager: dependencies.libraryStorageManager,
                databaseWriter: dependencies.libraryDatabaseWriter,
                documentLoader: dependencies.comicDocumentLoader,
                readerLayoutPreferencesStore: dependencies.readerLayoutPreferencesStore,
                onComicUpdated: onComicUpdated
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Opening Comic")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = viewModel.document {
                readerContent(for: document)
            } else {
                ContentUnavailableView(
                    "Comic Unavailable",
                    systemImage: "book.closed",
                    description: Text("The selected comic could not be opened.")
                )
            }
        }
        .allowsHitTesting(!viewModel.isShowingPageJumpSheet)
        .overlay {
            readerChromeOverlay
                .allowsHitTesting(!viewModel.isShowingPageJumpSheet)
        }
        .overlay {
            if viewModel.isShowingPageJumpSheet {
                ReaderPageJumpOverlay(
                    pageNumberText: $viewModel.pendingPageNumberText,
                    currentPageNumber: viewModel.currentPageNumber ?? 1,
                    pageCount: viewModel.pageCount ?? 1,
                    onCancel: viewModel.dismissPageJump,
                    onJump: viewModel.submitPageJump
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
            viewModel.loadIfNeeded()
        }
        .onAppear {
            updateIdleTimerState()
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.persistCurrentProgress()
        }
        .onChange(of: scenePhase) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: viewModel.document != nil) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
        }
        .sheet(isPresented: $isShowingThumbnailBrowser) {
            if let document = viewModel.document {
                ReaderThumbnailBrowserSheet(
                    document: document,
                    currentPageIndex: viewModel.currentPageIndex
                ) { pageIndex in
                    viewModel.updateCurrentPage(to: pageIndex)
                    isShowingThumbnailBrowser = false
                }
            }
        }
        .sheet(isPresented: $isShowingReaderControls) {
            readerControlsSheet
        }
        .sheet(isPresented: $isShowingQuickMetadataSheet) {
            ReaderQuickMetadataSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            ) { updatedComic in
                viewModel.applyUpdatedComic(updatedComic)
            }
        }
        .sheet(isPresented: $isShowingMetadataSheet) {
            ComicMetadataEditorSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            ) { updatedComic in
                viewModel.applyUpdatedComic(updatedComic)
            }
        }
        .sheet(isPresented: $isShowingOrganizationSheet) {
            ComicOrganizationSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            )
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: isShowingReaderControls) { _, isPresented in
            if isPresented {
                isReaderChromeHidden = false
                return
            }

            guard !isPresented, let pendingReaderAction else {
                return
            }

            self.pendingReaderAction = nil
            switch pendingReaderAction {
            case .quickMetadata:
                isShowingQuickMetadataSheet = true
            case .metadata:
                isShowingMetadataSheet = true
            case .organization:
                isShowingOrganizationSheet = true
            case .thumbnails:
                isShowingThumbnailBrowser = true
            case .pageJump:
                viewModel.presentPageJump()
            }
        }
        .onChange(of: viewModel.isShowingPageJumpSheet) { _, isPresented in
            guard !isPresented else {
                return
            }

            readerViewportRefreshToken &+= 1
        }
    }

    private var supportsDoublePageSpread: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        switch document {
        case .pdf(let pdf):
            ReaderRotationHost(rotation: viewModel.readerLayout.rotation) {
                PDFReaderContainerView(
                    document: pdf.pdfDocument,
                    requestedPageIndex: viewModel.currentPageIndex,
                    rotation: viewModel.readerLayout.rotation,
                    onPageChanged: viewModel.updateCurrentPage(to:),
                    onReaderTap: handleReaderTap
                )
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        case .imageSequence(let imageSequence):
            if viewModel.effectiveReaderLayout.pagingMode == .verticalContinuous {
                VerticalImageSequenceReaderContainerView(
                    document: imageSequence,
                    initialPageIndex: viewModel.currentPageIndex,
                    layout: viewModel.effectiveReaderLayout,
                    onPageChanged: viewModel.updateCurrentPage(to:),
                    onReaderTap: handleReaderTap
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            } else {
                ImageSequenceReaderContainerView(
                    document: imageSequence,
                    initialPageIndex: viewModel.currentPageIndex,
                    layout: viewModel.effectiveReaderLayout,
                    viewportRefreshToken: readerViewportRefreshToken,
                    onPageChanged: viewModel.updateCurrentPage(to:),
                    onReaderTap: handleReaderTap
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            }
        case .unsupported(let document):
            ContentUnavailableView(
                "Reader Not Ready",
                systemImage: "shippingbox",
                description: Text("`. \(document.fileExtension)` files are already indexed by the library, but archive page extraction is still being ported.\n\n\(document.reason)")
            )
        }
    }

    private var readerControlsSheet: some View {
        ReaderControlsSheet(
            pageIndicatorText: viewModel.pageIndicatorText,
            currentPageNumber: viewModel.currentPageNumber,
            pageCount: viewModel.pageCount,
            currentPageIsBookmarked: viewModel.currentPageIsBookmarked,
            bookmarkItems: viewModel.bookmarkItems,
            isFavorite: viewModel.isFavorite,
            isRead: viewModel.comic.read,
            rating: viewModel.rating,
            supportsImageLayoutControls: viewModel.supportsImageLayoutControls,
            supportsDoublePageSpread: supportsDoublePageSpread,
            supportsRotationControls: viewModel.supportsRotationControls,
            fitMode: viewModel.effectiveReaderLayout.fitMode,
            pagingMode: viewModel.effectiveReaderLayout.pagingMode,
            spreadMode: viewModel.effectiveReaderLayout.spreadMode,
            readingDirection: viewModel.effectiveReaderLayout.readingDirection,
            coverAsSinglePage: viewModel.effectiveReaderLayout.coverAsSinglePage,
            rotation: viewModel.readerLayout.rotation,
            onDone: { isShowingReaderControls = false },
            onToggleFavorite: viewModel.toggleFavoriteStatus,
            onToggleReadStatus: viewModel.toggleReadStatus,
            onOpenQuickMetadata: {
                pendingReaderAction = .quickMetadata
                isShowingReaderControls = false
            },
            onOpenMetadata: {
                pendingReaderAction = .metadata
                isShowingReaderControls = false
            },
            onOpenOrganization: {
                pendingReaderAction = .organization
                isShowingReaderControls = false
            },
            onOpenThumbnails: {
                pendingReaderAction = .thumbnails
                isShowingReaderControls = false
            },
            onOpenPageJump: {
                pendingReaderAction = .pageJump
                isShowingReaderControls = false
            },
            onToggleBookmark: viewModel.toggleBookmarkForCurrentPage,
            onSetRating: viewModel.setRating,
            onGoToBookmark: { pageIndex in
                viewModel.goToBookmark(pageIndex: pageIndex)
                isShowingReaderControls = false
            },
            onGoToPageNumber: { pageNumber in
                viewModel.goToPage(number: pageNumber)
                isShowingReaderControls = false
            },
            onSetFitMode: viewModel.setFitMode,
            onSetPagingMode: viewModel.setPagingMode,
            onSetSpreadMode: viewModel.setSpreadMode,
            onSetReadingDirection: viewModel.setReadingDirection,
            onSetCoverAsSinglePage: viewModel.setCoverAsSinglePage,
            onRotateCounterClockwise: viewModel.rotateCounterClockwise,
            onRotateClockwise: viewModel.rotateClockwise,
            onResetRotation: viewModel.resetRotation
        )
    }

    @ViewBuilder
    private var readerChromeOverlay: some View {
        ReaderChromeOverlay(isHidden: isReaderChromeHidden) {
            ReaderChromeBar {
                HStack(spacing: 12) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "chevron.backward")
                            .font(.headline.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.navigationTitle)
                            .font(.headline)
                            .lineLimit(1)

                        if let contextPositionText = viewModel.readerContextPositionText {
                            Text(contextPositionText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        } bottomBar: {
            if viewModel.pageIndicatorText != nil || viewModel.hasReaderNavigationContext {
                ReaderChromeBar {
                    HStack(spacing: 16) {
                        Button {
                            isReaderChromeHidden = false
                            isShowingReaderControls = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.headline)
                        }
                        .disabled(viewModel.document == nil)

                        Spacer(minLength: 0)

                        Button(action: viewModel.openPreviousComic) {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                        }
                        .disabled(!viewModel.canOpenPreviousComic)

                        if let pageIndicatorText = viewModel.pageIndicatorText {
                            ReaderChromePill {
                                Text(pageIndicatorText)
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(action: viewModel.openNextComic) {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                        }
                        .disabled(!viewModel.canOpenNextComic)
                    }
                }
            }
        }
    }

    private func toggleReaderChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isReaderChromeHidden.toggle()
        }
    }

    private func hideReaderChrome() {
        guard !isReaderChromeHidden else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isReaderChromeHidden = true
        }
    }

    private func handleReaderTap(_ tapRegion: ReaderTapRegion) {
        switch tapRegion {
        case .center:
            toggleReaderChrome()
        case .leading:
            if !isReaderChromeHidden {
                hideReaderChrome()
            } else if viewModel.canOpenPreviousComic {
                viewModel.openPreviousComic()
            }
        case .trailing:
            if !isReaderChromeHidden {
                hideReaderChrome()
            } else if viewModel.canOpenNextComic {
                viewModel.openNextComic()
            }
        }
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && viewModel.document != nil
    }
}

private enum ReaderSecondaryAction {
    case quickMetadata
    case metadata
    case organization
    case thumbnails
    case pageJump
}

private struct ReaderRotationHost<Content: View>: View {
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

private struct ReaderPageJumpSheet: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isFocused: Bool

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...pageCount).contains(pageNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("Page number", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .focused($isFocused)

                    Text("Current page: \(currentPageNumber)")
                        .foregroundStyle(.secondary)

                    Text("Valid range: 1-\(pageCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Go to Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump", action: onJump)
                        .disabled(!isValidPageNumber)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }
}

private struct ReaderControlsSheet: View {
    let pageIndicatorText: String?
    let currentPageNumber: Int?
    let pageCount: Int?
    let currentPageIsBookmarked: Bool
    let bookmarkItems: [ReaderBookmarkItem]
    let isFavorite: Bool
    let isRead: Bool
    let rating: Int
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
    let onToggleFavorite: () -> Void
    let onToggleReadStatus: () -> Void
    let onOpenQuickMetadata: () -> Void
    let onOpenMetadata: () -> Void
    let onOpenOrganization: () -> Void
    let onOpenThumbnails: () -> Void
    let onOpenPageJump: () -> Void
    let onToggleBookmark: () -> Void
    let onSetRating: (Int) -> Void
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

    @State private var selectedPageNumber: Double

    init(
        pageIndicatorText: String?,
        currentPageNumber: Int?,
        pageCount: Int?,
        currentPageIsBookmarked: Bool,
        bookmarkItems: [ReaderBookmarkItem],
        isFavorite: Bool,
        isRead: Bool,
        rating: Int,
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
        onToggleFavorite: @escaping () -> Void,
        onToggleReadStatus: @escaping () -> Void,
        onOpenQuickMetadata: @escaping () -> Void,
        onOpenMetadata: @escaping () -> Void,
        onOpenOrganization: @escaping () -> Void,
        onOpenThumbnails: @escaping () -> Void,
        onOpenPageJump: @escaping () -> Void,
        onToggleBookmark: @escaping () -> Void,
        onSetRating: @escaping (Int) -> Void,
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
        self.isFavorite = isFavorite
        self.isRead = isRead
        self.rating = rating
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
        self.onToggleFavorite = onToggleFavorite
        self.onToggleReadStatus = onToggleReadStatus
        self.onOpenQuickMetadata = onOpenQuickMetadata
        self.onOpenMetadata = onOpenMetadata
        self.onOpenOrganization = onOpenOrganization
        self.onOpenThumbnails = onOpenThumbnails
        self.onOpenPageJump = onOpenPageJump
        self.onToggleBookmark = onToggleBookmark
        self.onSetRating = onSetRating
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
        _selectedPageNumber = State(initialValue: Double(currentPageNumber ?? 1))
    }

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

    private var ratingBinding: Binding<Int> {
        Binding(
            get: { rating },
            set: onSetRating
        )
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

    private var isVerticalContinuousMode: Bool {
        pagingMode == .verticalContinuous
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Navigate") {
                    if let pageIndicatorText {
                        LabeledContent("Current Page", value: pageIndicatorText)

                        Button(action: onOpenThumbnails) {
                            Label("Browse Thumbnails", systemImage: "square.grid.3x2")
                        }

                        Button(action: onOpenPageJump) {
                            Label("Go to Page", systemImage: "number.square")
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
                }

                Section("Reading Status") {
                    Button(action: onToggleFavorite) {
                        Label(
                            isFavorite ? "Remove Favorite" : "Add Favorite",
                            systemImage: isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button(action: onToggleReadStatus) {
                        Label(
                            isRead ? "Mark Unread" : "Mark Read",
                            systemImage: isRead ? "arrow.uturn.backward.circle" : "checkmark.circle"
                        )
                    }

                    Button(action: onToggleBookmark) {
                        Label(
                            currentPageIsBookmarked ? "Remove Current Bookmark" : "Bookmark Current Page",
                            systemImage: currentPageIsBookmarked ? "bookmark.slash" : "bookmark"
                        )
                    }

                    Picker("Rating", selection: ratingBinding) {
                        Text("Unrated").tag(0)
                        ForEach(1...5, id: \.self) { value in
                            Text(value == 1 ? "1 Star" : "\(value) Stars").tag(value)
                        }
                    }
                }

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

                Section("Library") {
                    Button(action: onOpenQuickMetadata) {
                        Label("Quick Edit Metadata", systemImage: "pencil")
                    }

                    Button(action: onOpenMetadata) {
                        Label("Edit Metadata", systemImage: "square.and.pencil")
                    }

                    Button(action: onOpenOrganization) {
                        Label("Tags and Reading Lists", systemImage: "tag")
                    }
                }

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
            .navigationTitle("Reader Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: currentPageNumber) { _, newValue in
            if let newValue {
                selectedPageNumber = Double(newValue)
            }
        }
    }
}
