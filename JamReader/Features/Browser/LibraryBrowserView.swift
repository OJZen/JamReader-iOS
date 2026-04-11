import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryBrowserView: View {
    private enum LayoutMetrics {
        static let horizontalInset: CGFloat = Spacing.sm
        static let rowAccessoryReservedWidth: CGFloat = 36
        static let compactGridMinWidth: CGFloat = 165
        static let compactGridMaxWidth: CGFloat = 220
        static let regularGridMinWidth: CGFloat = 240
        static let regularGridMaxWidth: CGFloat = 320
        static let wideGridMinContainerWidth: CGFloat = 860
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @AppStorage("libraryRecentWindowDays") private var recentWindowRawValue = LibraryRecentWindowOption.defaultOption.rawValue
    @StateObject private var viewModel: LibraryBrowserViewModel
    @State private var comicSortMode: LibraryComicSortMode
    @State private var preferredDisplayMode: LibraryBrowserDisplayMode
    @State private var displayMode: LibraryBrowserDisplayMode
    @State private var hasConfiguredPreferredDisplayMode = false
    @State private var folderSearchQuery = ""
    @State private var comicFilter: LibraryComicQuickFilter = .all
    @State private var editingComic: LibraryComic?
    @State private var organizingComic: LibraryComic?
    @State private var quickActionsComic: LibraryComic?
    @State private var pendingQuickAction: PendingComicQuickAction?
    @State private var removingComic: LibraryComic?
    @State private var isSelectionMode = false
    @State private var selectedComicIDs = Set<Int64>()
    @State private var isShowingBatchMetadataSheet = false
    @State private var isShowingComicInfoImportSheet = false
    @State private var isShowingBatchOrganizationSheet = false
    @State private var isShowingSelectionActionsSheet = false
    @State private var isShowingComicFileImporter = false
    @State private var presentedComic: LibraryComicPresentation?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?
    @State private var containerWidth: CGFloat = 0

    init(
        descriptor: LibraryDescriptor,
        folderID: Int64 = 1,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _comicSortMode = State(initialValue: Self.loadStoredSortMode())
        let storedDisplayMode = Self.loadStoredDisplayMode()
        _preferredDisplayMode = State(initialValue: storedDisplayMode)
        _displayMode = State(initialValue: storedDisplayMode)
        _viewModel = StateObject(
            wrappedValue: LibraryBrowserViewModel(
                descriptor: descriptor,
                folderID: folderID,
                storageManager: dependencies.libraryStorageManager,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                databaseBootstrapper: dependencies.libraryDatabaseBootstrapper,
                libraryScanner: dependencies.libraryScanner,
                maintenanceStatusStore: dependencies.libraryMaintenanceStatusStore,
                coverLocator: dependencies.libraryCoverLocator,
                comicInfoImportService: dependencies.comicInfoImportService,
                importedComicsImportService: dependencies.importedComicsImportService,
                comicRemovalService: dependencies.libraryComicRemovalService
            )
        )
    }

    var body: some View {
        composedBody
    }

    private var showsPersistentComicActions: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularInlineActionMinWidth)
    }

    private var comicAccessoryReservedWidth: CGFloat {
        showsPersistentComicActions ? LayoutMetrics.rowAccessoryReservedWidth : 0
    }

    @ViewBuilder
    private var rootContent: some View {
        Group {
            if viewModel.hasActiveSearch {
                searchResultsView
            } else if let content = viewModel.content {
                contentView(content)
            } else if viewModel.isLoading || viewModel.isInitializingLibrary || viewModel.isRefreshingLibrary {
                VStack(spacing: Spacing.sm) {
                    ProgressView(progressMessage)

                    if let scanProgress = viewModel.scanProgress {
                        Text(scanProgress.detailLine)
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Spacing.lg) {
                    EmptyStateView(
                        systemImage: viewModel.canInitializeLibrary ? "books.vertical.circle" : "externaldrive.badge.exclamationmark",
                        title: viewModel.canInitializeLibrary ? "Library Not Initialized" : "Library Unavailable",
                        description: viewModel.emptyStateMessage ?? "The selected library could not be loaded."
                    )

                    if viewModel.canInitializeLibrary {
                        Button {
                            viewModel.initializeLibrary()
                        } label: {
                            Label("Initialize Library", systemImage: "sparkles.rectangle.stack")
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Builds this library's local index, adds the root folder, and scans supported comic files.")
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var composedBody: some View {
        rootContent
        .readContainerWidth(into: $containerWidth)
        .safeAreaInset(edge: .top) {
            if let scanCompletion = viewModel.scanCompletion, viewModel.scanProgress == nil {
                ScanCompletionBanner(
                    completion: scanCompletion,
                    dismiss: viewModel.dismissScanCompletion
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, Spacing.xs)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.scanCompletion?.id)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canSelectComics {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectionMode ? "Done" : "Select") {
                        if isSelectionMode {
                            endSelectionMode()
                        } else {
                            isSelectionMode = true
                        }
                    }
                }
            }

            if isSelectionMode && canSelectComics {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(areAllVisibleComicsSelected ? "Clear" : "Select All") {
                        toggleSelectAllVisibleComics()
                    }
                }
            }

            if !isSelectionMode {
                if usesCondensedTopBarActions {
                    if hasCondensedTopBarActions {
                        ToolbarItem(placement: .topBarTrailing) {
                            condensedTopBarActionsMenu
                        }
                    }
                } else {
                    if canImportComicInfo {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingComicInfoImportSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .accessibilityLabel("Import ComicInfo")
                        }
                    }

                    if canImportComicFiles {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isShowingComicFileImporter = true
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .accessibilityLabel("Import Comic Files")
                        }
                    }

                    if canAdjustRecentWindow {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                recentWindowMenuContent
                            } label: {
                                Image(systemName: "calendar.badge.clock")
                            }
                            .accessibilityLabel("Recent Window")
                        }
                    }

                    if canMaintainCurrentContext {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                currentContextMaintenanceMenuContent
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .accessibilityLabel("Maintenance")
                        }
                    }

                    if canAdjustDisplayMode {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                displayModeMenuContent
                            } label: {
                                Image(systemName: displayMode.systemImageName)
                            }
                            .accessibilityLabel("Display Mode")
                        }
                    }

                    if canSortCurrentComics {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                sortModeMenuContent
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                            }
                            .accessibilityLabel("Sort")
                        }
                    }
                }
            }

            if isSelectionMode {
                ToolbarItem(placement: .bottomBar) {
                    Text(selectionSummaryText)
                        .font(AppFont.footnote(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isShowingSelectionActionsSheet = true
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(!hasSelectedComics)
                }
            }
        }
        .searchable(text: $viewModel.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search entire library")
        .task {
            viewModel.setRecentDays(recentWindowOption.dayCount)
            viewModel.loadIfNeeded()
        }
        .onAppear {
            configurePreferredDisplayModeIfNeeded()
            viewModel.setRecentDays(recentWindowOption.dayCount)
            viewModel.refreshIfLoaded()
            if let currentFolderID = viewModel.content?.folder.id {
                Self.persistLastOpenedFolderID(currentFolderID, for: viewModel.descriptor.id)
            }
        }
        .onChange(of: viewModel.content?.folder.id) { _, newFolderID in
            guard let newFolderID else {
                return
            }

            Self.persistLastOpenedFolderID(newFolderID, for: viewModel.descriptor.id)
        }
        .onChange(of: viewModel.hasActiveSearch) { _, hasActiveSearch in
            if hasActiveSearch {
                endSelectionMode()
            }
        }
        .onChange(of: comicFilter) { _, _ in
            if isSelectionMode {
                endSelectionMode()
            }
        }
        .onChange(of: folderSearchQuery) { _, _ in
            if isSelectionMode {
                endSelectionMode()
            }
        }
        .onChange(of: visibleComicIDs) { _, visibleComicIDs in
            let visibleIDs = Set(visibleComicIDs)
            selectedComicIDs = selectedComicIDs.intersection(visibleIDs)

            if isSelectionMode && visibleIDs.isEmpty {
                endSelectionMode()
            }
        }
        .onChange(of: supportsGridDisplay) { _, _ in
            adaptDisplayModeForCurrentWidth()
        }
        .onChange(of: recentWindowRawValue) { _, _ in
            viewModel.setRecentDays(recentWindowOption.dayCount)
        }
        .refreshable {
            if viewModel.canRefreshCurrentFolder {
                viewModel.refreshCurrentFolder()
            } else if viewModel.canRefreshLibrary {
                viewModel.refreshLibrary()
            } else {
                viewModel.load()
            }
        }
        .sheet(item: $editingComic) { comic in
            ComicMetadataEditorSheet(
                descriptor: viewModel.descriptor,
                comic: comic,
                dependencies: dependencies
            ) { updatedComic in
                viewModel.applyUpdatedComic(updatedComic)
            }
        }
        .sheet(item: $organizingComic, onDismiss: viewModel.load) { comic in
            ComicOrganizationSheet(
                descriptor: viewModel.descriptor,
                comic: comic,
                dependencies: dependencies
            )
        }
        .sheet(item: $quickActionsComic) { comic in
            LibraryComicQuickActionsSheet(
                comic: comic,
                onDone: { quickActionsComic = nil },
                onEditMetadata: {
                    queueQuickAction(.edit(comic))
                },
                onToggleFavorite: {
                    viewModel.toggleFavorite(for: comic)
                    quickActionsComic = nil
                },
                onToggleReadStatus: {
                    viewModel.toggleReadStatus(for: comic)
                    quickActionsComic = nil
                },
                onSetRating: { rating in
                    viewModel.setRating(rating, for: comic)
                },
                onOpenOrganization: {
                    queueQuickAction(.organize(comic))
                },
                onRemoveFromLibrary: viewModel.canRemoveComics ? {
                    queueQuickAction(.remove(comic))
                } : nil
            )
        }
        .sheet(isPresented: $isShowingBatchMetadataSheet) {
            BatchComicMetadataSheet(
                descriptor: viewModel.descriptor,
                comicIDs: Array(selectedComicIDs),
                dependencies: dependencies
            ) {
                endSelectionMode()
                viewModel.load()
            }
        }
        .sheet(isPresented: $isShowingComicInfoImportSheet) {
            BatchComicInfoImportSheet(
                descriptor: viewModel.descriptor,
                comics: comicInfoImportTargetComics,
                scope: comicInfoImportScope,
                dependencies: dependencies
            ) { result in
                viewModel.load()
                if isSelectionMode {
                    endSelectionMode()
                }
                viewModel.alert = AppAlertState(
                    title: result.alertTitle,
                    message: result.alertMessage
                )
            }
        }
        .sheet(isPresented: $isShowingBatchOrganizationSheet) {
            BatchComicOrganizationSheet(
                descriptor: viewModel.descriptor,
                comicIDs: Array(selectedComicIDs),
                dependencies: dependencies
            ) {
                endSelectionMode()
                viewModel.load()
            }
        }
        .sheet(isPresented: $isShowingSelectionActionsSheet) {
            LibrarySelectionActionsSheet(
                selectionCount: selectedComicIDs.count,
                onEditMetadata: {
                    isShowingBatchMetadataSheet = true
                },
                onImportComicInfo: {
                    isShowingComicInfoImportSheet = true
                },
                onOpenOrganization: {
                    isShowingBatchOrganizationSheet = true
                },
                onMarkRead: {
                    performBatchReadAction(true)
                },
                onMarkUnread: {
                    performBatchReadAction(false)
                },
                onAddFavorite: {
                    performBatchFavoriteAction(true)
                },
                onRemoveFavorite: {
                    performBatchFavoriteAction(false)
                }
            )
        }
        .fileImporter(
            isPresented: $isShowingComicFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importComicFiles(from: urls)
            case .failure(let error):
                viewModel.alert = AppAlertState(
                    title: "Import Failed",
                    message: error.userFacingMessage
                )
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(
            HeroReaderPresenter(
                item: $presentedComic,
                sourceFrame: heroSourceFrame,
                previewImage: heroPreviewImage,
                onDismiss: {
                    heroSourceFrame = .zero
                    heroPreviewImage = nil
                }
            ) { presentation in
                ComicReaderView(
                    descriptor: viewModel.descriptor,
                    comic: presentation.comic,
                    navigationContext: presentation.navigationContext,
                    onComicUpdated: handleReaderComicUpdate,
                    dependencies: dependencies
                )
            }
        )
        .onChange(of: quickActionsComic) { _, newValue in
            guard newValue == nil, let pendingQuickAction else {
                return
            }

            self.pendingQuickAction = nil
            switch pendingQuickAction {
            case .edit(let comic):
                editingComic = comic
            case .organize(let comic):
                organizingComic = comic
            case .remove(let comic):
                removingComic = comic
            }
        }
        .confirmationDialog(
            "Delete Comic",
            isPresented: removingComicConfirmationBinding,
            titleVisibility: .visible,
            presenting: removingComic
        ) { comic in
            Button("Delete Comic", role: .destructive) {
                if viewModel.removeComic(comic) {
                    removingComic = nil
                }
            }
        } message: { comic in
            Text("Deletes \"\(comic.displayTitle)\" from this library and removes the local file.")
        }
    }

    private var supportsGridDisplay: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularInlineActionMinWidth)
    }

    private var removingComicConfirmationBinding: Binding<Bool> {
        Binding(
            get: { removingComic != nil },
            set: { isPresented in
                if !isPresented {
                    removingComic = nil
                }
            }
        )
    }

    private var usesCondensedTopBarActions: Bool {
        !supportsGridDisplay
    }

    private var recentWindowOption: LibraryRecentWindowOption {
        LibraryRecentWindowOption(rawValue: recentWindowRawValue) ?? .defaultOption
    }

    private var canAdjustRecentWindow: Bool {
        viewModel.content?.folder.isRoot == true && !viewModel.hasActiveSearch
    }

    private var canImportComicFiles: Bool {
        viewModel.canImportComicFiles && !viewModel.hasActiveSearch
    }

    private var canMaintainCurrentContext: Bool {
        viewModel.canScanFromCurrentContext && !viewModel.hasActiveSearch
    }

    private var canAdjustDisplayMode: Bool {
        supportsGridDisplay && !viewModel.hasActiveSearch
    }

    private var hasCondensedTopBarActions: Bool {
        canImportComicInfo
            || canImportComicFiles
            || canAdjustRecentWindow
            || canMaintainCurrentContext
            || canAdjustDisplayMode
            || canSortCurrentComics
    }

    private var canSelectComics: Bool {
        !viewModel.hasActiveSearch && !visibleComics.isEmpty
    }

    private var canSortCurrentComics: Bool {
        !visibleComics.isEmpty
    }

    private var hasSelectedComics: Bool {
        !selectedComicIDs.isEmpty
    }

    private var visibleComics: [LibraryComic] {
        if viewModel.hasActiveSearch {
            return filteredSortedComics(viewModel.searchResults?.comics ?? [])
        }

        return filteredSortedComics(
            viewModel.content?.comics ?? [],
            localQuery: folderSearchQuery
        )
    }

    private var selectedComics: [LibraryComic] {
        visibleComics.filter { selectedComicIDs.contains($0.id) }
    }

    private var comicInfoImportTargetComics: [LibraryComic] {
        isSelectionMode ? selectedComics : visibleComics
    }

    private var comicInfoImportScope: BatchComicInfoImportScope {
        isSelectionMode ? .selected : .visible
    }

    private var canImportComicInfo: Bool {
        !comicInfoImportTargetComics.isEmpty
    }

    private var visibleComicIDs: [Int64] {
        visibleComics.map(\.id)
    }

    private var areAllVisibleComicsSelected: Bool {
        let visibleIDs = Set(visibleComicIDs)
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedComicIDs)
    }

    private var selectionSummaryText: String {
        let count = selectedComicIDs.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private var progressMessage: String {
        if let scanProgress = viewModel.scanProgress {
            return scanProgress.title
        }

        if viewModel.isInitializingLibrary {
            return "Initializing Library"
        }

        if viewModel.isRefreshingLibrary {
            return "Refreshing Library"
        }

        return "Opening Library"
    }

    private func handleReaderComicUpdate(_ updatedComic: LibraryComic) {
        viewModel.applyUpdatedComic(updatedComic)
    }

    @ViewBuilder
    private var condensedTopBarActionsMenu: some View {
        Menu {
            if canImportComicInfo {
                Button {
                    isShowingComicInfoImportSheet = true
                } label: {
                    Label("Import ComicInfo", systemImage: "square.and.arrow.down")
                }
            }

            if canImportComicFiles {
                Button {
                    isShowingComicFileImporter = true
                } label: {
                    Label("Import Comic Files", systemImage: "square.and.arrow.down")
                }
            }

            if (canImportComicInfo || canImportComicFiles)
                && (canAdjustRecentWindow || canMaintainCurrentContext || canAdjustDisplayMode || canSortCurrentComics) {
                Divider()
            }

            if canAdjustRecentWindow {
                Menu {
                    recentWindowMenuContent
                } label: {
                    Label("Recent Window", systemImage: "calendar.badge.clock")
                }
            }

            if canMaintainCurrentContext {
                Menu {
                    currentContextMaintenanceMenuContent
                } label: {
                    Label("Refresh & Scan", systemImage: "arrow.clockwise.circle")
                }
            }

            if canAdjustDisplayMode {
                Menu {
                    displayModeMenuContent
                } label: {
                    Label("Display Mode", systemImage: displayMode.systemImageName)
                }
            }

            if canSortCurrentComics {
                Menu {
                    sortModeMenuContent
                } label: {
                    Label("Sort Comics", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More Library Actions")
    }

    @ViewBuilder
    private var recentWindowMenuContent: some View {
        ForEach(LibraryRecentWindowOption.allCases) { option in
            Button {
                recentWindowRawValue = option.rawValue
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(option.title)
                        Text(option.subtitle)
                            .font(AppFont.caption())
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    if recentWindowOption == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentContextMaintenanceMenuContent: some View {
        if viewModel.canRefreshLibrary {
            Button {
                viewModel.refreshLibrary()
            } label: {
                Label("Refresh Library", systemImage: "arrow.clockwise")
            }
        }

        if viewModel.canRefreshCurrentFolder {
            Button {
                viewModel.refreshCurrentFolder()
            } label: {
                Label("Refresh Current Folder", systemImage: "folder.badge.plus")
            }
        }

        if viewModel.canImportLibraryComicInfo || viewModel.canImportCurrentFolderComicInfo {
            Divider()
        }

        if viewModel.canImportLibraryComicInfo {
            Menu {
                comicInfoImportPolicyActions { policy in
                    viewModel.importLibraryComicInfo(policy: policy)
                }
            } label: {
                Label("Import Library ComicInfo", systemImage: "square.and.arrow.down")
            }
        }

        if viewModel.canImportCurrentFolderComicInfo {
            Menu {
                comicInfoImportPolicyActions { policy in
                    viewModel.importCurrentFolderComicInfo(policy: policy)
                }
            } label: {
                Label("Import Current Folder ComicInfo", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private var displayModeMenuContent: some View {
        ForEach(LibraryBrowserDisplayMode.allCases) { mode in
            Button {
                applyDisplayMode(mode)
            } label: {
                HStack {
                    Text(mode.title)
                    Spacer()
                    if displayMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sortModeMenuContent: some View {
        ForEach(LibraryComicSortMode.allCases) { mode in
            Button {
                applySortMode(mode)
            } label: {
                HStack {
                    Text(mode.title)
                    Spacer()
                    if comicSortMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private func applySortMode(_ mode: LibraryComicSortMode) {
        comicSortMode = mode
        Self.persistSortMode(mode)
    }

    private static func sortModeStorageKey() -> String {
        "libraryBrowserSortMode"
    }

    private static func loadStoredSortMode() -> LibraryComicSortMode {
        let defaults = UserDefaults.standard
        let scopedKey = sortModeStorageKey()

        if let scopedRawValue = defaults.string(forKey: scopedKey),
           let scopedMode = LibraryComicSortMode(rawValue: scopedRawValue) {
            return scopedMode
        }

        if let legacyRawValue = defaults.string(forKey: "libraryComicSortMode"),
           let legacyMode = LibraryComicSortMode(rawValue: legacyRawValue) {
            defaults.set(legacyMode.rawValue, forKey: scopedKey)
            return legacyMode
        }

        return .sourceOrder
    }

    private static func persistSortMode(_ mode: LibraryComicSortMode) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: sortModeStorageKey()
        )
    }

    static func lastOpenedFolderID(for libraryID: UUID) -> Int64 {
        let value = UserDefaults.standard.object(
            forKey: lastOpenedFolderStorageKey(for: libraryID)
        ) as? NSNumber
        return max(1, value?.int64Value ?? 1)
    }

    static func persistLastOpenedFolderID(_ folderID: Int64, for libraryID: UUID) {
        UserDefaults.standard.set(
            max(1, folderID),
            forKey: lastOpenedFolderStorageKey(for: libraryID)
        )
    }

    private static func lastOpenedFolderStorageKey(for libraryID: UUID) -> String {
        "libraryBrowser.lastOpenedFolderID.\(libraryID.uuidString)"
    }

    private func sortedComics(_ comics: [LibraryComic]) -> [LibraryComic] {
        comics.sorted(using: comicSortMode)
    }

    private var trimmedFolderSearchQuery: String {
        folderSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveLocalFolderSearch: Bool {
        !trimmedFolderSearchQuery.isEmpty
    }

    private var hasActiveLocalFolderFilters: Bool {
        hasActiveLocalFolderSearch || comicFilter != .all
    }

    private var comicFilterChipBinding: Binding<LibraryComicQuickFilter?> {
        Binding(
            get: { comicFilter == .all ? nil : comicFilter },
            set: { comicFilter = $0 ?? .all }
        )
    }

    private func filteredSubfolders(
        _ folders: [LibraryFolder],
        localQuery: String? = nil
    ) -> [LibraryFolder] {
        let trimmedQuery = (localQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return folders
        }

        return folders.filter { $0.matchesSearchQuery(trimmedQuery) }
    }

    private func filteredSortedComics(
        _ comics: [LibraryComic],
        localQuery: String? = nil
    ) -> [LibraryComic] {
        let trimmedQuery = (localQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return sortedComics(comics).filter { comic in
            comicFilter.matches(comic) && (trimmedQuery.isEmpty || comic.matchesSearchQuery(trimmedQuery))
        }
    }

    @ViewBuilder
    private func comicInfoImportPolicyActions(
        _ action: @escaping (ComicInfoImportPolicy) -> Void
    ) -> some View {
        ForEach(ComicInfoImportPolicy.allCases) { policy in
            Button {
                action(policy)
            } label: {
                Text(policy.title)
            }
        }
    }

    private func contentView(_ content: LibraryFolderContent) -> some View {
        Group {
            if supportsGridDisplay && displayMode == .grid {
                gridContentView(content)
            } else {
                listContentView(content)
            }
        }
    }

    private func listContentView(_ content: LibraryFolderContent) -> some View {
        let displayedSubfolders = filteredSubfolders(content.subfolders, localQuery: folderSearchQuery)
        let displayedComics = filteredSortedComics(content.comics, localQuery: folderSearchQuery)

        return List {
            if hasLibraryStatus {
                libraryStatusListSection
            }

            if showsLocalFolderControls(for: content) {
                localControlsListSection(content)
            }

            if content.folder.isRoot && !hasActiveLocalFolderSearch {
                continueReadingListSection
                browseByListSection
            }

            if content.subfolders.isEmpty, content.comics.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "Empty Folder",
                        description: "This part of the library does not contain subfolders or comics yet."
                    )
                    .padding(.vertical, Spacing.xl)
                }
            } else if displayedSubfolders.isEmpty, displayedComics.isEmpty {
                Section {
                    filteredContentEmptyStateView(content)
                }
            } else {
                foldersSection(displayedSubfolders)
                comicsSection(content, displayedComics: displayedComics)
            }
        }
    }

    private func gridContentView(_ content: LibraryFolderContent) -> some View {
        let displayedSubfolders = filteredSubfolders(content.subfolders, localQuery: folderSearchQuery)
        let displayedComics = filteredSortedComics(content.comics, localQuery: folderSearchQuery)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if hasLibraryStatus {
                    libraryStatusGridSection
                }

                if showsLocalFolderControls(for: content) {
                    localControlsGridContent(content)
                }

                if content.folder.isRoot && !hasActiveLocalFolderSearch {
                    continueReadingGridSection
                    browseByGridSection
                }

                if content.subfolders.isEmpty, content.comics.isEmpty {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "Empty Folder",
                        description: "This part of the library does not contain subfolders or comics yet."
                    )
                    .padding(.vertical, Spacing.xxxl)
                } else if displayedSubfolders.isEmpty, displayedComics.isEmpty {
                    filteredContentEmptyStateView(content)
                        .padding(.vertical, Spacing.xxxl)
                } else {
                    folderGridSection(displayedSubfolders)
                    comicGridSection(content, displayedComics: displayedComics)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.lg)
            .adaptiveContentWidth(1200)
        }
    }

    private var browseByShortcutItems: [LibraryShortcutCardItem] {
        [
            organizationShortcutItem(for: .readingLists),
            organizationShortcutItem(for: .labels),
            specialCollectionShortcutItem(for: .favorites),
            specialCollectionShortcutItem(for: .recent)
        ]
    }

    private func specialCollectionShortcutItem(
        for kind: LibrarySpecialCollectionKind
    ) -> LibraryShortcutCardItem {
        let count = viewModel.specialCollectionCount(for: kind)

        return LibraryShortcutCardItem(
            id: kind.id,
            title: kind.title,
            subtitle: kind.dashboardSubtitle(
                count: count,
                recentDays: viewModel.currentRecentDays
            ),
            systemImageName: kind.systemImageName,
            tint: .blue,
            destination: AnyView(
                LibrarySpecialCollectionView(
                    descriptor: viewModel.descriptor,
                    kind: kind,
                    dependencies: dependencies
                )
            )
        )
    }

    private func organizationShortcutItem(
        for sectionKind: LibraryOrganizationSectionKind
    ) -> LibraryShortcutCardItem {
        LibraryShortcutCardItem(
            id: sectionKind.id,
            title: sectionKind.title,
            subtitle: organizationShortcutSubtitle(for: sectionKind),
            systemImageName: sectionKind.systemImageName,
            tint: .orange,
            destination: AnyView(
                LibraryOrganizationView(
                    descriptor: viewModel.descriptor,
                    sectionKind: sectionKind,
                    dependencies: dependencies
                )
            )
        )
    }

    private func organizationShortcutSubtitle(
        for sectionKind: LibraryOrganizationSectionKind
    ) -> String {
        switch sectionKind {
        case .labels:
            return "Tags across folders"
        case .readingLists:
            return "Custom reading queues"
        }
    }

    @ViewBuilder
    private var continueReadingListSection: some View {
        collectionPreviewListSection(for: .reading)
    }

    @ViewBuilder
    private var continueReadingGridSection: some View {
        collectionPreviewGridSection(for: .reading)
    }

    @ViewBuilder
    private var browseByListSection: some View {
        if !browseByShortcutItems.isEmpty {
            Section("Browse By") {
                ForEach(browseByShortcutItems) { item in
                    NavigationLink {
                        item.destination
                    } label: {
                        InsetListRowCard {
                            LibraryShortcutRow(item: item)
                        }
                    }
                    .buttonStyle(.plain)
                    .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                }
            }
        }
    }

    @ViewBuilder
    private var browseByGridSection: some View {
        if !browseByShortcutItems.isEmpty {
            gridSection(title: "Browse By") {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: Spacing.md) {
                    ForEach(browseByShortcutItems) { item in
                        NavigationLink {
                            item.destination
                        } label: {
                            LibraryShortcutCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func collectionPreviewListSection(for kind: LibrarySpecialCollectionKind) -> some View {
        let comics = previewComics(for: kind)

        if !comics.isEmpty {
            Section {
                ForEach(comics) { comic in
                    previewListNavigationLink(for: kind, comic: comic)
                }
            } header: {
                collectionPreviewHeader(for: kind)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private func collectionPreviewGridSection(for kind: LibrarySpecialCollectionKind) -> some View {
        let comics = previewComics(for: kind)

        if !comics.isEmpty {
            gridSection {
                collectionPreviewHeader(for: kind)
            } content: {
                if kind == .reading, let comic = comics.first {
                    previewGridNavigationLink(for: kind, comic: comic)
                } else {
                    LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: Spacing.md) {
                        ForEach(comics) { comic in
                            previewGridNavigationLink(for: kind, comic: comic)
                        }
                    }
                }
            }
        }
    }

    private func previewComics(for kind: LibrarySpecialCollectionKind) -> [LibraryComic] {
        switch kind {
        case .reading:
            return viewModel.continueReadingComic.map { [$0] } ?? []
        case .recent:
            return viewModel.recentPreviewComics
        case .favorites:
            return viewModel.favoritesPreviewComics
        }
    }

    private func previewNavigationContext(for kind: LibrarySpecialCollectionKind) -> ReaderNavigationContext {
        ReaderNavigationContext(
            title: kind.title,
            comics: previewNavigationComics(for: kind)
        )
    }

    private func previewNavigationComics(for kind: LibrarySpecialCollectionKind) -> [LibraryComic] {
        switch kind {
        case .reading:
            return viewModel.continueReadingComics
        case .recent:
            return viewModel.recentComics
        case .favorites:
            return viewModel.favoritesComics
        }
    }

    private func previewSectionTitle(for kind: LibrarySpecialCollectionKind) -> String {
        switch kind {
        case .reading:
            return "Continue Reading"
        case .recent:
            return "Recently Added"
        case .favorites:
            return "Favorites"
        }
    }

    private func previewReaderDestination(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        comicReaderDestination(
            comic: comic,
            navigationContext: previewNavigationContext(for: kind)
        )
    }

    private func previewListNavigationLink(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        interactiveComicListNavigationLink(
            comic: comic,
            context: previewNavigationContext(for: kind),
            heroSourceID: previewHeroSourceID(for: kind, comic: comic),
            showsPersistentActions: kind != .reading,
            label: {
                previewListRow(
                    for: kind,
                    comic: comic,
                    trailingAccessoryReservedWidth: kind == .reading ? 0 : comicAccessoryReservedWidth
                )
            }
        )
    }

    @ViewBuilder
    private func previewListRow(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic,
        trailingAccessoryReservedWidth: CGFloat = 0
    ) -> some View {
        if kind == .reading {
            ContinueReadingRow(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                coverSource: viewModel.coverSource(for: comic),
                heroSourceID: previewHeroSourceID(for: kind, comic: comic)
            )
        } else {
            LibraryComicRow(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                coverSource: viewModel.coverSource(for: comic),
                heroSourceID: previewHeroSourceID(for: kind, comic: comic),
                trailingAccessoryReservedWidth: trailingAccessoryReservedWidth
            )
            .equatable()
        }
    }

    private func previewGridNavigationLink(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        interactiveComicGridNavigationLink(
            comic: comic,
            context: previewNavigationContext(for: kind),
            heroSourceID: previewHeroSourceID(for: kind, comic: comic),
            label: { previewGridCard(for: kind, comic: comic) }
        )
    }

    @ViewBuilder
    private func previewGridCard(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        if kind == .reading {
            ContinueReadingCard(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                coverSource: viewModel.coverSource(for: comic),
                heroSourceID: previewHeroSourceID(for: kind, comic: comic)
            )
        } else {
            LibraryComicCard(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                coverSource: viewModel.coverSource(for: comic),
                heroSourceID: previewHeroSourceID(for: kind, comic: comic)
            )
                .equatable()
        }
    }

    private func previewHeroSourceID(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> String {
        "library-preview-\(viewModel.descriptor.id.uuidString)-\(kind.id)-\(comic.id)"
    }

    private func showsLocalFolderControls(for content: LibraryFolderContent) -> Bool {
        guard !isSelectionMode else {
            return false
        }

        if !content.folder.isRoot {
            return true
        }

        return !(content.subfolders.isEmpty && content.comics.isEmpty)
    }

    private func localControlsListSection(_ content: LibraryFolderContent) -> some View {
        Section {
            localFolderControls(content)
                .padding(.vertical, Spacing.xxxs)
                .insetCardListRow(
                    horizontalInset: LayoutMetrics.horizontalInset,
                    top: 0,
                    bottom: 10
                )
        }
    }

    @ViewBuilder
    private var libraryStatusListSection: some View {
        Section("Status") {
            libraryStatusContent
        }
    }

    private var libraryStatusGridSection: some View {
        gridSection(title: "Status") {
            libraryStatusContent
        }
    }

    @ViewBuilder
    private var libraryStatusContent: some View {
        if let maintenanceSummaryLine {
            Label(maintenanceSummaryLine, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
        }

        if let scanProgress = viewModel.scanProgress {
            scanProgressPanel(scanProgress)
        }

        if let importNotice = viewModel.libraryImportNotice {
            libraryImportNoticePanel(importNotice)
        }
    }

    private func localControlsGridContent(_ content: LibraryFolderContent) -> some View {
        localFolderControls(content)
            .padding(.horizontal, LayoutMetrics.horizontalInset)
    }

    private var hasLibraryStatus: Bool {
        maintenanceSummaryLine != nil
            || viewModel.scanProgress != nil
            || viewModel.libraryImportNotice != nil
    }

    private var maintenanceSummaryLine: String? {
        if let maintenanceRecord = viewModel.maintenanceRecord {
            return maintenanceRecord.summaryLine
        }

        return viewModel.lastInitializationSummary?.summaryLine
    }

    private func libraryImportNoticePanel(_ message: String) -> some View {
        Label {
            Text(message)
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
                .font(AppFont.footnote(.semibold))
                .foregroundStyle(.orange)
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func foldersSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            Section {
                ForEach(folders) { folder in
                    folderListNavigationLink(for: folder)
                }
            } header: {
                sectionHeaderLabel("Folders", count: folders.count)
            }
        }
    }

    @ViewBuilder
    private func folderGridSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            gridSection(title: "Folders", count: folders.count) {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: Spacing.md) {
                    ForEach(folders) { folder in
                        folderGridNavigationLink(for: folder)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comicsSection(_ content: LibraryFolderContent, displayedComics: [LibraryComic]) -> some View {
        if !displayedComics.isEmpty {
            Section {
                ForEach(displayedComics) { comic in
                    if isSelectionMode {
                        Button {
                            toggleSelection(for: comic)
                        } label: {
                            InsetListRowCard {
                                LibraryComicRow(
                                    comic: comic,
                                    coverURL: viewModel.coverURL(for: comic),
                                    coverSource: viewModel.coverSource(for: comic),
                                    showsSelectionState: true,
                                    isSelected: selectedComicIDs.contains(comic.id)
                                )
                                .equatable()
                            }
                        }
                        .buttonStyle(.plain)
                        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                    } else {
                        interactiveComicListNavigationLink(
                                comic: comic,
                                context: ReaderNavigationContext(
                                    title: content.folder.displayName,
                                    comics: displayedComics
                                ),
                                label: {
                                    LibraryComicRow(
                                        comic: comic,
                                        coverURL: viewModel.coverURL(for: comic),
                                        coverSource: viewModel.coverSource(for: comic),
                                        heroSourceID: viewModel.heroSourceID(for: comic),
                                        trailingAccessoryReservedWidth: comicAccessoryReservedWidth
                                    )
                                    .equatable()
                                }
                            )
                    }
                }
            } header: {
                sectionHeaderLabel("Comics", count: displayedComics.count)
            }
        }
    }

    @ViewBuilder
    private func comicGridSection(_ content: LibraryFolderContent, displayedComics: [LibraryComic]) -> some View {
        if !displayedComics.isEmpty {
            gridSection(title: "Comics", count: displayedComics.count) {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: Spacing.md) {
                    ForEach(displayedComics) { comic in
                        if isSelectionMode {
                            Button {
                                toggleSelection(for: comic)
                            } label: {
                                LibraryComicCard(
                                    comic: comic,
                                    coverURL: viewModel.coverURL(for: comic),
                                    coverSource: viewModel.coverSource(for: comic),
                                    showsSelectionState: true,
                                    isSelected: selectedComicIDs.contains(comic.id)
                                )
                                .equatable()
                            }
                            .buttonStyle(.plain)
                        } else {
                            interactiveComicGridNavigationLink(
                                comic: comic,
                                context: ReaderNavigationContext(
                                    title: content.folder.displayName,
                                    comics: displayedComics
                                ),
                                label: {
                                    LibraryComicCard(
                                        comic: comic,
                                        coverURL: viewModel.coverURL(for: comic),
                                        coverSource: viewModel.coverSource(for: comic),
                                        heroSourceID: viewModel.heroSourceID(for: comic)
                                    )
                                        .equatable()
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private func gridSection<Content: View>(
        title: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        gridSection {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(AppFont.headline())

                if let count {
                    Text("(\(count))")
                        .font(AppFont.headline())
                        .foregroundStyle(Color.textTertiary)
                }
            }
        } content: {
            content()
        }
    }

    private func gridSection<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header()
            content()
        }
    }

    private func sectionHeaderLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: Spacing.xxs) {
            Text(title)
            Text("(\(count))")
                .foregroundStyle(Color.textTertiary)
        }
        .textCase(nil)
    }

    private func folderDestination(for folder: LibraryFolder) -> some View {
        LibraryBrowserView(
            descriptor: viewModel.descriptor,
            folderID: folder.id,
            dependencies: dependencies
        )
    }

    private func folderListNavigationLink(for folder: LibraryFolder) -> some View {
        NavigationLink {
            folderDestination(for: folder)
        } label: {
            InsetListRowCard {
                LibraryFolderRow(folder: folder, coverURL: viewModel.coverURL(for: folder))
            }
        }
        .buttonStyle(.plain)
        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
    }

    private func folderGridNavigationLink(for folder: LibraryFolder) -> some View {
        NavigationLink {
            folderDestination(for: folder)
        } label: {
            LibraryFolderCard(folder: folder, coverURL: viewModel.coverURL(for: folder))
        }
        .buttonStyle(.plain)
    }

    private func comicReaderDestination(
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext
    ) -> some View {
        ComicReaderView(
            descriptor: viewModel.descriptor,
            comic: comic,
            navigationContext: navigationContext,
            onComicUpdated: handleReaderComicUpdate,
            dependencies: dependencies
        )
    }

    private func interactiveComicListNavigationLink<Label: View>(
        comic: LibraryComic,
        context: ReaderNavigationContext,
        heroSourceID: String? = nil,
        showsPersistentActions: Bool = true,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let rowLabel = label()

        return HeroTapButton { frame in
            presentComic(
                comic,
                context: context,
                sourceFrame: frame,
                preferredHeroSourceID: heroSourceID
            )
        } label: {
            InsetListRowCard {
                rowLabel
            }
        }
        .buttonStyle(.plain)
        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
        .overlay(alignment: .trailing) {
            if showsPersistentComicActions && showsPersistentActions {
                persistentComicQuickActionsButton(for: comic)
                    .padding(.trailing, 8)
            }
        }
        .contextMenu {
            comicContextActions(for: comic)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            comicReadSwipeAction(for: comic)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            comicTrailingSwipeActions(for: comic)
        }
    }

    private func interactiveComicGridNavigationLink<Label: View>(
        comic: LibraryComic,
        context: ReaderNavigationContext,
        heroSourceID: String? = nil,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        HeroTapButton { frame in
            presentComic(
                comic,
                context: context,
                sourceFrame: frame,
                preferredHeroSourceID: heroSourceID
            )
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if showsPersistentComicActions {
                persistentComicQuickActionsButton(for: comic)
                    .padding(12)
            }
        }
        .contextMenu {
            comicContextActions(for: comic)
        }
    }

    private var cardGridColumns: [GridItem] {
        let widthRange = usesWideCardGridMetrics
            ? LayoutMetrics.regularGridMinWidth...LayoutMetrics.regularGridMaxWidth
            : LayoutMetrics.compactGridMinWidth...LayoutMetrics.compactGridMaxWidth
        return [
            GridItem(
                .adaptive(
                    minimum: widthRange.lowerBound,
                    maximum: widthRange.upperBound
                ),
                spacing: Spacing.md,
                alignment: .top
            )
        ]
    }

    private var usesWideCardGridMetrics: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= LayoutMetrics.wideGridMinContainerWidth)
    }

    @MainActor
    private func prepareHeroTransition(
        for comic: LibraryComic,
        fallbackFrame: CGRect,
        preferredHeroSourceID: String? = nil
    ) {
        let resolvedHeroSourceID = preferredHeroSourceID ?? viewModel.heroSourceID(for: comic)
        let registeredFrame = HeroSourceRegistry.shared.frame(for: resolvedHeroSourceID)
        heroSourceFrame = registeredFrame == .zero ? fallbackFrame : registeredFrame
        heroPreviewImage = LocalCoverTransitionCache.shared.image(for: resolvedHeroSourceID)
            ?? viewModel.cachedTransitionImage(for: comic)
    }

    private func presentComic(
        _ comic: LibraryComic,
        context: ReaderNavigationContext,
        sourceFrame: CGRect,
        preferredHeroSourceID: String? = nil
    ) {
        prepareHeroTransition(
            for: comic,
            fallbackFrame: sourceFrame,
            preferredHeroSourceID: preferredHeroSourceID
        )
        presentedComic = LibraryComicPresentation(comic: comic, navigationContext: context)
    }

    @ViewBuilder
    private func comicContextActions(for comic: LibraryComic) -> some View {
        Button {
            editingComic = comic
        } label: {
            Label("Edit Metadata", systemImage: "square.and.pencil")
        }

        Button {
            viewModel.toggleFavorite(for: comic)
        } label: {
            Label(
                comic.isFavorite ? "Remove Favorite" : "Add Favorite",
                systemImage: comic.isFavorite ? "star.slash" : "star"
            )
        }

        Button {
            viewModel.toggleReadStatus(for: comic)
        } label: {
            Label(
                comic.read ? "Mark Unread" : "Mark Read",
                systemImage: comic.read ? "arrow.uturn.backward.circle" : "checkmark.circle"
            )
        }

        if viewModel.canRemoveComics {
            Button(role: .destructive) {
                removingComic = comic
            } label: {
                Label("Delete Comic", systemImage: "trash")
            }
        }
    }

    private func persistentComicQuickActionsButton(for comic: LibraryComic) -> some View {
        Button {
            quickActionsComic = comic
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More Actions for \(comic.displayTitle)")
    }

    private func comicReadSwipeAction(for comic: LibraryComic) -> some View {
        Button {
            viewModel.toggleReadStatus(for: comic)
        } label: {
            Label(
                comic.read ? "Unread" : "Read",
                systemImage: comic.read ? "arrow.uturn.backward.circle" : "checkmark.circle"
            )
        }
        .tint(comic.read ? .orange : .green)
    }

    @ViewBuilder
    private func comicTrailingSwipeActions(for comic: LibraryComic) -> some View {
        Button {
            quickActionsComic = comic
        } label: {
            Label("Info", systemImage: "info.circle")
        }
        .tint(.indigo)

        Button {
            editingComic = comic
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        .tint(.blue)

        Button {
            viewModel.toggleFavorite(for: comic)
        } label: {
            Label(
                comic.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: comic.isFavorite ? "star.slash" : "star"
            )
        }
        .tint(.yellow)

        if viewModel.canRemoveComics {
            Button(role: .destructive) {
                removingComic = comic
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func specialCollectionDestination(_ kind: LibrarySpecialCollectionKind) -> some View {
        LibrarySpecialCollectionView(
            descriptor: viewModel.descriptor,
            kind: kind,
            dependencies: dependencies
        )
    }

    private func collectionPreviewHeader(
        for kind: LibrarySpecialCollectionKind
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(previewSectionTitle(for: kind))
                .font(AppFont.headline())

            Spacer(minLength: Spacing.sm)

            NavigationLink {
                specialCollectionDestination(kind)
            } label: {
                HStack(spacing: 4) {
                    Text("See All")

                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(.semibold))
                }
                .font(AppFont.subheadline(.semibold))
                .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private func queueQuickAction(_ action: PendingComicQuickAction) {
        pendingQuickAction = action
        quickActionsComic = nil
    }

    private func toggleSelection(for comic: LibraryComic) {
        AppHaptics.selection()
        if selectedComicIDs.contains(comic.id) {
            selectedComicIDs.remove(comic.id)
        } else {
            selectedComicIDs.insert(comic.id)
        }
    }

    private func endSelectionMode() {
        isSelectionMode = false
        isShowingBatchMetadataSheet = false
        isShowingComicInfoImportSheet = false
        isShowingBatchOrganizationSheet = false
        isShowingSelectionActionsSheet = false
        selectedComicIDs.removeAll()
    }

    private func toggleSelectAllVisibleComics() {
        let visibleIDs = Set(visibleComicIDs)
        guard !visibleIDs.isEmpty else {
            return
        }

        AppHaptics.selection()

        if areAllVisibleComicsSelected {
            selectedComicIDs.subtract(visibleIDs)
        } else {
            selectedComicIDs.formUnion(visibleIDs)
        }
    }

    private func performBatchReadAction(_ isRead: Bool) {
        if viewModel.setReadStatus(isRead, for: Array(selectedComicIDs)) {
            endSelectionMode()
        }
    }

    private func performBatchFavoriteAction(_ isFavorite: Bool) {
        if viewModel.setFavorite(isFavorite, for: Array(selectedComicIDs)) {
            endSelectionMode()
        }
    }

    private func scanProgressPanel(_ progress: LibraryScanProgress) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(progress.title)
                    .font(AppFont.footnote(.semibold))

                Text(progress.detailLine)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Spacing.xxxs)
    }

    @ViewBuilder
    private func localFolderControls(_ content: LibraryFolderContent) -> some View {
        if isSelectionMode {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                folderLocationControls(content)

                if !(content.subfolders.isEmpty && content.comics.isEmpty) {
                    LibraryInlineSearchField(
                        prompt: content.folder.isRoot ? "Filter library" : "Filter folder",
                        text: $folderSearchQuery
                    )

                    if !content.comics.isEmpty {
                        FilterChipBar(
                            items: LibraryComicQuickFilter.allCases.filter { $0 != .all },
                            selection: comicFilterChipBinding,
                            label: { $0.title }
                        )
                    }

                    if hasActiveLocalFolderFilters {
                        Button {
                            folderSearchQuery = ""
                            comicFilter = .all
                        } label: {
                            Text("Clear Filters")
                                .font(AppFont.caption(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appAccent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderLocationControls(_ content: LibraryFolderContent) -> some View {
        if !content.folder.isRoot {
            HStack(spacing: Spacing.md) {
                if let parentFolderID = parentFolderID(for: content) {
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: viewModel.descriptor,
                            folderID: parentFolderID,
                            dependencies: dependencies
                        )
                    } label: {
                        Label("Up", systemImage: "arrow.up.backward")
                            .font(AppFont.subheadline(.semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                }

                if content.folder.parentID != 1 {
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: viewModel.descriptor,
                            folderID: 1,
                            dependencies: dependencies
                        )
                    } label: {
                        Label("Library", systemImage: "house")
                            .font(AppFont.subheadline(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func parentFolderID(for content: LibraryFolderContent) -> Int64? {
        guard !content.folder.isRoot else {
            return nil
        }

        return content.folder.parentID > 0 ? content.folder.parentID : 1
    }

    private func filteredContentEmptyStateView(_ content: LibraryFolderContent) -> some View {
        EmptyStateView(
            systemImage: filteredContentEmptyStateSystemImage,
            title: filteredContentEmptyStateTitle,
            description: filteredContentEmptyStateDescription(content)
        )
        .padding(.vertical, Spacing.xl)
    }

    private var filteredContentEmptyStateTitle: String {
        hasActiveLocalFolderSearch ? "No Matching Items" : "No Matching Comics"
    }

    private var filteredContentEmptyStateSystemImage: String {
        hasActiveLocalFolderSearch ? "magnifyingglass" : comicFilter.systemImageName
    }

    private func filteredContentEmptyStateDescription(_ content: LibraryFolderContent) -> String {
        let trimmedQuery = trimmedFolderSearchQuery
        let location = content.folder.isRoot ? "this library section" : content.folder.displayName

        if !trimmedQuery.isEmpty, comicFilter != .all {
            return "No folders or comics in \(location) match \"\(trimmedQuery)\" while using the current \(comicFilter.title.lowercased()) filter."
        }

        if !trimmedQuery.isEmpty {
            return "No folders or comics in \(location) match \"\(trimmedQuery)\"."
        }

        return "No comics in \(location) match the current \(comicFilter.title.lowercased()) filter."
    }

    private var filteredComicEmptyStateView: some View {
        EmptyStateView(
            systemImage: comicFilter.systemImageName,
            title: "No Matching Comics",
            description: "No comics match the current \(comicFilter.title.lowercased()) filter."
        )
        .padding(.vertical, Spacing.xl)
    }

    private func configurePreferredDisplayModeIfNeeded() {
        guard !hasConfiguredPreferredDisplayMode else {
            return
        }

        hasConfiguredPreferredDisplayMode = true
        displayMode = supportsGridDisplay ? preferredDisplayMode : .list
    }

    private func adaptDisplayModeForCurrentWidth() {
        if supportsGridDisplay {
            displayMode = preferredDisplayMode
        } else if displayMode == .grid {
            displayMode = .list
        }
    }

    private func applyDisplayMode(_ mode: LibraryBrowserDisplayMode) {
        preferredDisplayMode = mode
        Self.persistDisplayMode(mode)
        displayMode = supportsGridDisplay ? mode : .list
    }

    private static func displayModeStorageKey() -> String {
        "libraryBrowserDisplayMode"
    }

    private static func loadStoredDisplayMode() -> LibraryBrowserDisplayMode {
        let defaults = UserDefaults.standard
        let storageKey = displayModeStorageKey()

        if let rawValue = defaults.string(forKey: storageKey),
           let storedMode = LibraryBrowserDisplayMode(rawValue: rawValue) {
            return storedMode
        }

        return .grid
    }

    private static func persistDisplayMode(_ mode: LibraryBrowserDisplayMode) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: displayModeStorageKey()
        )
    }

    private var searchResultsView: some View {
        List {
            if viewModel.isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Searching Library")
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
                }
            } else if let results = viewModel.searchResults {
                let displayedSearchComics = filteredSortedComics(results.comics)

                if results.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No Results",
                            description: "No folders or comics matched \"\(results.query)\"."
                        )
                        .padding(.vertical, Spacing.xl)
                    }
                } else {
                    if !results.comics.isEmpty {
                        searchResultsFilterSection(totalComicCount: results.comics.count)
                    }

                    if !results.folders.isEmpty {
                        Section {
                            ForEach(results.folders) { folder in
                                folderListNavigationLink(for: folder)
                            }
                        } header: {
                            sectionHeaderLabel("Matching Folders", count: results.folders.count)
                        }
                    }

                    if !displayedSearchComics.isEmpty {
                        Section {
                            ForEach(displayedSearchComics) { comic in
                                interactiveComicListNavigationLink(
                                    comic: comic,
                                    context: ReaderNavigationContext(
                                        title: "Search",
                                        comics: displayedSearchComics
                                    ),
                                    label: {
                                        LibraryComicRow(
                                            comic: comic,
                                            coverURL: viewModel.coverURL(for: comic),
                                            coverSource: viewModel.coverSource(for: comic),
                                            heroSourceID: viewModel.heroSourceID(for: comic),
                                            trailingAccessoryReservedWidth: comicAccessoryReservedWidth
                                        )
                                        .equatable()
                                    }
                                )
                            }
                        } header: {
                            sectionHeaderLabel("Matching Comics", count: displayedSearchComics.count)
                        }
                    } else if results.folders.isEmpty, !results.comics.isEmpty {
                        Section {
                            filteredComicEmptyStateView
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsFilterSection(totalComicCount: Int) -> some View {
        Section {
            FilterChipBar(
                items: LibraryComicQuickFilter.allCases.filter { $0 != .all },
                selection: comicFilterChipBinding,
                label: { $0.title }
            )
        } header: {
            Text("Filter")
        } footer: {
            Text(searchFilterSummaryText(totalCount: totalComicCount))
        }
    }

    private func searchFilterSummaryText(totalCount: Int) -> String {
        guard comicFilter != .all else {
            return totalCount == 1 ? "1 comic result" : "\(totalCount) comic results"
        }

        let visibleCount = visibleComics.count
        return "\(visibleCount) of \(totalCount) comic results in \(comicFilter.title.lowercased())"
    }
}

private enum PendingComicQuickAction {
    case edit(LibraryComic)
    case organize(LibraryComic)
    case remove(LibraryComic)
}

private struct LibraryComicPresentation: Identifiable {
    let id: UUID = UUID()
    let comic: LibraryComic
    let navigationContext: ReaderNavigationContext
}

private enum LibraryBrowserDisplayMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .list:
            return "List"
        case .grid:
            return "Grid"
        }
    }

    var systemImageName: String {
        switch self {
        case .list:
            return "list.bullet"
        case .grid:
            return "square.grid.2x2"
        }
    }
}
