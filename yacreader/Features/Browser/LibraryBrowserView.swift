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
                VStack(alignment: .leading, spacing: 4) {
                    Text(policy.title)
                    Text(policy.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            overviewSection(
                content,
                displayedSubfolders: displayedSubfolders,
                displayedComics: displayedComics
            )

            if content.folder.isRoot && !hasActiveLocalFolderSearch {
                continueReadingSection
                recentAddedSection
                favoritesSection
                specialCollectionsSection
                organizationSection
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
                gridOverviewCard(
                    content,
                    displayedSubfolders: displayedSubfolders,
                    displayedComics: displayedComics
                )

                if content.folder.isRoot && !hasActiveLocalFolderSearch {
                    continueReadingGridCard
                    recentAddedGridSection
                    favoritesGridSection

                    shortcutGridSection(
                        title: "Collections",
                        items: specialCollectionShortcutItems
                    )

                    shortcutGridSection(
                        title: "Organize",
                        items: LibraryOrganizationSectionKind.allCases.map { sectionKind in
                            LibraryShortcutCardItem(
                                id: sectionKind.id,
                                title: sectionKind.title,
                                subtitle: sectionKind.subtitle,
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
                    )
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
                subtitle: collectionSummarySubtitle(for: kind),
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
    }

    private var specialCollectionsSection: some View {
        Section("Collections") {
            ForEach(LibrarySpecialCollectionKind.allCases) { kind in
                NavigationLink {
                    LibrarySpecialCollectionView(
                        descriptor: viewModel.descriptor,
                        kind: kind,
                        dependencies: dependencies
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.systemImageName)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title)
                                .font(.headline)

                            Text(collectionSummarySubtitle(for: kind))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 12)

                        StatusBadge(title: collectionCountTitle(for: kind), tint: .blue)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var continueReadingSection: some View {
        if let comic = viewModel.continueReadingComic {
            Section("Continue Reading") {
                NavigationLink {
                    ComicReaderView(
                        descriptor: viewModel.descriptor,
                        comic: comic,
                        navigationContext: ReaderNavigationContext(
                            title: LibrarySpecialCollectionKind.reading.title,
                            comics: viewModel.continueReadingComics
                        ),
                        onComicUpdated: handleReaderComicUpdate,
                        dependencies: dependencies
                    )
                } label: {
                    ContinueReadingRow(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic),
                        trailingAccessoryReservedWidth: 40
                    )
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

                NavigationLink {
                    specialCollectionDestination(.reading)
                } label: {
                    collectionBrowseRow(
                        title: "Browse Reading",
                        subtitle: collectionSummarySubtitle(for: .reading)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var recentAddedSection: some View {
        if !viewModel.recentPreviewComics.isEmpty {
            Section("Recently Added") {
                ForEach(viewModel.recentPreviewComics) { comic in
                    NavigationLink {
                        ComicReaderView(
                            descriptor: viewModel.descriptor,
                            comic: comic,
                            navigationContext: ReaderNavigationContext(
                                title: LibrarySpecialCollectionKind.recent.title,
                                comics: viewModel.recentComics
                            ),
                            onComicUpdated: handleReaderComicUpdate,
                            dependencies: dependencies
                        )
                    } label: {
                        LibraryComicRow(
                            comic: comic,
                            coverURL: viewModel.coverURL(for: comic),
                            trailingAccessoryReservedWidth: 40
                        )
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

                NavigationLink {
                    specialCollectionDestination(.recent)
                } label: {
                    collectionBrowseRow(
                        title: "Browse Recent",
                        subtitle: collectionSummarySubtitle(for: .recent)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !viewModel.favoritesPreviewComics.isEmpty {
            Section("Favorites") {
                ForEach(viewModel.favoritesPreviewComics) { comic in
                    NavigationLink {
                        ComicReaderView(
                            descriptor: viewModel.descriptor,
                            comic: comic,
                            navigationContext: ReaderNavigationContext(
                                title: LibrarySpecialCollectionKind.favorites.title,
                                comics: viewModel.favoritesComics
                            ),
                            onComicUpdated: handleReaderComicUpdate,
                            dependencies: dependencies
                        )
                    } label: {
                        LibraryComicRow(
                            comic: comic,
                            coverURL: viewModel.coverURL(for: comic),
                            trailingAccessoryReservedWidth: 40
                        )
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

                NavigationLink {
                    specialCollectionDestination(.favorites)
                } label: {
                    collectionBrowseRow(
                        title: "Browse Favorites",
                        subtitle: collectionSummarySubtitle(for: .favorites)
                    )
                }
            }
        }
    }

    private var organizationSection: some View {
        Section("Organize") {
            ForEach(LibraryOrganizationSectionKind.allCases) { sectionKind in
                NavigationLink {
                    LibraryOrganizationView(
                        descriptor: viewModel.descriptor,
                        sectionKind: sectionKind,
                        dependencies: dependencies
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sectionKind.systemImageName)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(sectionKind.title)
                                .font(.headline)

                            Text(sectionKind.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func gridOverviewCard(
        _ content: LibraryFolderContent,
        displayedSubfolders: [LibraryFolder],
        displayedComics: [LibraryComic]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.folder.displayName)
                .font(.title2.weight(.semibold))

            Text(viewModel.folderPath)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                StatusBadge(title: folderCountTitle(displayed: displayedSubfolders.count, total: content.subfolders.count), tint: .blue)
                StatusBadge(title: comicCountTitle(displayed: displayedComics.count, total: content.comics.count), tint: .green)
                StatusBadge(title: content.folder.type.title, tint: .orange)
                if comicFilter != .all {
                    StatusBadge(title: comicFilter.title, tint: .teal)
                }
            }

            Text("Database: \(viewModel.databasePath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let summary = viewModel.lastInitializationSummary {
                Text("Latest scan: \(summary.summaryLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let scanProgress = viewModel.scanProgress {
                scanProgressPanel(scanProgress)
            }

            localFolderControls(content)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var continueReadingGridCard: some View {
        if let comic = viewModel.continueReadingComic {
            VStack(alignment: .leading, spacing: 14) {
                collectionPreviewHeader(
                    title: "Continue Reading",
                    subtitle: collectionSummarySubtitle(for: .reading),
                    kind: .reading
                )

                NavigationLink {
                    ComicReaderView(
                        descriptor: viewModel.descriptor,
                        comic: comic,
                        navigationContext: ReaderNavigationContext(
                            title: LibrarySpecialCollectionKind.reading.title,
                            comics: viewModel.continueReadingComics
                        ),
                        onComicUpdated: handleReaderComicUpdate,
                        dependencies: dependencies
                    )
                } label: {
                    ContinueReadingCard(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic)
                    )
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
        }
    }

    @ViewBuilder
    private var recentAddedGridSection: some View {
        if !viewModel.recentPreviewComics.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                collectionPreviewHeader(
                    title: "Recently Added",
                    subtitle: collectionSummarySubtitle(for: .recent),
                    kind: .recent
                )

                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(viewModel.recentPreviewComics) { comic in
                        NavigationLink {
                            ComicReaderView(
                                descriptor: viewModel.descriptor,
                                comic: comic,
                                navigationContext: ReaderNavigationContext(
                                    title: LibrarySpecialCollectionKind.recent.title,
                                    comics: viewModel.recentComics
                                ),
                                onComicUpdated: handleReaderComicUpdate,
                                dependencies: dependencies
                            )
                        } label: {
                            LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
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
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesGridSection: some View {
        if !viewModel.favoritesPreviewComics.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                collectionPreviewHeader(
                    title: "Favorites",
                    subtitle: collectionSummarySubtitle(for: .favorites),
                    kind: .favorites
                )

                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(viewModel.favoritesPreviewComics) { comic in
                        NavigationLink {
                            ComicReaderView(
                                descriptor: viewModel.descriptor,
                                comic: comic,
                                navigationContext: ReaderNavigationContext(
                                    title: LibrarySpecialCollectionKind.favorites.title,
                                    comics: viewModel.favoritesComics
                                ),
                                onComicUpdated: handleReaderComicUpdate,
                                dependencies: dependencies
                            )
                        } label: {
                            LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
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
                }
            }
        }
    }

    private func overviewSection(
        _ content: LibraryFolderContent,
        displayedSubfolders: [LibraryFolder],
        displayedComics: [LibraryComic]
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(content.folder.displayName)
                    .font(.headline)

                Text(viewModel.folderPath)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    StatusBadge(title: folderCountTitle(displayed: displayedSubfolders.count, total: content.subfolders.count), tint: .blue)
                    StatusBadge(title: comicCountTitle(displayed: displayedComics.count, total: content.comics.count), tint: .green)
                    StatusBadge(title: content.folder.type.title, tint: .orange)
                    if comicFilter != .all {
                        StatusBadge(title: comicFilter.title, tint: .teal)
                    }
                }

                Text("Database: \(viewModel.databasePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let summary = viewModel.lastInitializationSummary {
                    Text("Latest scan: \(summary.summaryLine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let scanProgress = viewModel.scanProgress {
                    scanProgressPanel(scanProgress)
                }

                if let libraryImportCompatibilityNotice = viewModel.libraryImportCompatibilityNotice {
                    libraryImportCompatibilityPanel(message: libraryImportCompatibilityNotice)
                }

                localFolderControls(content)
            }
            .padding(.vertical, 8)
        }
    }

    private func libraryImportCompatibilityPanel(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Direct Imports Unavailable")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func shortcutGridSection(
        title: String,
        items: [LibraryShortcutCardItem]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.headline)

                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
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
    private func foldersSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            Section("Folders") {
                ForEach(folders) { folder in
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: viewModel.descriptor,
                            folderID: folder.id,
                            dependencies: dependencies
                        )
                    } label: {
                        LibraryFolderRow(folder: folder, coverURL: viewModel.coverURL(for: folder))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderGridSection(_ folders: [LibraryFolder]) -> some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Folders")
                    .font(.headline)

                LazyVGrid(columns: cardGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(folders) { folder in
                        NavigationLink {
                            LibraryBrowserView(
                                descriptor: viewModel.descriptor,
                                folderID: folder.id,
                                dependencies: dependencies
                            )
                        } label: {
                            LibraryFolderCard(folder: folder, coverURL: viewModel.coverURL(for: folder))
                        }
                        .buttonStyle(.plain)
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
                        NavigationLink {
                            ComicReaderView(
                                descriptor: viewModel.descriptor,
                                comic: comic,
                                navigationContext: ReaderNavigationContext(
                                    title: content.folder.displayName,
                                    comics: displayedComics
                                ),
                                onComicUpdated: handleReaderComicUpdate,
                                dependencies: dependencies
                            )
                        } label: {
                            LibraryComicRow(
                                comic: comic,
                                coverURL: viewModel.coverURL(for: comic),
                                trailingAccessoryReservedWidth: 40
                            )
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
                }
            }
        }
    }

    @ViewBuilder
    private func comicGridSection(_ content: LibraryFolderContent, displayedComics: [LibraryComic]) -> some View {
        if !displayedComics.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Comics")
                    .font(.headline)

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
                            NavigationLink {
                                ComicReaderView(
                                    descriptor: viewModel.descriptor,
                                    comic: comic,
                                    navigationContext: ReaderNavigationContext(
                                        title: content.folder.displayName,
                                        comics: displayedComics
                                    ),
                                    onComicUpdated: handleReaderComicUpdate,
                                    dependencies: dependencies
                                )
                            } label: {
                                LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
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
                    }
                }
            }
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

    private func collectionSummarySubtitle(for kind: LibrarySpecialCollectionKind) -> String {
        kind.dashboardSubtitle(
            count: viewModel.specialCollectionCount(for: kind),
            recentDays: viewModel.currentRecentDays
        )
    }

    private func collectionCountTitle(for kind: LibrarySpecialCollectionKind) -> String {
        let count = viewModel.specialCollectionCount(for: kind)
        return count == 1 ? "1 comic" : "\(count) comics"
    }

    private func collectionBrowseRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }

    private func collectionPreviewHeader(
        title: String,
        subtitle: String,
        kind: LibrarySpecialCollectionKind
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            NavigationLink {
                specialCollectionDestination(kind)
            } label: {
                Label("See All", systemImage: "arrow.right")
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search")
                        .font(.headline)

                    Text("Query: \(viewModel.searchQuery)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let results = viewModel.searchResults {
                        Text(results.summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !results.comics.isEmpty {
                            Text(searchFilterSummaryText(totalCount: results.comics.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.isSearching {
                        Text("Searching library database...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let results = viewModel.searchResults,
                       !results.comics.isEmpty {
                        LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                            comicFilter = selectedFilter
                        }
                    }
                }
                .padding(.vertical, 8)
            }

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
                                NavigationLink {
                                    LibraryBrowserView(
                                        descriptor: viewModel.descriptor,
                                        folderID: folder.id,
                                        dependencies: dependencies
                                    )
                                } label: {
                                    LibraryFolderRow(folder: folder, coverURL: viewModel.coverURL(for: folder))
                                }
                            }
                        }
                    }

                    if !displayedSearchComics.isEmpty {
                        Section("Matching Comics") {
                            ForEach(displayedSearchComics) { comic in
                                NavigationLink {
                                    ComicReaderView(
                                        descriptor: viewModel.descriptor,
                                        comic: comic,
                                        navigationContext: ReaderNavigationContext(
                                            title: "Search",
                                            comics: displayedSearchComics
                                        ),
                                        onComicUpdated: handleReaderComicUpdate,
                                        dependencies: dependencies
                                    )
                                } label: {
                                    LibraryComicRow(
                                        comic: comic,
                                        coverURL: viewModel.coverURL(for: comic),
                                        trailingAccessoryReservedWidth: 40
                                    )
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
    let subtitle: String
    let systemImageName: String
    let tint: Color
    let destination: AnyView
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
        HStack(spacing: 12) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "folder.fill"
            )

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

                HStack(spacing: 8) {
                    StatusBadge(title: folder.type.title, tint: .orange)

                    if folder.finished {
                        StatusBadge(title: "Finished", tint: .green)
                    } else if folder.completed {
                        StatusBadge(title: "Complete", tint: .blue)
                    }
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
    }
}

private struct LibraryShortcutCard: View {
    let item: LibraryShortcutCardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: item.systemImageName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(item.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct ContinueReadingRow: View {
    let comic: LibraryComic
    let coverURL: URL?
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill",
                width: 64,
                height: 92
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(comic.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(comic.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StatusBadge(title: comic.progressText, tint: comic.read ? .green : .orange)

                    if !comic.bookmarkPageIndices.isEmpty {
                        StatusBadge(title: "\(comic.bookmarkPageIndices.count) bookmarks", tint: .blue)
                    }
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "play.fill")
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private struct ContinueReadingCard: View {
    let comic: LibraryComic
    let coverURL: URL?

    var body: some View {
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

                HStack(spacing: 8) {
                    StatusBadge(title: comic.progressText, tint: comic.read ? .green : .orange)
                    StatusBadge(title: comic.type.title, tint: .gray)
                }

                Spacer(minLength: 0)

                Label("Resume", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct LibraryFolderCard: View {
    let folder: LibraryFolder
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                HStack(spacing: 8) {
                    StatusBadge(title: folder.type.title, tint: .orange)

                    if folder.finished {
                        StatusBadge(title: "Finished", tint: .green)
                    } else if folder.completed {
                        StatusBadge(title: "Complete", tint: .blue)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
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
        HStack(spacing: 12) {
            if showsSelectionState {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            }

            LocalCoverThumbnailView(
                url: coverURL,
                placeholderSystemName: "book.closed.fill"
            )

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

                HStack(spacing: 8) {
                    StatusBadge(title: comic.progressText, tint: comic.read ? .green : .orange)
                    StatusBadge(title: comic.type.title, tint: .gray)

                    if comic.isFavorite {
                        StatusBadge(title: "Favorite", tint: .yellow)
                    }

                    if !comic.bookmarkPageIndices.isEmpty {
                        StatusBadge(title: "\(comic.bookmarkPageIndices.count) bookmarks", tint: .blue)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

struct LibraryComicCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var showsSelectionState = false
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

                if let issueLabel = comic.issueLabel {
                    StatusBadge(title: "#\(issueLabel)", tint: .blue)
                }

                HStack(spacing: 8) {
                    StatusBadge(title: comic.progressText, tint: comic.read ? .green : .orange)
                    StatusBadge(title: comic.type.title, tint: .gray)
                }

                HStack(spacing: 8) {
                    if comic.isFavorite {
                        StatusBadge(title: "Favorite", tint: .yellow)
                    }

                    if !comic.bookmarkPageIndices.isEmpty {
                        StatusBadge(title: "\(comic.bookmarkPageIndices.count) bookmarks", tint: .blue)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    showsSelectionState && isSelected ? Color.accentColor : Color.black.opacity(0.06),
                    lineWidth: showsSelectionState && isSelected ? 2 : 1
                )
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
