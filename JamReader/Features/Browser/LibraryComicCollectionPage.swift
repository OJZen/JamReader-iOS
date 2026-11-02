import SwiftUI
import UIKit

/// What a collection page (Favorites, Recently Added, a tag, a reading list)
/// needs from its view model.
@MainActor
protocol LibraryComicCollectionModel: ObservableObject {
    var descriptor: LibraryDescriptor { get }
    var comics: [LibraryComic] { get }
    var isLoading: Bool { get }
    var canRemoveComics: Bool { get }
    var alert: AppAlertState? { get set }

    func loadIfNeeded()
    func load()
    func applyUpdatedComic(_ updatedComic: LibraryComic)
    func toggleFavorite(for comic: LibraryComic)
    func toggleReadStatus(for comic: LibraryComic)
    func setRating(_ rating: Int, for comic: LibraryComic)
    func setReadStatus(_ isRead: Bool, for comicIDs: [Int64]) -> Bool
    func setFavorite(_ isFavorite: Bool, for comicIDs: [Int64]) -> Bool
    func deleteComicFromLibrary(_ comic: LibraryComic) -> Bool
    func coverURL(for comic: LibraryComic) -> URL?
    func coverSource(for comic: LibraryComic) -> LocalComicCoverSource?
    func heroSourceID(for comic: LibraryComic) -> String
    func cachedTransitionImage(for comic: LibraryComic) -> UIImage?
}

extension LibrarySpecialCollectionViewModel: LibraryComicCollectionModel {
    func deleteComicFromLibrary(_ comic: LibraryComic) -> Bool {
        removeComic(comic)
    }
}

extension LibraryOrganizationCollectionDetailViewModel: LibraryComicCollectionModel {
    func deleteComicFromLibrary(_ comic: LibraryComic) -> Bool {
        removeComicFromLibrary(comic)
    }
}

/// Removes comics from the current tag or reading list; the files stay.
struct LibraryCollectionMembershipRemoval {
    let title: String
    let removeOne: (LibraryComic) -> Void
    let removeMany: ([Int64]) -> Bool
}

/// The one layout for collection pages: same grid, list, actions and selection
/// as the library page. See docs/design-system/components/ScreenCollections.
struct LibraryComicCollectionPage<Model: LibraryComicCollectionModel, MenuContent: View>: View {
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject var model: Model
    let dependencies: AppDependencies
    let title: String
    let subtitle: String
    let emptyStateSystemImage: String
    let emptyStateTitle: String
    let emptyStateDescription: String
    let sortStorageKey: String
    let displayStorageKey: String
    let defaultSortMode: LibraryComicSortMode
    var membershipRemoval: LibraryCollectionMembershipRemoval?
    /// Off for the in-library Continue Reading page, which is already "In Progress".
    var showsQuickFilters = true
    /// Page-specific items placed first in the More menu.
    @ViewBuilder let pageMenuContent: () -> MenuContent

    @State private var comicSortMode: LibraryComicSortMode = .sourceOrder
    @State private var displayMode: LibraryComicDisplayMode = .grid
    @State private var hasLoadedPreferences = false
    @State private var searchQuery = ""
    @State private var quickFilter: LibraryComicQuickFilter = .all
    @State private var editingComic: LibraryComic?
    @State private var organizingComic: LibraryComic?
    @State private var deletingComic: LibraryComic?
    @State private var isConfirmingSelectionDeletion = false
    @State private var isSelectionMode = false
    @State private var selectedComicIDs = Set<Int64>()

    var body: some View {
        Group {
            if model.isLoading && model.comics.isEmpty {
                LoadingStateView(message: String(localized: "Loading \(title)"))
            } else if displayMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .background(Color.surfacePrimary)
        .navigationTitle(isSelectionMode ? selectionTitle : title)
        .navigationBarTitleDisplayMode(isSelectionMode ? .inline : .large)
        .toolbar {
            if isSelectionMode {
                selectionToolbar
            } else {
                browsingToolbar
            }
        }
        .systemTabBarHidden(isSelectionMode)
        .prefersToolbarItemsWhenCompressed(isSelectionMode)
        .searchable(
            text: $searchQuery,
            prompt: Text("Search in “\(title)”")
        )
        .task {
            loadPreferencesIfNeeded()
            model.loadIfNeeded()
        }
        .onAppear {
            loadPreferencesIfNeeded()
            model.load()
        }
        .onChange(of: displayedComics.map(\.id)) { _, visibleComicIDs in
            let visibleIDs = Set(visibleComicIDs)
            selectedComicIDs = selectedComicIDs.intersection(visibleIDs)
            if isSelectionMode && visibleIDs.isEmpty {
                endSelectionMode()
            }
        }
        .onChange(of: searchQuery) { _, _ in
            if isSelectionMode {
                endSelectionMode()
            }
        }
        .onChange(of: editingComic?.id) { _, _ in
            presentEditingComicSheetIfNeeded()
        }
        .onChange(of: organizingComic?.id) { _, _ in
            presentOrganizingComicSheetIfNeeded()
        }
        .refreshable {
            model.load()
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .libraryComicDeletionConfirmation(
            $deletingComic,
            libraryKind: model.descriptor.kind
        ) { comic in
            _ = model.deleteComicFromLibrary(comic)
        }
        .confirmationDialog(
            selectedComicIDs.count == 1
                ? String(localized: "Delete 1 Comic?")
                : String(localized: "Delete \(selectedComicIDs.count) Comics?"),
            isPresented: $isConfirmingSelectionDeletion,
            titleVisibility: .visible
        ) {
            Button(
                selectedComicIDs.count == 1
                    ? String(localized: "Delete 1 Comic")
                    : String(localized: "Delete \(selectedComicIDs.count) Comics"),
                role: .destructive
            ) {
                deleteSelectedComics()
            }
        } message: {
            Text(LibraryComicDeletionCopy.message(for: model.descriptor.kind, count: selectedComicIDs.count))
        }
    }

    // MARK: - Content

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                header

                if displayedComics.isEmpty {
                    emptyStateView
                        .padding(.vertical, Spacing.xxl)
                } else {
                    LazyVGrid(columns: coverGridColumns, alignment: .leading, spacing: Spacing.lg) {
                        ForEach(displayedComics) { comic in
                            gridItem(comic)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .containerHorizontalMargins()
            .adaptiveContentWidth(1180)
        }
    }

    private var listContent: some View {
        List {
            Section {
                header
                    .listRowSeparator(.hidden)
            }

            if displayedComics.isEmpty {
                emptyStateView
                    .padding(.vertical, Spacing.xl)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(displayedComics) { comic in
                        listRow(comic)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(subtitle)
                .font(AppFont.subheadline().monospacedDigit())
                .foregroundStyle(Color.textSecondary)

            if showsQuickFilters, !model.comics.isEmpty {
                LibraryComicFilterBar(selection: quickFilter) { filter in
                    quickFilter = filter
                }
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        // An empty collection hides the filter bar, so it keeps its own empty state.
        if !model.comics.isEmpty, let copy = LibraryCollectionFilterCopy.emptyResult(
            collectionTitle: title,
            filter: quickFilter,
            searchQuery: trimmedSearchQuery
        ) {
            EmptyStateView(
                systemImage: copy.searchesText ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                title: copy.title,
                description: copy.description,
                actionTitle: quickFilter == .all ? nil : String(localized: "Show All"),
                action: quickFilter == .all ? nil : { quickFilter = .all }
            )
        } else {
            EmptyStateView(
                systemImage: emptyStateSystemImage,
                title: emptyStateTitle,
                description: emptyStateDescription
            )
        }
    }

    @ViewBuilder
    private func gridItem(_ comic: LibraryComic) -> some View {
        if isSelectionMode {
            Button {
                toggleSelection(for: comic)
            } label: {
                LibraryComicCard(
                    comic: comic,
                    coverURL: model.coverURL(for: comic),
                    coverSource: model.coverSource(for: comic),
                    showsSelectionState: true,
                    isSelected: selectedComicIDs.contains(comic.id)
                )
                .equatable()
            }
            .buttonStyle(.plain)
        } else {
            HeroTapButton { frame in
                presentComic(comic, sourceFrame: frame)
            } label: {
                LibraryComicCard(
                    comic: comic,
                    coverURL: model.coverURL(for: comic),
                    coverSource: model.coverSource(for: comic),
                    heroSourceID: model.heroSourceID(for: comic)
                )
                .equatable()
            }
            .buttonStyle(.plain)
            .contextMenu {
                LibraryComicMenuContent(comic: comic, actions: comicActions)
            }
        }
    }

    @ViewBuilder
    private func listRow(_ comic: LibraryComic) -> some View {
        if isSelectionMode {
            Button {
                toggleSelection(for: comic)
            } label: {
                LibraryComicRow(
                    comic: comic,
                    coverURL: model.coverURL(for: comic),
                    coverSource: model.coverSource(for: comic),
                    showsSelectionState: true,
                    isSelected: selectedComicIDs.contains(comic.id)
                )
                .equatable()
            }
            .buttonStyle(.plain)
        } else {
            HeroTapButton { frame in
                presentComic(comic, sourceFrame: frame)
            } label: {
                LibraryComicRow(
                    comic: comic,
                    coverURL: model.coverURL(for: comic),
                    coverSource: model.coverSource(for: comic),
                    heroSourceID: model.heroSourceID(for: comic),
                    trailingAccessoryReservedWidth: 44
                )
                .equatable()
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                LibraryComicMoreButton(comic: comic, actions: comicActions)
            }
            .contextMenu {
                LibraryComicMenuContent(comic: comic, actions: comicActions)
            }
            .libraryComicSwipeActions(for: comic, actions: comicActions)
        }
    }

    private var coverGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(
                repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top),
                count: 2
            )
        }

        let minimumWidth = horizontalSizeClass == .regular
            ? AppLayout.gridItemMinWidth
            : AppLayout.gridItemMinWidthCompact
        return [
            GridItem(
                .adaptive(minimum: minimumWidth, maximum: AppLayout.gridItemMaxWidth),
                spacing: Spacing.sm,
                alignment: .top
            )
        ]
    }

    private var comicActions: LibraryComicActions {
        LibraryComicActions(
            toggleFavorite: { model.toggleFavorite(for: $0) },
            toggleRead: { model.toggleReadStatus(for: $0) },
            organize: { organizingComic = $0 },
            setRating: { rating, comic in model.setRating(rating, for: comic) },
            editMetadata: { editingComic = $0 },
            showInfo: presentInfoSheet,
            removeFromCollection: membershipRemoval?.removeOne,
            removeFromCollectionTitle: membershipRemoval?.title,
            delete: model.canRemoveComics ? { deletingComic = $0 } : nil
        )
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var browsingToolbar: some ToolbarContent {
        if !displayedComics.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSelectionMode = true
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .barButtonTextBeforeSideBars()
            }
        }

        PageOverflowMenu {
                pageMenuContent()

                Section {
                    Picker("View As", selection: displayModeBinding) {
                        ForEach(LibraryComicDisplayMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImageName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.palette)

                    Picker(selection: sortModeBinding) {
                        ForEach(LibraryComicSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        Label("Sort Comics", systemImage: "arrow.up.arrow.down")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button {
                        presentComicInfoImportSheet()
                    } label: {
                        Label("Import Comic Info…", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(displayedComics.isEmpty)
                }
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                toggleSelectAllVisibleComics()
            } label: {
                Label(
                    areAllVisibleComicsSelected ? "Deselect All" : "Select All",
                    systemImage: areAllVisibleComicsSelected ? "circle.dashed" : "checkmark.circle.fill"
                )
            }
            .labelStyle(.titleOnly)
        }
        .staysInHorizontalBar()

        ToolbarItem(placement: .confirmationAction) {
            Button {
                endSelectionMode()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .barButtonTextBeforeSideBars()
            // The bar fills this button; fills use jam, not the brighter dark-mode accent.
            .tint(.appJam)
        }
        .keepsVisibleLongest()

        // One centered group of actions, as in components/SelectionBar.
        ToolbarItemGroup(placement: .bottomBar) {
            Spacer()

            Button {
                performBatchAction { model.setReadStatus(!allSelectedAreRead, for: $0) }
            } label: {
                Label(
                    allSelectedAreRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: allSelectedAreRead ? "circle" : "checkmark.circle"
                )
            }
            .tint(.appAccent)
            .disabled(selectedComicIDs.isEmpty)

            Button {
                performBatchAction { model.setFavorite(!allSelectedAreFavorites, for: $0) }
            } label: {
                Label(
                    allSelectedAreFavorites ? "Unfavorite" : "Favorite",
                    systemImage: allSelectedAreFavorites ? "star.slash" : "star"
                )
            }
            .tint(.appAccent)
            .disabled(selectedComicIDs.isEmpty)

            Button {
                presentBatchOrganizationSheet()
            } label: {
                Label("Tags & Lists", systemImage: "tag")
            }
            .tint(.appAccent)
            .disabled(selectedComicIDs.isEmpty)

            // From iOS 27.1 these join the system overflow menu (below).
            if #available(iOS 27.1, *) {
                EmptyView()
            } else {
                Menu {
                    selectionMoreMenuItems
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .tint(.appAccent)
                .disabled(selectedComicIDs.isEmpty)
            }

            if model.canRemoveComics {
                Button(role: .destructive) {
                    isConfirmingSelectionDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.appDanger)
                .disabled(selectedComicIDs.isEmpty)
            }

            Spacer()
        }

        if #available(iOS 27.1, *) {
            ToolbarOverflowMenu {
                selectionMoreMenuItems
                    .disabled(selectedComicIDs.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var selectionMoreMenuItems: some View {
        Button {
            presentBatchMetadataSheet()
        } label: {
            Label("Edit Metadata", systemImage: "square.and.pencil")
        }

        Button {
            presentComicInfoImportSheet()
        } label: {
            Label("Import Comic Info…", systemImage: "doc.text.magnifyingglass")
        }

        if let membershipRemoval {
            Button {
                performBatchAction(membershipRemoval.removeMany)
            } label: {
                Label(membershipRemoval.title, systemImage: "minus.circle")
            }
        }
    }

    // MARK: - State

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedComics: [LibraryComic] {
        LibraryCollectionFilterCopy.displayedComics(
            model.comics.sorted(using: comicSortMode),
            filter: showsQuickFilters ? quickFilter : .all,
            searchQuery: searchQuery
        )
    }

    private var selectedComics: [LibraryComic] {
        displayedComics.filter { selectedComicIDs.contains($0.id) }
    }

    private var allSelectedAreRead: Bool {
        !selectedComics.isEmpty && selectedComics.allSatisfy(\.read)
    }

    private var allSelectedAreFavorites: Bool {
        !selectedComics.isEmpty && selectedComics.allSatisfy(\.isFavorite)
    }

    private var areAllVisibleComicsSelected: Bool {
        let visibleIDs = Set(displayedComics.map(\.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedComicIDs)
    }

    private var selectionTitle: String {
        selectedComicIDs.count == 1
            ? String(localized: "1 Selected")
            : String(localized: "\(selectedComicIDs.count) Selected")
    }

    private var sortModeBinding: Binding<LibraryComicSortMode> {
        Binding(
            get: { comicSortMode },
            set: { mode in
                comicSortMode = mode
                UserDefaults.standard.set(mode.rawValue, forKey: sortStorageKey)
            }
        )
    }

    private var displayModeBinding: Binding<LibraryComicDisplayMode> {
        Binding(
            get: { displayMode },
            set: { mode in
                displayMode = mode
                UserDefaults.standard.set(mode.rawValue, forKey: displayStorageKey)
            }
        )
    }

    private func loadPreferencesIfNeeded() {
        guard !hasLoadedPreferences else {
            return
        }

        hasLoadedPreferences = true
        let defaults = UserDefaults.standard
        comicSortMode = defaults.string(forKey: sortStorageKey)
            .flatMap(LibraryComicSortMode.init(rawValue:)) ?? defaultSortMode
        displayMode = defaults.string(forKey: displayStorageKey)
            .flatMap(LibraryComicDisplayMode.init(rawValue:)) ?? .grid
    }

    // MARK: - Actions

    private func presentComic(_ comic: LibraryComic, sourceFrame: CGRect) {
        let heroSourceID = model.heroSourceID(for: comic)
        let registeredFrame = HeroSourceRegistry.shared.frame(for: heroSourceID)
        let effectiveSourceFrame = registeredFrame == .zero ? sourceFrame : registeredFrame
        let previewImage = LocalCoverTransitionCache.shared.image(for: heroSourceID)
            ?? model.cachedTransitionImage(for: comic)

        appPresenter?.presentReader(
            .local(
                LocalReaderPresentation(
                    descriptor: model.descriptor,
                    comic: comic,
                    navigationContext: ReaderNavigationContext(title: title, comics: displayedComics),
                    heroSourceID: heroSourceID,
                    sourceFrame: effectiveSourceFrame,
                    previewImage: previewImage,
                    onComicUpdated: { model.applyUpdatedComic($0) },
                    onDismiss: nil
                )
            )
        )
    }

    private func presentInfoSheet(for comic: LibraryComic) {
        appPresenter?.presentSheet(
            .content(
                id: "library.collection.info.\(comic.id)",
                content: AnyView(
                    LibraryComicInfoSheet(
                        comic: comic,
                        libraryName: model.descriptor.displayName,
                        coverURL: model.coverURL(for: comic),
                        coverSource: model.coverSource(for: comic)
                    )
                )
            )
        )
    }

    private func presentEditingComicSheetIfNeeded() {
        guard let comic = editingComic else {
            return
        }

        appPresenter?.presentSheet(
            .content(
                id: "library.collection.edit.\(comic.id)",
                content: AnyView(
                    ComicMetadataEditorSheet(
                        descriptor: model.descriptor,
                        comic: comic,
                        dependencies: dependencies,
                        coverURL: model.coverURL(for: comic),
                        coverSource: model.coverSource(for: comic)
                    ) { updatedComic in
                        model.applyUpdatedComic(updatedComic)
                    }
                ),
                onDismiss: {
                    editingComic = nil
                }
            )
        )
    }

    private func presentOrganizingComicSheetIfNeeded() {
        guard let comic = organizingComic else {
            return
        }

        appPresenter?.presentSheet(
            .content(
                id: "library.collection.organize.\(comic.id)",
                content: AnyView(
                    ComicOrganizationSheet(
                        descriptor: model.descriptor,
                        comic: comic,
                        dependencies: dependencies
                    )
                ),
                onDismiss: {
                    organizingComic = nil
                    model.load()
                }
            )
        )
    }

    private func presentBatchMetadataSheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.collection.batchMetadata.\(selectedComicIDs.sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicMetadataSheet(
                        descriptor: model.descriptor,
                        comicIDs: Array(selectedComicIDs),
                        dependencies: dependencies
                    ) {
                        endSelectionMode()
                        model.load()
                    }
                )
            )
        )
    }

    private func presentComicInfoImportSheet() {
        let comics = isSelectionMode ? selectedComics : displayedComics
        appPresenter?.presentSheet(
            .content(
                id: "library.collection.infoImport.\(comics.map(\.id).sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicInfoImportSheet(
                        descriptor: model.descriptor,
                        comics: comics,
                        scope: isSelectionMode ? .selected : .visible,
                        dependencies: dependencies
                    ) { result in
                        model.load()
                        if isSelectionMode {
                            endSelectionMode()
                        }
                        model.alert = AppAlertState(
                            title: result.alertTitle,
                            message: result.alertMessage
                        )
                    }
                )
            )
        )
    }

    private func presentBatchOrganizationSheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.collection.batchOrganization.\(selectedComicIDs.sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicOrganizationSheet(
                        descriptor: model.descriptor,
                        comicIDs: Array(selectedComicIDs),
                        dependencies: dependencies
                    ) {
                        endSelectionMode()
                        model.load()
                    }
                )
            )
        )
    }

    private func toggleSelection(for comic: LibraryComic) {
        AppHaptics.selection()
        if selectedComicIDs.contains(comic.id) {
            selectedComicIDs.remove(comic.id)
        } else {
            selectedComicIDs.insert(comic.id)
        }
    }

    private func toggleSelectAllVisibleComics() {
        let visibleIDs = Set(displayedComics.map(\.id))
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

    private func performBatchAction(_ action: ([Int64]) -> Bool) {
        if action(Array(selectedComicIDs)) {
            endSelectionMode()
        }
    }

    private func deleteSelectedComics() {
        var deletedAll = true
        for comic in selectedComics where !model.deleteComicFromLibrary(comic) {
            deletedAll = false
            break
        }
        if deletedAll {
            endSelectionMode()
        }
        model.load()
    }

    private func endSelectionMode() {
        isSelectionMode = false
        isConfirmingSelectionDeletion = false
        selectedComicIDs.removeAll()
    }
}

/// Quick filter + search on a collection page, and the empty result that
/// names both conditions. See docs/design-system/components/FilterChips.
enum LibraryCollectionFilterCopy {
    struct EmptyResult: Equatable {
        let title: String
        let description: String
        let searchesText: Bool
    }

    static func displayedComics(
        _ comics: [LibraryComic],
        filter: LibraryComicQuickFilter,
        searchQuery: String
    ) -> [LibraryComic] {
        comics
            .filter(filter.matches)
            .filter { $0.matchesSearchQuery(searchQuery) }
    }

    /// `nil` when neither a filter nor a search is active: the collection is empty.
    static func emptyResult(
        collectionTitle: String,
        filter: LibraryComicQuickFilter,
        searchQuery: String
    ) -> EmptyResult? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (filter, query.isEmpty) {
        case (.all, true):
            return nil
        case (.all, false):
            return EmptyResult(
                title: String(localized: "No Matching Comics"),
                description: String(localized: "No comics in “\(collectionTitle)” match “\(query)”."),
                searchesText: true
            )
        case (_, true):
            return EmptyResult(
                title: String(localized: "No Matching Comics"),
                description: String(localized: "No “\(filter.title)” comics in “\(collectionTitle)”."),
                searchesText: false
            )
        case (_, false):
            return EmptyResult(
                title: String(localized: "No Matching Comics"),
                description: String(localized: "No “\(filter.title)” comics in “\(collectionTitle)” match “\(query)”."),
                searchesText: true
            )
        }
    }
}
