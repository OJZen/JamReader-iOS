import SwiftUI

struct LibraryOrganizationCollectionDetailView: View {
    private enum LayoutMetrics {
        static let horizontalInset: CGFloat = 12
        static let rowAccessoryReservedWidth: CGFloat = 36
        static let compactGridMinWidth: CGFloat = 165
        static let compactGridMaxWidth: CGFloat = 220
        static let regularGridMinWidth: CGFloat = 240
        static let regularGridMaxWidth: CGFloat = 320
        static let wideGridMinContainerWidth: CGFloat = 860
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: LibraryOrganizationCollectionDetailViewModel
    @State private var comicSortMode: LibraryComicSortMode
    @State private var preferredDisplayMode: LibraryComicDisplayMode
    @State private var displayMode: LibraryComicDisplayMode
    @State private var hasConfiguredPreferredDisplayMode = false
    @State private var searchQuery = ""
    @State private var comicFilter: LibraryComicQuickFilter = .all
    @State private var editingCollection: LibraryOrganizationCollection?
    @State private var deletingCollection: LibraryOrganizationCollection?
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
    @State private var presentedComic: PresentedComic?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var containerWidth: CGFloat = 0

    private var showsPersistentComicActions: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularInlineActionMinWidth)
    }

    private var comicAccessoryReservedWidth: CGFloat {
        showsPersistentComicActions ? LayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var adaptiveListColumnCount: Int {
        AppLayout.adaptiveListColumnCount(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: containerWidth
        )
    }

    private var adaptiveListColumnSpacing: CGFloat {
        AppLayout.adaptiveListColumnSpacing(for: adaptiveListColumnCount)
    }

    init(
        descriptor: LibraryDescriptor,
        collection: LibraryOrganizationCollection,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _comicSortMode = State(initialValue: Self.loadStoredSortMode(for: collection))
        let storedDisplayMode = Self.loadStoredDisplayMode(for: collection)
        _preferredDisplayMode = State(initialValue: storedDisplayMode)
        _displayMode = State(initialValue: storedDisplayMode)
        _viewModel = StateObject(
            wrappedValue: LibraryOrganizationCollectionDetailViewModel(
                descriptor: descriptor,
                collection: collection,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager,
                coverLocator: dependencies.libraryCoverLocator,
                comicRemovalService: dependencies.libraryComicRemovalService
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(message: "Loading \(viewModel.collection.displayTitle)")
            } else {
                contentBody
            }
        }
        .readContainerWidth(into: $containerWidth)
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
                    ToolbarItem(placement: .topBarTrailing) {
                        condensedTopBarActionsMenu
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

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            collectionManagementMenuContent
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Collection Actions")
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

                    if canSortComics {
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
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            configurePreferredDisplayModeIfNeeded()
            viewModel.load()
        }
        .onChange(of: supportsGridDisplay) { _, _ in
            adaptDisplayModeForCurrentWidth()
        }
        .onChange(of: displayedComics.map(\.id)) { _, visibleComicIDs in
            let visibleIDs = Set(visibleComicIDs)
            selectedComicIDs = selectedComicIDs.intersection(visibleIDs)

            if isSelectionMode && visibleIDs.isEmpty {
                endSelectionMode()
            }
        }
        .refreshable {
            viewModel.load()
        }
        .searchable(text: $searchQuery, prompt: "Filter comics")
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
                removeFromContextTitle: "Remove from \(viewModel.collection.displayTitle)",
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
                onRemoveFromCurrentContext: {
                    viewModel.remove(comic)
                    quickActionsComic = nil
                },
                onRemoveFromLibrary: viewModel.canRemoveComics ? {
                    queueQuickAction(.remove(comic))
                } : nil
            )
        }
        .sheet(item: $editingCollection) { collection in
            LibraryOrganizationCollectionEditorSheet(collection: collection) { name, color in
                viewModel.updateCollection(
                    name: name,
                    labelColor: color
                )
            }
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
                organizeActionTitle: "Tags and Reading Lists",
                removeFromContextTitle: viewModel.collection.type == .label ? "Remove from Tag" : "Remove from Reading List",
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
                },
                onRemoveFromCurrentContext: {
                    performBatchRemoveAction()
                }
            )
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(readerPresenter)
        .confirmationDialog(
            deletingCollectionDialogTitle,
            isPresented: deletingCollectionConfirmationBinding,
            titleVisibility: .visible,
            presenting: deletingCollection
        ) { collection in
            Button(deleteCollectionActionTitle(for: collection), role: .destructive) {
                if viewModel.deleteCollection() {
                    deletingCollection = nil
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) {
                deletingCollection = nil
            }
        } message: { collection in
            Text(deleteCollectionMessage(for: collection))
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
                if viewModel.removeComicFromLibrary(comic) {
                    removingComic = nil
                }
            }
        } message: { comic in
            Text("Deletes \"\(comic.displayTitle)\" from this library and removes the local file.")
        }
        .onChange(of: searchQuery) { _, _ in
            if isSelectionMode {
                endSelectionMode()
            }
        }
        .onChange(of: comicFilter) { _, _ in
            if isSelectionMode {
                endSelectionMode()
            }
        }
    }

    @ViewBuilder
    private var readerPresenter: some View {
        HeroReaderPresenter(
            item: $presentedComic,
            sourceFrame: heroSourceFrame,
            onDismiss: {
                heroSourceFrame = .zero
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
    }

    @ViewBuilder
    private var contentBody: some View {
        if displayMode == .grid {
            gridContent
        } else {
            listContent
        }
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

    private var listContent: some View {
        List {
            if showsFilterControls {
                filterControlsSection
            }

            if displayedComics.isEmpty {
                Section {
                    emptyStateView
                }
            } else {
                Section(contentSectionTitle) {
                    AdaptiveCardListRows(
                        displayedComics,
                        columnCount: adaptiveListColumnCount,
                        spacing: adaptiveListColumnSpacing,
                        horizontalInset: LayoutMetrics.horizontalInset
                    ) { comic in
                        listComicRow(
                            for: comic,
                            appliesListRowInsets: false,
                            enablesSwipeActions: adaptiveListColumnCount == 1
                        )
                    }
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if showsFilterControls {
                    filterControlsContent
                }

                if displayedComics.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(contentSectionTitle)
                            .font(.headline)

                        LazyVGrid(columns: comicGridColumns, alignment: .leading, spacing: 16) {
                            ForEach(displayedComics) { comic in
                                gridComicCard(for: comic)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .adaptiveContentWidth(1200)
        }
    }

    private var filterControlsSection: some View {
        Section {
            filterControlsContent
                .padding(.vertical, Spacing.xxxs)
                .insetCardListRow(
                    horizontalInset: LayoutMetrics.horizontalInset,
                    top: 0,
                    bottom: 10
                )
        }
    }

    private var filterControlsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                comicFilter = selectedFilter
            }

            if canResetFilters {
                Button("Clear Filters", action: resetFilters)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: emptyStateSystemImage,
            title: emptyStateTitle,
            description: emptyStateDescription
        )
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func listComicRow(
        for comic: LibraryComic,
        appliesListRowInsets: Bool = true,
        enablesSwipeActions: Bool = true
    ) -> some View {
        if isSelectionMode {
            let row = Button {
                toggleSelection(for: comic)
            } label: {
                InsetListRowCard {
                    LibraryComicRow(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic),
                        showsSelectionState: true,
                        isSelected: selectedComicIDs.contains(comic.id)
                    )
                }
            }
            .buttonStyle(.plain)

            if appliesListRowInsets {
                row.insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
            } else {
                row
            }
        } else {
            let row = HeroTapButton { frame in
                presentComic(comic, sourceFrame: frame)
            } label: {
                InsetListRowCard {
                    LibraryComicRow(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic),
                        trailingAccessoryReservedWidth: comicAccessoryReservedWidth
                    )
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                if showsPersistentComicActions {
                    persistentComicQuickActionsButton(for: comic)
                        .padding(.trailing, 8)
                }
            }
            .contextMenu {
                comicContextActions(for: comic)
            }

            if appliesListRowInsets && enablesSwipeActions {
                row
                    .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        comicReadSwipeAction(for: comic)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

                        Button(role: .destructive) {
                            viewModel.remove(comic)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
            } else if appliesListRowInsets {
                row.insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
            } else {
                row
            }
        }
    }

    @ViewBuilder
    private func gridComicCard(for comic: LibraryComic) -> some View {
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
            HeroTapButton { frame in
                presentComic(comic, sourceFrame: frame)
            } label: {
                LibraryComicCard(comic: comic, coverURL: viewModel.coverURL(for: comic))
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
    }

    private var canSelectComics: Bool {
        !viewModel.comics.isEmpty
    }

    private var canSortComics: Bool {
        !viewModel.comics.isEmpty
    }

    private var deletingCollectionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletingCollection != nil },
            set: { isPresented in
                if !isPresented {
                    deletingCollection = nil
                }
            }
        )
    }

    private var deletingCollectionDialogTitle: String {
        guard let deletingCollection else {
            return "Delete Collection"
        }

        return deleteCollectionActionTitle(for: deletingCollection)
    }

    private func deleteCollectionActionTitle(for collection: LibraryOrganizationCollection) -> String {
        switch collection.type {
        case .label:
            return "Delete Tag"
        case .readingList:
            return "Delete Reading List"
        }
    }

    private func deleteCollectionMessage(for collection: LibraryOrganizationCollection) -> String {
        switch collection.type {
        case .label:
            return "This removes the tag and its assignments from the library database."
        case .readingList:
            return "This removes the reading list and its assigned comics from the library database."
        }
    }

    private var hasSelectedComics: Bool {
        !selectedComicIDs.isEmpty
    }

    private var supportsGridDisplay: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularInlineActionMinWidth)
    }

    private func presentComic(_ comic: LibraryComic, sourceFrame: CGRect) {
        heroSourceFrame = sourceFrame
        presentedComic = PresentedComic(
            comic: comic,
            navigationContext: ReaderNavigationContext(
                title: viewModel.collection.displayTitle,
                comics: displayedComics
            )
        )
    }

    private var usesCondensedTopBarActions: Bool {
        !supportsGridDisplay
    }

    private var showsFilterControls: Bool {
        !viewModel.comics.isEmpty && !isSelectionMode
    }

    private var canResetFilters: Bool {
        hasActiveFilter
    }

    private var comicInfoImportTargetComics: [LibraryComic] {
        isSelectionMode ? selectedComics : displayedComics
    }

    private var comicInfoImportScope: BatchComicInfoImportScope {
        isSelectionMode ? .selected : .visible
    }

    private var canImportComicInfo: Bool {
        !comicInfoImportTargetComics.isEmpty
    }

    private var selectedComics: [LibraryComic] {
        displayedComics.filter { selectedComicIDs.contains($0.id) }
    }

    private var visibleComicIDs: [Int64] {
        displayedComics.map(\.id)
    }

    private var areAllVisibleComicsSelected: Bool {
        let visibleIDs = Set(visibleComicIDs)
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedComicIDs)
    }

    private var canAdjustDisplayMode: Bool {
        supportsGridDisplay && canSortComics
    }

    private func handleReaderComicUpdate(_ updatedComic: LibraryComic) {
        viewModel.applyUpdatedComic(updatedComic)
    }

    @ViewBuilder
    private var condensedTopBarActionsMenu: some View {
        Menu {
            collectionManagementMenuContent

            if canImportComicInfo || canSortComics {
                Divider()
            }

            if canImportComicInfo {
                Button {
                    isShowingComicInfoImportSheet = true
                } label: {
                    Label("Import ComicInfo", systemImage: "square.and.arrow.down")
                }
            }

            if canSortComics {
                Menu {
                    sortModeMenuContent
                } label: {
                    Label("Sort Comics", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More Collection Actions")
    }

    @ViewBuilder
    private var collectionManagementMenuContent: some View {
        Button {
            editingCollection = viewModel.collection
        } label: {
            Label(
                viewModel.collection.type == .label ? "Edit Tag" : "Edit Reading List",
                systemImage: "square.and.pencil"
            )
        }

        Button(role: .destructive) {
            deletingCollection = viewModel.collection
        } label: {
            Label(
                deleteCollectionActionTitle(for: viewModel.collection),
                systemImage: "trash"
            )
        }
    }

    @ViewBuilder
    private var displayModeMenuContent: some View {
        ForEach(LibraryComicDisplayMode.allCases) { mode in
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
        Self.persistSortMode(mode, for: viewModel.collection)
    }

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        preferredDisplayMode = mode
        displayMode = mode
        Self.persistDisplayMode(mode, for: viewModel.collection)
    }

    private static func sortModeStorageKey(for collection: LibraryOrganizationCollection) -> String {
        "libraryOrganizationCollectionSortMode.\(collection.type.rawValue).\(collection.id)"
    }

    private static func loadStoredSortMode(
        for collection: LibraryOrganizationCollection
    ) -> LibraryComicSortMode {
        let defaults = UserDefaults.standard
        let scopedKey = sortModeStorageKey(for: collection)

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

    private static func persistSortMode(
        _ mode: LibraryComicSortMode,
        for collection: LibraryOrganizationCollection
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: sortModeStorageKey(for: collection)
        )
    }

    private static func displayModeStorageKey(for collection: LibraryOrganizationCollection) -> String {
        "libraryOrganizationCollectionDisplayMode.\(collection.type.rawValue).\(collection.id)"
    }

    private static func loadStoredDisplayMode(
        for collection: LibraryOrganizationCollection
    ) -> LibraryComicDisplayMode {
        let defaults = UserDefaults.standard
        let storageKey = displayModeStorageKey(for: collection)

        if let rawValue = defaults.string(forKey: storageKey),
           let mode = LibraryComicDisplayMode(rawValue: rawValue) {
            return mode
        }

        return .grid
    }

    private static func persistDisplayMode(
        _ mode: LibraryComicDisplayMode,
        for collection: LibraryOrganizationCollection
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: displayModeStorageKey(for: collection)
        )
    }

    private var displayedComics: [LibraryComic] {
        viewModel.comics
            .sorted(using: comicSortMode)
            .filter { comic in
                comicFilter.matches(comic) && comic.matchesSearchQuery(searchQuery)
            }
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveFilter: Bool {
        comicFilter != .all || !trimmedSearchQuery.isEmpty
    }

    private var contentSectionTitle: String {
        hasActiveFilter ? "Results" : "Comics"
    }

    private var emptyStateTitle: String {
        hasActiveFilter ? "No Matching Comics" : viewModel.collection.sectionKind.detailEmptyStateTitle
    }

    private var emptyStateDescription: String {
        if !trimmedSearchQuery.isEmpty {
            return "No comics in \(viewModel.collection.displayTitle) matched \"\(trimmedSearchQuery)\"."
        }

        if comicFilter != .all {
            return "No comics in \(viewModel.collection.displayTitle) match the current \(comicFilter.title.lowercased()) filter."
        }

        return viewModel.collection.sectionKind.detailEmptyStateDescription
    }

    private var emptyStateSystemImage: String {
        if !trimmedSearchQuery.isEmpty {
            return "magnifyingglass"
        }

        return hasActiveFilter ? comicFilter.systemImageName : viewModel.collection.systemImageName
    }

    private func resetFilters() {
        comicFilter = .all
        searchQuery = ""
    }

    private var selectionSummaryText: String {
        let count = selectedComicIDs.count
        return count == 1 ? "1 selected" : "\(count) selected"
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

    private func performBatchRemoveAction() {
        if viewModel.removeComics(withIDs: Array(selectedComicIDs)) {
            endSelectionMode()
        }
    }

    private var comicGridColumns: [GridItem] {
        let widthRange = usesWideComicGridMetrics
            ? LayoutMetrics.regularGridMinWidth...LayoutMetrics.regularGridMaxWidth
            : LayoutMetrics.compactGridMinWidth...LayoutMetrics.compactGridMaxWidth
        return [
            GridItem(
                .adaptive(
                    minimum: widthRange.lowerBound,
                    maximum: widthRange.upperBound
                ),
                spacing: 16,
                alignment: .top
            )
        ]
    }

    private var usesWideComicGridMetrics: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= LayoutMetrics.wideGridMinContainerWidth)
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
}

private struct PresentedComic: Identifiable {
    let comic: LibraryComic
    let navigationContext: ReaderNavigationContext

    var id: Int64 { comic.id }
}

private enum PendingComicQuickAction {
    case edit(LibraryComic)
    case organize(LibraryComic)
    case remove(LibraryComic)
}
