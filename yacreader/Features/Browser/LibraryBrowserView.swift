import SwiftUI
import UniformTypeIdentifiers

struct LibraryBrowserView: View {
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
    @State private var isSelectionMode = false
    @State private var selectedComicIDs = Set<Int64>()
    @State private var isShowingBatchMetadataSheet = false
    @State private var isShowingComicInfoImportSheet = false
    @State private var isShowingBatchOrganizationSheet = false
    @State private var isShowingSelectionActionsSheet = false
    @State private var isShowingComicFileImporter = false

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
                importedComicsImportService: dependencies.importedComicsImportService
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.hasActiveSearch {
                searchResultsView
            } else if let content = viewModel.content {
                contentView(content)
            } else if viewModel.isLoading || viewModel.isInitializingLibrary || viewModel.isRefreshingLibrary {
                VStack(spacing: 12) {
                    ProgressView(progressMessage)

                    if let scanProgress = viewModel.scanProgress {
                        Text(scanProgress.detailLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        viewModel.canInitializeLibrary ? "Library Not Initialized" : "Library Unavailable",
                        systemImage: viewModel.canInitializeLibrary ? "books.vertical.circle" : "externaldrive.badge.exclamationmark",
                        description: Text(viewModel.emptyStateMessage ?? "The selected library could not be loaded.")
                    )

                    if viewModel.canInitializeLibrary {
                        Button {
                            viewModel.initializeLibrary()
                        } label: {
                            Label("Initialize Library", systemImage: "sparkles.rectangle.stack")
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.borderedProminent)

                        Text("This creates a compatible `library.ydb`, inserts the root folder, and performs an initial scan of supported comic files.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top) {
            if let scanCompletion = viewModel.scanCompletion, viewModel.scanProgress == nil {
                ScanCompletionBanner(
                    completion: scanCompletion,
                    dismiss: viewModel.dismissScanCompletion
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
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
                                Image(systemName: "doc.badge.arrow.down")
                            }
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
                        }
                    }

                    if canMaintainCurrentContext {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                currentContextMaintenanceMenuContent
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                        }
                    }

                    if canAdjustDisplayMode {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                displayModeMenuContent
                            } label: {
                                Image(systemName: displayMode.systemImageName)
                            }
                        }
                    }

                    if canSortCurrentComics {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                sortModeMenuContent
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                            }
                        }
                    }
                }
            }

            if isSelectionMode {
                ToolbarItem(placement: .bottomBar) {
                    Text(selectionSummaryText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        .onChange(of: horizontalSizeClass) { _, newValue in
            adaptDisplayMode(to: newValue)
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
                }
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
                viewModel.alert = LibraryAlertState(
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
                viewModel.alert = LibraryAlertState(
                    title: "Import Failed",
                    message: error.localizedDescription
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
            }
        }
    }

    private var supportsGridDisplay: Bool {
        horizontalSizeClass == .regular
    }

    private var usesCondensedTopBarActions: Bool {
        horizontalSizeClass != .regular
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
                    Label("Import ComicInfo", systemImage: "doc.badge.arrow.down")
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                        Text(option.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Label("Import Library ComicInfo", systemImage: "doc.badge.arrow.down")
            }
        }

        if viewModel.canImportCurrentFolderComicInfo {
            Menu {
                comicInfoImportPolicyActions { policy in
                    viewModel.importCurrentFolderComicInfo(policy: policy)
                }
            } label: {
                Label("Import Current Folder ComicInfo", systemImage: "doc.badge.arrow.down")
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
            Section {
                overviewCard(
                    content,
                    displayedSubfolders: displayedSubfolders,
                    displayedComics: displayedComics,
                    titleFont: .headline
                )
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if content.folder.isRoot && !hasActiveLocalFolderSearch {
                ForEach(rootPreviewKinds, id: \.self) { kind in
                    collectionPreviewListSection(for: kind)
                }

                ForEach(dashboardShortcutSections) { section in
                    shortcutListSection(section)
                }
            }

            if content.subfolders.isEmpty, content.comics.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Empty Folder",
                        systemImage: "folder",
                        description: Text("This part of the library does not contain subfolders or comics yet.")
                    )
                    .padding(.vertical, 24)
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
            LazyVStack(alignment: .leading, spacing: 24) {
                overviewCard(
                    content,
                    displayedSubfolders: displayedSubfolders,
                    displayedComics: displayedComics,
                    titleFont: .title2.weight(.semibold)
                )

                if content.folder.isRoot && !hasActiveLocalFolderSearch {
                    ForEach(rootPreviewKinds, id: \.self) { kind in
                        collectionPreviewGridSection(for: kind)
                    }

                    ForEach(dashboardShortcutSections) { section in
                        shortcutGridSection(section)
                    }
                }

                if content.subfolders.isEmpty, content.comics.isEmpty {
                    ContentUnavailableView(
                        "Empty Folder",
                        systemImage: "folder",
                        description: Text("This part of the library does not contain subfolders or comics yet.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else if displayedSubfolders.isEmpty, displayedComics.isEmpty {
                    filteredContentEmptyStateView(content)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                } else {
                    folderGridSection(displayedSubfolders)
                    comicGridSection(content, displayedComics: displayedComics)
                }
            }
            .padding(20)
        }
    }

    private var specialCollectionShortcutItems: [LibraryShortcutCardItem] {
        LibrarySpecialCollectionKind.allCases.map { kind in
            LibraryShortcutCardItem(
                id: kind.id,
                title: kind.title,
                systemImageName: kind.systemImageName,
                tint: .blue,
                badgeTitle: collectionCountTitle(for: kind),
                destination: AnyView(
                    LibrarySpecialCollectionView(
                        descriptor: viewModel.descriptor,
                        kind: kind,
                        dependencies: dependencies
                    )
                )
            )
        }
    }

    private var organizationShortcutItems: [LibraryShortcutCardItem] {
        LibraryOrganizationSectionKind.allCases.map { sectionKind in
            LibraryShortcutCardItem(
                id: sectionKind.id,
                title: sectionKind.title,
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
    }

    private var rootPreviewKinds: [LibrarySpecialCollectionKind] {
        [.reading, .recent, .favorites]
    }

    private var dashboardShortcutSections: [LibraryDashboardShortcutSection] {
        [
            LibraryDashboardShortcutSection(
                title: "Collections",
                items: specialCollectionShortcutItems
            ),
            LibraryDashboardShortcutSection(
                title: "Organize",
                items: organizationShortcutItems
            )
        ]
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
                    LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
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
        interactiveComicListNavigationLink(comic: comic) {
            previewReaderDestination(for: kind, comic: comic)
        } label: {
            previewListRow(for: kind, comic: comic)
        }
    }

    @ViewBuilder
    private func previewListRow(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        if kind == .reading {
            ContinueReadingRow(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                trailingAccessoryReservedWidth: 40
            )
        } else {
            LibraryComicRow(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic),
                trailingAccessoryReservedWidth: 40
            )
        }
    }

    private func previewGridNavigationLink(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        interactiveComicGridNavigationLink(comic: comic) {
            previewReaderDestination(for: kind, comic: comic)
        } label: {
            previewGridCard(for: kind, comic: comic)
        }
    }

    @ViewBuilder
    private func previewGridCard(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> some View {
        if kind == .reading {
            ContinueReadingCard(
                comic: comic,
                coverURL: viewModel.coverURL(for: comic)
            )
        } else {
            LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
        }
    }

    private func overviewCard(
        _ content: LibraryFolderContent,
        displayedSubfolders: [LibraryFolder],
        displayedComics: [LibraryComic],
        titleFont: Font
    ) -> some View {
        InsetCard(cornerRadius: 20, contentPadding: 16, strokeOpacity: 0.04) {
            Text(content.folder.displayName)
                .font(titleFont)

            Text(viewModel.folderPath)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            AdaptiveStatusBadgeGroup(
                badges: overviewBadgeItems(
                    content,
                    displayedSubfolders: displayedSubfolders,
                    displayedComics: displayedComics
                )
            )

            FormOverviewContent(
                items: overviewDetailItems(for: content)
            ) {
                maintenanceSummaryView
            }

            if let scanProgress = viewModel.scanProgress {
                scanProgressPanel(scanProgress)
            }

            if let compatibilityPresentation = viewModel.compatibilityPresentation {
                libraryImportCompatibilityPanel(compatibilityPresentation)
            }

            localFolderControls(content)
        }
    }

    private func overviewDetailItems(
        for content: LibraryFolderContent
    ) -> [FormOverviewItem] {
        var items = [
            FormOverviewItem(
                title: content.folder.isRoot ? "Location" : "Path",
                value: viewModel.folderPath
            )
        ]

        if content.folder.isRoot {
            items.append(
                FormOverviewItem(
                    title: "Database",
                    value: viewModel.databasePath
                )
            )
        }

        return items
    }

    private func libraryImportCompatibilityPanel(
        _ presentation: LibraryCompatibilityPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.iconName ?? "externaldrive.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(presentation.tint ?? .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.bannerTitle ?? "Direct Imports Unavailable")
                    .font(.subheadline.weight(.semibold))

                Text(presentation.bannerMessage ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background((presentation.tint ?? .orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var maintenanceSummaryView: some View {
        if let maintenanceRecord = viewModel.maintenanceRecord {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent("Latest Scan", value: maintenanceRecord.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let detailLine = maintenanceRecord.detailLine {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let summary = viewModel.lastInitializationSummary {
            LabeledContent("Latest Scan", value: summary.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func overviewBadgeItems(
        _ content: LibraryFolderContent,
        displayedSubfolders: [LibraryFolder],
        displayedComics: [LibraryComic]
    ) -> [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: folderCountTitle(displayed: displayedSubfolders.count, total: content.subfolders.count),
                tint: .blue
            ),
            StatusBadgeItem(
                title: comicCountTitle(displayed: displayedComics.count, total: content.comics.count),
                tint: .green
            ),
            StatusBadgeItem(title: content.folder.type.title, tint: .orange)
        ]

        if comicFilter != .all {
            badges.append(StatusBadgeItem(title: comicFilter.title, tint: .teal))
        }

        if hasActiveLocalFolderSearch {
            badges.append(StatusBadgeItem(title: "Searching", tint: .pink))
        }

        return badges
    }

    @ViewBuilder
    private func shortcutGridSection(_ section: LibraryDashboardShortcutSection) -> some View {
        if !section.items.isEmpty {
            gridSection(title: section.title) {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(section.items) { item in
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
    private func shortcutListSection(_ section: LibraryDashboardShortcutSection) -> some View {
        if !section.items.isEmpty {
            Section(section.title) {
                ForEach(section.items) { item in
                    NavigationLink {
                        item.destination
                    } label: {
                        LibraryShortcutRow(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func foldersSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            Section("Folders") {
                ForEach(folders) { folder in
                    folderListNavigationLink(for: folder)
                }
            }
        }
    }

    @ViewBuilder
    private func folderGridSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            gridSection(title: "Folders") {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
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
            Section("Comics") {
                ForEach(displayedComics) { comic in
                    if isSelectionMode {
                        Button {
                            toggleSelection(for: comic)
                        } label: {
                            LibraryComicRow(
                                comic: comic,
                                coverURL: viewModel.coverURL(for: comic),
                                showsSelectionState: true,
                                isSelected: selectedComicIDs.contains(comic.id)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        interactiveComicListNavigationLink(comic: comic) {
                            comicReaderDestination(
                                comic: comic,
                                navigationContext: ReaderNavigationContext(
                                    title: content.folder.displayName,
                                    comics: displayedComics
                                )
                            )
                        } label: {
                            LibraryComicRow(
                                comic: comic,
                                coverURL: viewModel.coverURL(for: comic),
                                trailingAccessoryReservedWidth: 40
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comicGridSection(_ content: LibraryFolderContent, displayedComics: [LibraryComic]) -> some View {
        if !displayedComics.isEmpty {
            gridSection(title: "Comics") {
                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(displayedComics) { comic in
                        if isSelectionMode {
                            Button {
                                toggleSelection(for: comic)
                            } label: {
                                LibraryComicCard(
                                    comic: comic,
                                    coverURL: viewModel.coverURL(for: comic),
                                    showsSelectionState: true,
                                    isSelected: selectedComicIDs.contains(comic.id)
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            interactiveComicGridNavigationLink(comic: comic) {
                                comicReaderDestination(
                                    comic: comic,
                                    navigationContext: ReaderNavigationContext(
                                        title: content.folder.displayName,
                                        comics: displayedComics
                                    )
                                )
                            } label: {
                                LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
                            }
                        }
                    }
                }
            }
        }
    }

    private func gridSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        gridSection {
            Text(title)
                .font(.headline)
        } content: {
            content()
        }
    }

    private func gridSection<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header()
            content()
        }
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
            LibraryFolderRow(folder: folder, coverURL: viewModel.coverURL(for: folder))
        }
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

    private func interactiveComicListNavigationLink<Destination: View, Label: View>(
        comic: LibraryComic,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            label()
        }
        .overlay(alignment: .trailing) {
            quickActionButton(for: comic)
                .padding(.trailing, 8)
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

    private func interactiveComicGridNavigationLink<Destination: View, Label: View>(
        comic: LibraryComic,
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            quickActionButton(for: comic, compact: true)
                .padding(12)
        }
        .contextMenu {
            comicContextActions(for: comic)
        }
    }

    private var cardGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16, alignment: .top)
        ]
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
    }

    private func quickActionButton(for comic: LibraryComic, compact: Bool = false) -> some View {
        LibraryComicQuickActionButton(compact: compact) {
            quickActionsComic = comic
        }
    }

    private func specialCollectionDestination(_ kind: LibrarySpecialCollectionKind) -> some View {
        LibrarySpecialCollectionView(
            descriptor: viewModel.descriptor,
            kind: kind,
            dependencies: dependencies
        )
    }

    private func collectionCountTitle(for kind: LibrarySpecialCollectionKind) -> String {
        let count = viewModel.specialCollectionCount(for: kind)
        return count == 1 ? "1 comic" : "\(count) comics"
    }

    private func collectionPreviewHeader(
        for kind: LibrarySpecialCollectionKind
    ) -> some View {
        HStack(spacing: 12) {
            Text(previewSectionTitle(for: kind))
                .font(.headline)

            Spacer(minLength: 12)

            NavigationLink {
                specialCollectionDestination(kind)
            } label: {
                Text("See All")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    private func queueQuickAction(_ action: PendingComicQuickAction) {
        pendingQuickAction = action
        quickActionsComic = nil
    }

    private func toggleSelection(for comic: LibraryComic) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(progress.title)
                    .font(.subheadline.weight(.semibold))
            }

            Text(progress.detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    @ViewBuilder
    private func localFolderControls(_ content: LibraryFolderContent) -> some View {
        if isSelectionMode {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                folderLocationControls(content)

                if !(content.subfolders.isEmpty && content.comics.isEmpty) {
                    LibraryInlineSearchField(
                        prompt: content.folder.isRoot ? "Filter this library section" : "Filter this folder",
                        text: $folderSearchQuery
                    )

                    if !content.comics.isEmpty {
                        LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                            comicFilter = selectedFilter
                        }
                    }

                    if hasActiveLocalFolderFilters {
                        Button {
                            folderSearchQuery = ""
                            comicFilter = .all
                        } label: {
                            Label("Reset Filters", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderLocationControls(_ content: LibraryFolderContent) -> some View {
        if !content.folder.isRoot {
            HStack(spacing: 10) {
                if let parentFolderID = parentFolderID(for: content) {
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: viewModel.descriptor,
                            folderID: parentFolderID,
                            dependencies: dependencies
                        )
                    } label: {
                        Label("Up One Level", systemImage: "arrow.up.backward")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if content.folder.parentID != 1 {
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: viewModel.descriptor,
                            folderID: 1,
                            dependencies: dependencies
                        )
                    } label: {
                        Label("Library Root", systemImage: "house")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
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

    private func folderCountTitle(displayed: Int, total: Int) -> String {
        countTitle(
            displayed: displayed,
            total: total,
            singular: "folder",
            plural: "folders",
            useFilteredCount: hasActiveLocalFolderSearch && displayed != total
        )
    }

    private func comicCountTitle(displayed: Int, total: Int) -> String {
        countTitle(
            displayed: displayed,
            total: total,
            singular: "comic",
            plural: "comics",
            useFilteredCount: hasActiveLocalFolderSearch || comicFilter != .all
        )
    }

    private func countTitle(
        displayed: Int,
        total: Int,
        singular: String,
        plural: String,
        useFilteredCount: Bool
    ) -> String {
        let totalNoun = total == 1 ? singular : plural
        guard useFilteredCount, displayed != total else {
            return "\(total) \(totalNoun)"
        }

        return "\(displayed) of \(total) \(totalNoun)"
    }

    private func filteredContentEmptyStateView(_ content: LibraryFolderContent) -> some View {
        ContentUnavailableView(
            filteredContentEmptyStateTitle,
            systemImage: filteredContentEmptyStateSystemImage,
            description: Text(filteredContentEmptyStateDescription(content))
        )
        .padding(.vertical, 24)
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
        ContentUnavailableView(
            "No Matching Comics",
            systemImage: comicFilter.systemImageName,
            description: Text("No comics match the current \(comicFilter.title.lowercased()) filter.")
        )
        .padding(.vertical, 24)
    }

    private func configurePreferredDisplayModeIfNeeded() {
        guard !hasConfiguredPreferredDisplayMode else {
            return
        }

        hasConfiguredPreferredDisplayMode = true
        displayMode = supportsGridDisplay ? preferredDisplayMode : .list
    }

    private func adaptDisplayMode(to sizeClass: UserInterfaceSizeClass?) {
        if sizeClass == .regular {
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
            searchResultsSummarySection

            if viewModel.isSearching {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Searching Library")
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            } else if let results = viewModel.searchResults {
                let displayedSearchComics = filteredSortedComics(results.comics)

                if results.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("No folders or comics matched \"\(results.query)\".")
                        )
                        .padding(.vertical, 24)
                    }
                } else {
                    if !results.folders.isEmpty {
                        Section("Matching Folders") {
                            ForEach(results.folders) { folder in
                                folderListNavigationLink(for: folder)
                            }
                        }
                    }

                    if !displayedSearchComics.isEmpty {
                        Section("Matching Comics") {
                            ForEach(displayedSearchComics) { comic in
                                interactiveComicListNavigationLink(comic: comic) {
                                    comicReaderDestination(
                                        comic: comic,
                                        navigationContext: ReaderNavigationContext(
                                            title: "Search",
                                            comics: displayedSearchComics
                                        )
                                    )
                                } label: {
                                    LibraryComicRow(
                                        comic: comic,
                                        coverURL: viewModel.coverURL(for: comic),
                                        trailingAccessoryReservedWidth: 40
                                    )
                                }
                            }
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

    private var searchResultsSummarySection: some View {
        Section {
            SectionSummaryCard(
                title: "Search",
                badges: searchResultBadgeItems,
                titleFont: .headline,
                cornerRadius: 20,
                contentPadding: 16,
                strokeOpacity: 0.04
            ) {
                if let results = viewModel.searchResults {
                    SummaryMetricGroup(
                        metrics: searchResultMetrics(for: results),
                        style: .compactValue
                    )

                    Text(results.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !results.comics.isEmpty {
                        Text(searchFilterSummaryText(totalCount: results.comics.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                            comicFilter = selectedFilter
                        }
                    }
                } else if viewModel.isSearching {
                    Text("Searching library database...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var searchResultBadgeItems: [StatusBadgeItem] {
        guard let results = viewModel.searchResults else {
            return viewModel.isSearching ? [StatusBadgeItem(title: "Searching", tint: .blue)] : []
        }

        var badges = [StatusBadgeItem]()

        if comicFilter != .all, !results.comics.isEmpty {
            badges.append(StatusBadgeItem(title: comicFilter.title, tint: .teal))
        }

        if results.isEmpty {
            badges.append(StatusBadgeItem(title: "No Results", tint: .orange))
        }

        return badges
    }

    private func searchResultMetrics(
        for results: LibrarySearchResults
    ) -> [SummaryMetricItem] {
        var metrics = [
            SummaryMetricItem(
                title: "Folders",
                value: "\(results.folders.count)",
                tint: .blue
            ),
            SummaryMetricItem(
                title: "Comics",
                value: "\(results.comics.count)",
                tint: .green
            )
        ]

        if comicFilter != .all, !results.comics.isEmpty {
            metrics.append(
                SummaryMetricItem(
                    title: "Visible",
                    value: "\(visibleComics.count)",
                    tint: .teal
                )
            )
        }

        return metrics
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

private struct LibraryShortcutCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImageName: String
    let tint: Color
    let badgeTitle: String?
    let destination: AnyView

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImageName: String,
        tint: Color,
        badgeTitle: String? = nil,
        destination: AnyView
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.tint = tint
        self.badgeTitle = badgeTitle
        self.destination = destination
    }
}

private struct LibraryDashboardShortcutSection: Identifiable {
    let id: String
    let title: String
    let items: [LibraryShortcutCardItem]

    init(
        id: String? = nil,
        title: String,
        items: [LibraryShortcutCardItem]
    ) {
        self.id = id ?? title
        self.title = title
        self.items = items
    }
}

private struct ScanCompletionBanner: View {
    let completion: LibraryScanCompletionState
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text(completion.title)
                    .font(.subheadline.weight(.semibold))

                Text(completion.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

private struct LibraryFolderRow: View {
    let folder: LibraryFolder
    let coverURL: URL?

    var body: some View {
        LibraryBrowserListRowShell {
            EmptyView()
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "folder.fill"
            )
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text(folder.displayName)
                    .font(.headline)
                    .lineLimit(2)

                if let childCountText = folder.childCountText {
                    Text(childCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(folder.path)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                AdaptiveStatusBadgeGroup(badges: folder.browserBadgeItems)
            }
        } trailingAccessory: {
            EmptyView()
        }
    }
}

private struct LibraryShortcutCard: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        InsetCard(cornerRadius: 18, contentPadding: 18, strokeOpacity: 0.06) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: item.systemImageName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)

            if let badgeTitle = item.badgeTitle {
                StatusBadge(title: badgeTitle, tint: item.tint)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? 108 : 132, alignment: .topLeading)
    }
}

private struct LibraryShortcutRow: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: item.systemImageName)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)

            Spacer(minLength: 12)

            if let badgeTitle = item.badgeTitle {
                StatusBadge(title: badgeTitle, tint: item.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ContinueReadingRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        LibraryBrowserListRowShell(spacing: 14, trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            EmptyView()
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: 64,
                height: 92
            )
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AdaptiveStatusBadgeGroup(badges: comic.continueReadingRowBadges)
            }
        } trailingAccessory: {
            Image(systemName: "play.fill")
                .foregroundStyle(.blue)
        }
    }
}

private struct ContinueReadingCard: View {
    let comic: LibraryComic
    let coverURL: URL?

    var body: some View {
        LibraryBrowserContentCard(minHeight: 188, cornerRadius: 20, contentPadding: 20) {
            HStack(spacing: 18) {
                LocalCoverThumbnailView(
                    url: coverURL,
                    placeholderSystemName: "book.closed.fill",
                    width: 104,
                    height: 148
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(comic.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(comic.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    AdaptiveStatusBadgeGroup(badges: comic.continueReadingCardBadges)

                    Spacer(minLength: 0)

                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct LibraryFolderCard: View {
    let folder: LibraryFolder
    let coverURL: URL?

    var body: some View {
        LibraryBrowserContentCard(minHeight: 250) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "folder.fill",
                width: 96,
                height: 120
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(folder.displayName)
                    .font(.headline)
                    .lineLimit(2)

                Text(folder.childCountText ?? folder.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                AdaptiveStatusBadgeGroup(badges: folder.browserBadgeItems)
            }
        }
    }
}

struct LibraryComicRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var showsSelectionState = false
    var isSelected = false
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        LibraryBrowserListRowShell(trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            } else {
                EmptyView()
            }
        } thumbnail: {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill"
            )
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(comic.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let issueLabel = comic.issueLabel {
                        StatusBadge(title: "#\(issueLabel)", tint: .blue)
                    }
                }

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AdaptiveStatusBadgeGroup(badges: comic.browserRowBadges)
            }
        } trailingAccessory: {
            EmptyView()
        }
    }
}

struct LibraryComicCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var showsSelectionState = false
    var isSelected = false

    var body: some View {
        LibraryBrowserContentCard(minHeight: 330, isSelected: showsSelectionState && isSelected) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: 120,
                height: 168
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                AdaptiveStatusBadgeGroup(badges: comic.browserCardBadges)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                    .padding(14)
            }
        }
    }
}

private struct LibraryBrowserContentCard<Content: View>: View {
    let minHeight: CGFloat
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 18
    var strokeOpacity: Double = 0.06
    var isSelected = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            strokeOpacity: strokeOpacity
        ) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

private struct LibraryBrowserListRowShell<
    LeadingAccessory: View,
    Thumbnail: View,
    Content: View,
    TrailingAccessory: View
>: View {
    var spacing: CGFloat = 12
    var trailingAccessoryReservedWidth: CGFloat = 0
    @ViewBuilder let leadingAccessory: () -> LeadingAccessory
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailingAccessory: () -> TrailingAccessory

    var body: some View {
        HStack(spacing: spacing) {
            leadingAccessory()
            thumbnail()
            content()
            Spacer(minLength: 12)
            trailingAccessory()
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private extension LibraryFolder {
    var browserBadgeItems: [StatusBadgeItem] {
        var badges = [StatusBadgeItem(title: type.title, tint: .orange)]

        if finished {
            badges.append(StatusBadgeItem(title: "Finished", tint: .green))
        } else if completed {
            badges.append(StatusBadgeItem(title: "Complete", tint: .blue))
        }

        return badges
    }
}

private extension LibraryComic {
    var issueBadgeItem: StatusBadgeItem? {
        issueLabel.map { StatusBadgeItem(title: "#\($0)", tint: .blue) }
    }

    var continueReadingRowBadges: [StatusBadgeItem] {
        var badges = [StatusBadgeItem(title: progressText, tint: read ? .green : .orange)]

        if !bookmarkPageIndices.isEmpty {
            badges.append(StatusBadgeItem(title: "\(bookmarkPageIndices.count) bookmarks", tint: .blue))
        }

        return badges
    }

    var continueReadingCardBadges: [StatusBadgeItem] {
        [
            StatusBadgeItem(title: progressText, tint: read ? .green : .orange),
            StatusBadgeItem(title: type.title, tint: .gray)
        ]
    }

    var browserRowBadges: [StatusBadgeItem] {
        var badges: [StatusBadgeItem] = []
        badges.append(StatusBadgeItem(title: progressText, tint: read ? .green : .orange))
        badges.append(StatusBadgeItem(title: type.title, tint: .gray))

        if isFavorite {
            badges.append(StatusBadgeItem(title: "Favorite", tint: .yellow))
        }

        if !bookmarkPageIndices.isEmpty {
            badges.append(StatusBadgeItem(title: "\(bookmarkPageIndices.count) bookmarks", tint: .blue))
        }

        return badges
    }

    var browserCardBadges: [StatusBadgeItem] {
        var badges = browserRowBadges

        if let issueBadgeItem {
            badges.insert(issueBadgeItem, at: 0)
        }

        return badges
    }
}
