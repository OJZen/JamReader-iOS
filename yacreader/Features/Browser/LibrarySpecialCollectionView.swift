import SwiftUI

struct LibrarySpecialCollectionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @AppStorage("libraryRecentWindowDays") private var recentWindowRawValue = LibraryRecentWindowOption.defaultOption.rawValue
    @StateObject private var viewModel: LibrarySpecialCollectionViewModel
    @State private var comicSortMode: LibraryComicSortMode
    @State private var preferredDisplayMode: LibraryComicDisplayMode
    @State private var displayMode: LibraryComicDisplayMode
    @State private var hasConfiguredPreferredDisplayMode = false
    @State private var searchQuery = ""
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

    init(
        descriptor: LibraryDescriptor,
        kind: LibrarySpecialCollectionKind,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _comicSortMode = State(initialValue: Self.loadStoredSortMode(for: kind))
        let storedDisplayMode = Self.loadStoredDisplayMode(for: kind)
        _preferredDisplayMode = State(initialValue: storedDisplayMode)
        _displayMode = State(initialValue: storedDisplayMode)
        _viewModel = StateObject(
            wrappedValue: LibrarySpecialCollectionViewModel(
                descriptor: descriptor,
                kind: kind,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager,
                coverLocator: dependencies.libraryCoverLocator
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading \(viewModel.kind.title)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentBody
            }
        }
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingBatchMetadataSheet = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(!hasSelectedComics)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingComicInfoImportSheet = true
                    } label: {
                        Image(systemName: "doc.badge.arrow.down")
                    }
                    .disabled(selectedComics.isEmpty)
                }
            }

            if canImportComicInfo && !isSelectionMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingComicInfoImportSheet = true
                    } label: {
                        Image(systemName: "doc.badge.arrow.down")
                    }
                }
            }

            if canAdjustRecentWindow && !isSelectionMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
            }

            if canSortComics && !isSelectionMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: displayMode.systemImageName)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
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
                    Menu {
                        Button {
                            performBatchReadAction(true)
                        } label: {
                            Label("Mark Read", systemImage: "checkmark.circle")
                        }

                        Button {
                            performBatchReadAction(false)
                        } label: {
                            Label("Mark Unread", systemImage: "arrow.uturn.backward.circle")
                        }
                    } label: {
                        Label("Read", systemImage: "checkmark.circle")
                    }
                    .disabled(!hasSelectedComics)
                }

                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button {
                            performBatchFavoriteAction(true)
                        } label: {
                            Label("Add Favorite", systemImage: "star")
                        }

                        Button {
                            performBatchFavoriteAction(false)
                        } label: {
                            Label("Remove Favorite", systemImage: "star.slash")
                        }
                    } label: {
                        Label("Favorite", systemImage: "star")
                    }
                    .disabled(!hasSelectedComics)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isShowingBatchOrganizationSheet = true
                    } label: {
                        Label("Organize", systemImage: "tag")
                    }
                    .disabled(!hasSelectedComics)
                }
            }
        }
        .task {
            viewModel.setRecentDays(recentWindowOption.dayCount)
            viewModel.loadIfNeeded()
        }
        .onAppear {
            configurePreferredDisplayModeIfNeeded()
            viewModel.setRecentDays(recentWindowOption.dayCount)
            viewModel.load()
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            adaptDisplayMode(to: newValue)
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
        .onChange(of: recentWindowRawValue) { _, _ in
            viewModel.setRecentDays(recentWindowOption.dayCount)
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

    private var listContent: some View {
        List {
            summarySection

            if displayedComics.isEmpty {
                Section {
                    emptyStateView
                }
            } else {
                Section("Comics") {
                    ForEach(displayedComics) { comic in
                        listComicRow(for: comic)
                    }
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard

                if displayedComics.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Comics")
                            .font(.headline)

                        LazyVGrid(columns: comicGridColumns, alignment: .leading, spacing: 16) {
                            ForEach(displayedComics) { comic in
                                gridComicCard(for: comic)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.kind.title)
                    .font(.headline)

                Text(kindSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !viewModel.comics.isEmpty, !isSelectionMode {
                    LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                        comicFilter = selectedFilter
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.kind.title)
                .font(.title3.weight(.semibold))

            Text(kindSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                StatusBadge(title: "\(displayedComics.count) comics", tint: .green)
                StatusBadge(title: comicSortMode.title, tint: .blue)
                if displayMode == .grid {
                    StatusBadge(title: "Grid", tint: .orange)
                }
                if comicFilter != .all {
                    StatusBadge(title: comicFilter.title, tint: .teal)
                }
            }

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.comics.isEmpty, !isSelectionMode {
                LibraryComicFilterBar(selection: comicFilter) { selectedFilter in
                    comicFilter = selectedFilter
                }
            }
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

    private var emptyStateView: some View {
        ContentUnavailableView(
            emptyStateTitle,
            systemImage: emptyStateSystemImage,
            description: Text(emptyStateDescription)
        )
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func listComicRow(for comic: LibraryComic) -> some View {
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
                        title: viewModel.kind.title,
                        comics: displayedComics
                    ),
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
            NavigationLink {
                ComicReaderView(
                    descriptor: viewModel.descriptor,
                    comic: comic,
                    navigationContext: ReaderNavigationContext(
                        title: viewModel.kind.title,
                        comics: displayedComics
                    ),
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

    private var canSelectComics: Bool {
        !viewModel.comics.isEmpty
    }

    private var canSortComics: Bool {
        !displayedComics.isEmpty
    }

    private var hasSelectedComics: Bool {
        !selectedComicIDs.isEmpty
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

    private var selectionSummaryText: String {
        let count = selectedComicIDs.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private var recentWindowOption: LibraryRecentWindowOption {
        LibraryRecentWindowOption(rawValue: recentWindowRawValue) ?? .defaultOption
    }

    private var canAdjustRecentWindow: Bool {
        viewModel.kind == .recent
    }

    private var kindSubtitle: String {
        viewModel.kind.subtitleText(recentDays: viewModel.currentRecentDays)
    }

    private func applySortMode(_ mode: LibraryComicSortMode) {
        comicSortMode = mode
        Self.persistSortMode(mode, for: viewModel.kind)
    }

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        preferredDisplayMode = mode
        displayMode = mode
        Self.persistDisplayMode(mode, for: viewModel.kind)
    }

    private static func sortModeStorageKey(for kind: LibrarySpecialCollectionKind) -> String {
        "librarySpecialCollectionSortMode.\(kind.rawValue)"
    }

    private static func defaultSortMode(for kind: LibrarySpecialCollectionKind) -> LibraryComicSortMode {
        switch kind {
        case .reading:
            return .recentlyOpened
        case .favorites:
            return .sourceOrder
        case .recent:
            return .recentlyAdded
        }
    }

    private static func loadStoredSortMode(for kind: LibrarySpecialCollectionKind) -> LibraryComicSortMode {
        let defaults = UserDefaults.standard
        let scopedKey = sortModeStorageKey(for: kind)

        if let rawValue = defaults.string(forKey: scopedKey),
           let mode = LibraryComicSortMode(rawValue: rawValue) {
            return mode
        }

        if let legacyRawValue = defaults.string(forKey: "libraryComicSortMode"),
           let legacyMode = LibraryComicSortMode(rawValue: legacyRawValue) {
            defaults.set(legacyMode.rawValue, forKey: scopedKey)
            return legacyMode
        }

        return defaultSortMode(for: kind)
    }

    private static func persistSortMode(
        _ mode: LibraryComicSortMode,
        for kind: LibrarySpecialCollectionKind
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: sortModeStorageKey(for: kind)
        )
    }

    private static func displayModeStorageKey(for kind: LibrarySpecialCollectionKind) -> String {
        "librarySpecialCollectionDisplayMode.\(kind.rawValue)"
    }

    private static func loadStoredDisplayMode(
        for kind: LibrarySpecialCollectionKind
    ) -> LibraryComicDisplayMode {
        let defaults = UserDefaults.standard
        let storageKey = displayModeStorageKey(for: kind)

        if let rawValue = defaults.string(forKey: storageKey),
           let mode = LibraryComicDisplayMode(rawValue: rawValue) {
            return mode
        }

        return .grid
    }

    private static func persistDisplayMode(
        _ mode: LibraryComicDisplayMode,
        for kind: LibrarySpecialCollectionKind
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: displayModeStorageKey(for: kind)
        )
    }

    private var displayedComics: [LibraryComic] {
        viewModel.comics
            .sorted(using: comicSortMode)
            .filter { comic in
                comicFilter.matches(comic) && comic.matchesSearchQuery(searchQuery)
            }
    }

    private var hasActiveFilter: Bool {
        comicFilter != .all || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var summaryText: String {
        guard hasActiveFilter else {
            return viewModel.summaryText
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return displayedComics.count == 1
                ? "1 comic matches \"\(query)\"."
                : "\(displayedComics.count) comics match \"\(query)\"."
        }

        return displayedComics.count == 1
            ? "1 comic is visible in \(comicFilter.title.lowercased())."
            : "\(displayedComics.count) comics are visible in \(comicFilter.title.lowercased())."
    }

    private var emptyStateTitle: String {
        hasActiveFilter ? "No Matching Comics" : viewModel.kind.emptyStateTitle
    }

    private var emptyStateDescription: String {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return "No comics in \(viewModel.kind.title) matched \"\(query)\"."
        }

        if comicFilter != .all {
            return "No comics in \(viewModel.kind.title) match the current \(comicFilter.title.lowercased()) filter."
        }

        return viewModel.kind.emptyStateDescriptionText(recentDays: viewModel.currentRecentDays)
    }

    private var emptyStateSystemImage: String {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }

        return hasActiveFilter ? comicFilter.systemImageName : viewModel.kind.systemImageName
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

    private var comicGridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: horizontalSizeClass == .regular ? 240 : 165,
                    maximum: horizontalSizeClass == .regular ? 320 : 220
                ),
                spacing: 16,
                alignment: .top
            )
        ]
    }

    private func configurePreferredDisplayModeIfNeeded() {
        guard !hasConfiguredPreferredDisplayMode else {
            return
        }

        hasConfiguredPreferredDisplayMode = true
        displayMode = horizontalSizeClass == .regular ? preferredDisplayMode : .list
    }

    private func adaptDisplayMode(to sizeClass: UserInterfaceSizeClass?) {
        if sizeClass == .regular {
            displayMode = preferredDisplayMode
        } else if sizeClass != .regular, displayMode == .grid {
            displayMode = .list
        }
    }
}

private enum PendingComicQuickAction {
    case edit(LibraryComic)
    case organize(LibraryComic)
}
