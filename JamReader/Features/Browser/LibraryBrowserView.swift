import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Library contents: folders and comics, the same toolbar at every level.
/// See docs/design-system/components/ScreenLibraryContent.
struct LibraryBrowserView: View {
    private enum ImportHereRoute {
        case files
        case folder

        var contentTypes: [UTType] {
            switch self {
            case .files:
                return [.data]
            case .folder:
                return [.folder]
            }
        }
    }

    @Environment(SplitLayoutState.self) private var splitLayout: SplitLayoutState?
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.libraryListViewModel) private var libraryListViewModel

    private let dependencies: AppDependencies

    @AppStorage(LibraryPreferencesStore.recentWindowStorageKey) private var recentWindowRawValue = LibraryRecentWindowOption.defaultOption.rawValue
    @AppStorage(LibraryPreferencesStore.continueReadingPlacementStorageKey)
    private var continueReadingPlacementRawValue = ContinueReadingPlacement.defaultValue.rawValue
    @StateObject private var viewModel: LibraryBrowserViewModel
    @State private var comicSortMode: LibraryComicSortMode
    @State private var displayMode: LibraryBrowserDisplayMode
    @State private var quickFilter: LibraryComicQuickFilter = .all
    @State private var foldGridMetrics: FoldSplitGridMetrics?
    @State private var editingComic: LibraryComic?
    @State private var organizingComic: LibraryComic?
    @State private var deletingComic: LibraryComic?
    @State private var isConfirmingSelectionDeletion = false
    @State private var isSelectionMode = false
    @State private var selectedComicIDs = Set<Int64>()
    @State private var activeImportPicker: ImportHereRoute?
    /// Kept apart from the picker binding, which iOS 27 clears before the completion runs.
    @State private var presentedImportPicker: ImportHereRoute?

    init(
        descriptor: LibraryDescriptor,
        folderID: Int64 = 1,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _comicSortMode = State(initialValue: Self.loadStoredSortMode())
        _displayMode = State(initialValue: Self.loadStoredDisplayMode())
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
                comicRemovalService: dependencies.libraryComicRemovalService,
                remoteBackgroundImportController: dependencies.remoteBackgroundImportController
            )
        )
    }

    var body: some View {
        rootContent
            .background(Color.surfacePrimary)
            .taskBanner {
                taskBanner
            }
            .navigationTitle(isSelectionMode ? selectionTitle : viewModel.navigationTitle)
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
                text: $viewModel.searchQuery,
                    prompt: Text("Search in “\(viewModel.descriptor.displayName)”")
            )
            .task {
                viewModel.setRecentDays(recentWindowOption.dayCount)
                viewModel.loadIfNeeded()
            }
            .onAppear {
                viewModel.takePendingTaskResult()
                viewModel.setRecentDays(recentWindowOption.dayCount)
                viewModel.refreshIfLoaded()
                if let currentFolderID = viewModel.content?.folder.id {
                    Self.persistLastOpenedFolderID(currentFolderID, for: viewModel.descriptor.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: LibraryTaskResultInbox.didReceiveResult)) { notification in
                if notification.object as? UUID == viewModel.descriptor.id {
                    viewModel.takePendingTaskResult()
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
            .onChange(of: visibleComicIDs) { _, visibleComicIDs in
                let visibleIDs = Set(visibleComicIDs)
                selectedComicIDs = selectedComicIDs.intersection(visibleIDs)

                if isSelectionMode && visibleIDs.isEmpty {
                    endSelectionMode()
                }
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
            .background {
                presentationObservers
            }
            .fileImporter(
                isPresented: Binding(
                    get: { activeImportPicker != nil },
                    set: { isPresented in
                        if !isPresented {
                            activeImportPicker = nil
                        }
                    }
                ),
                allowedContentTypes: presentedImportPicker?.contentTypes ?? [.data],
                allowsMultipleSelection: true
            ) { result in
                let route = presentedImportPicker
                presentedImportPicker = nil
                handleImportHere(result, route: route)
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .libraryComicDeletionConfirmation(
                $deletingComic,
                libraryKind: viewModel.descriptor.kind
            ) { comic in
                _ = viewModel.removeComic(comic)
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
                    if viewModel.removeComics(selectedComics) {
                        endSelectionMode()
                    }
                }
            } message: {
                Text(LibraryComicDeletionCopy.message(for: viewModel.descriptor.kind, count: selectedComicIDs.count))
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var rootContent: some View {
        if viewModel.hasActiveSearch {
            searchResultsView
        } else if let content = viewModel.content {
            if displayMode == .grid {
                gridContentView(content)
            } else {
                listContentView(content)
            }
        } else if viewModel.isLoading || viewModel.isInitializingLibrary || viewModel.isRefreshingLibrary {
            ProgressView(progressMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.lg) {
                EmptyStateView(
                    systemImage: viewModel.canInitializeLibrary ? "books.vertical.circle" : "externaldrive.badge.exclamationmark",
                    title: viewModel.canInitializeLibrary
                        ? String(localized: "Library Not Initialized")
                        : String(localized: "Library Unavailable"),
                    description: viewModel.emptyStateMessage
                        ?? String(localized: "The selected library could not be loaded.")
                )

                if viewModel.canInitializeLibrary {
                    Button {
                        viewModel.initializeLibrary()
                    } label: {
                        Label("Initialize Library", systemImage: "sparkles.rectangle.stack")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appJam)

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

    private func gridContentView(_ content: LibraryFolderContent) -> some View {
        let displayedComics = filteredComics(content.comics)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                locationHeader(content)

                if content.folder.isRoot, !isSelectionMode {
                    if showsCollectionsGrid {
                        collectionsGrid
                    }
                    continueReadingSection
                }

                if content.subfolders.isEmpty, content.comics.isEmpty {
                    emptyFolderView
                        .padding(.vertical, Spacing.xxl)
                } else {
                    if !content.subfolders.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            sectionHeader(String(localized: "Folders"), count: content.subfolders.count)
                            LazyVGrid(columns: coverGridColumns, alignment: .leading, spacing: Spacing.lg) {
                                ForEach(content.subfolders) { folder in
                                    Button {
                                        openFolder(folder.id)
                                    } label: {
                                        LibraryFolderCard(
                                            folder: folder,
                                            coverURL: viewModel.coverURL(for: folder),
                                            previewCoverURLs: viewModel.previewCoverURLs(for: folder)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSelectionMode)
                                }
                            }
                            .padding(.leading, foldGridLeadingOffset)
                        }
                    }

                    if !content.comics.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            comicsSectionHeader(count: displayedComics.count)
                            quickFilterBar
                            if displayedComics.isEmpty {
                                filteredEmptyView
                            } else {
                                LazyVGrid(columns: coverGridColumns, alignment: .leading, spacing: Spacing.lg) {
                                    ForEach(displayedComics) { comic in
                                        comicGridItem(
                                            comic,
                                            context: ReaderNavigationContext(
                                                title: content.folder.displayName,
                                                comics: displayedComics
                                            )
                                        )
                                    }
                                }
                                .padding(.leading, foldGridLeadingOffset)
                            }
                        }
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateFoldGridMetrics(proxy) }
                        .onChange(of: proxy.size) { _, _ in updateFoldGridMetrics(proxy) }
                }
            }
            .padding(.vertical, Spacing.xs)
            .containerHorizontalMargins()
            .adaptiveContentWidth(1180)
        }
    }

    private var foldGridLeadingOffset: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0 : (foldGridMetrics?.columnOrigins.first ?? 0)
    }

    /// iPhone Duo: a vertical fold across the grid (sidebar hidden) gets even
    /// columns with the middle gutter on the fold.
    private func updateFoldGridMetrics(_ proxy: GeometryProxy) {
        guard #available(iOS 27.1, *) else {
            return
        }

        let fold = proxy.reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width }
        let minimumWidth = horizontalSizeClass == .regular
            ? AppLayout.gridItemMinWidth
            : AppLayout.gridItemMinWidthCompact
        let metrics = fold.flatMap { fold in
            FoldSplitGridMetrics.make(
                containerWidth: proxy.size.width,
                leadingInset: 0,
                trailingInset: 0,
                foldMinX: fold.minX,
                foldMaxX: fold.maxX,
                minimumItemWidth: minimumWidth,
                maximumItemWidth: AppLayout.gridItemMaxWidth,
                spacing: Spacing.sm
            )
        }
        if metrics != foldGridMetrics {
            foldGridMetrics = metrics
        }
    }

    private func listContentView(_ content: LibraryFolderContent) -> some View {
        let displayedComics = filteredComics(content.comics)

        return List {
            Section {
                locationHeader(content)
                    .listRowSeparator(.hidden)

                if content.folder.isRoot, !isSelectionMode {
                    if showsCollectionsGrid {
                        collectionsGrid
                            .listRowSeparator(.hidden)
                    }
                    continueReadingSection
                        .listRowSeparator(.hidden)
                }
            }

            if content.subfolders.isEmpty, content.comics.isEmpty {
                emptyFolderView
                    .padding(.vertical, Spacing.xl)
                    .listRowSeparator(.hidden)
            } else {
                if !content.subfolders.isEmpty {
                    Section {
                        ForEach(content.subfolders) { folder in
                            folderListRow(folder)
                        }
                    } header: {
                        sectionHeader(String(localized: "Folders"), count: content.subfolders.count)
                    }
                }

                if !content.comics.isEmpty {
                    Section {
                        quickFilterBar
                            .listRowSeparator(.hidden)
                        if displayedComics.isEmpty {
                            filteredEmptyView
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(displayedComics) { comic in
                                comicListRow(
                                    comic,
                                    context: ReaderNavigationContext(
                                        title: content.folder.displayName,
                                        comics: displayedComics
                                    )
                                )
                            }
                        }
                    } header: {
                        comicsSectionHeader(count: displayedComics.count)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// Library totals under the root title; a tappable breadcrumb in subfolders.
    @ViewBuilder
    private func locationHeader(_ content: LibraryFolderContent) -> some View {
        if content.folder.isRoot {
            Text(librarySummaryText)
                .font(AppFont.subheadline().monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        } else {
            LibraryBreadcrumb(
                libraryName: viewModel.descriptor.displayName,
                ancestors: content.ancestors,
                current: content.folder,
                onSelectFolder: { folderID in
                    appNavigator?.navigate(
                        .library(.openAncestorFolder(viewModel.descriptor, folderID: folderID))
                    )
                }
            )
        }
    }

    private var librarySummaryText: String {
        let summary = viewModel.databaseSummary
        let comics = summary.comicCount == 1
            ? String(localized: "1 comic")
            : String(localized: "\(summary.comicCount) comics")
        let folders = summary.folderCount == 1
            ? String(localized: "1 folder")
            : String(localized: "\(summary.folderCount) folders")
        return "\(comics) · \(folders)"
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.title2(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("\(count)")
                .font(AppFont.subheadline().monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Comics" header with the sort menu on the right.
    private func comicsSectionHeader(count: Int) -> some View {
        // Large text puts the sort menu under the title instead of breaking words.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            sectionHeader(String(localized: "Comics"), count: count)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Spacing.sm)
            }

            Menu {
                Picker("Sort Comics", selection: sortModeBinding) {
                    ForEach(LibraryComicSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label(comicSortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel(Text("Sort Comics"))
            .accessibilityValue(Text(comicSortMode.title))
        }
        .textCase(nil)
    }

    private var quickFilterBar: some View {
        LibraryComicFilterBar(selection: quickFilter) { filter in
            quickFilter = filter
        }
    }

    private var filteredEmptyView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No comics in this folder match “\(quickFilter.title)”.")
                .font(AppFont.subheadline())
                .foregroundStyle(Color.textSecondary)
            Button("Show All") {
                quickFilter = .all
            }
            .font(AppFont.subheadline(.semibold))
            .foregroundStyle(Color.appAccent)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Spacing.sm)
    }

    private var emptyFolderView: some View {
        ContentUnavailableView {
            Label("Empty Folder", systemImage: "folder")
        } description: {
            Text("This folder doesn’t contain comics or subfolders yet.")
        } actions: {
            if canImportComicFiles {
                Menu {
                    importHereMenuItems
                } label: {
                    Label("Import Here", systemImage: "square.and.arrow.down")
                        .font(AppFont.body(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appJam)
            }
        }
    }

    private var coverGridColumns: [GridItem] {
        if let foldGridMetrics, !dynamicTypeSize.isAccessibilitySize {
            let middle = foldGridMetrics.columns / 2 - 1
            return (0..<foldGridMetrics.columns).map { index in
                GridItem(
                    .fixed(foldGridMetrics.itemWidth),
                    spacing: index == middle ? foldGridMetrics.centerGutter : Spacing.sm,
                    alignment: .top
                )
            }
        }

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

    // MARK: - Collections and continue reading

    private var collectionItems: [LibraryShortcutCardItem] {
        [
            specialCollectionItem(for: .favorites),
            specialCollectionItem(for: .recent),
            organizationItem(for: .labels),
            organizationItem(for: .readingLists)
        ]
    }

    /// The sidebar lists the collections while it is on screen.
    private var showsCollectionsGrid: Bool {
        !(splitLayout?.isSidebarVisible ?? false)
    }

    /// 2×2 collection entries on the library root.
    /// Four cards, so a non-lazy grid; a lazy one misplaces cards inside a list row.
    private var collectionsGrid: some View {
        let items = collectionItems
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Grid(horizontalSpacing: Spacing.xs, verticalSpacing: Spacing.xs) {
            ForEach(Array(stride(from: 0, to: items.count, by: columnCount)), id: \.self) { start in
                GridRow {
                    ForEach(items[start..<min(start + columnCount, items.count)]) { item in
                        Button {
                            if let route = item.route {
                                appNavigator?.navigate(.library(route))
                            }
                        } label: {
                            LibraryCollectionCard(item: item)
                                .frame(maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func specialCollectionItem(for kind: LibrarySpecialCollectionKind) -> LibraryShortcutCardItem {
        LibraryShortcutCardItem(
            id: kind.id,
            title: kind.title,
            systemImageName: kind.collectionSystemImageName,
            tint: kind.tint,
            metadataText: "\(viewModel.specialCollectionCount(for: kind))",
            destination: AnyView(EmptyView()),
            route: .specialCollection(viewModel.descriptor, kind)
        )
    }

    private func organizationItem(for sectionKind: LibraryOrganizationSectionKind) -> LibraryShortcutCardItem {
        LibraryShortcutCardItem(
            id: sectionKind.id,
            title: sectionKind.title,
            systemImageName: sectionKind.collectionSystemImageName,
            tint: sectionKind.tint,
            destination: AnyView(EmptyView()),
            route: .organization(viewModel.descriptor, sectionKind)
        )
    }

    /// Shown here only when Settings puts continue reading inside each library;
    /// otherwise the library home aggregates it and the In Progress filter finds it here.
    @ViewBuilder
    private var continueReadingSection: some View {
        if continueReadingPlacementRawValue == ContinueReadingPlacement.insideLibraries.rawValue,
           let comic = viewModel.continueReadingComic {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                collectionPreviewHeader(for: .reading)
                HeroTapButton { frame in
                    presentComic(
                        comic,
                        context: previewNavigationContext(for: .reading),
                        sourceFrame: frame,
                        preferredHeroSourceID: previewHeroSourceID(for: .reading, comic: comic)
                    )
                } label: {
                    ContinueReadingCard(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic),
                        coverSource: viewModel.coverSource(for: comic),
                        heroSourceID: previewHeroSourceID(for: .reading, comic: comic)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    LibraryComicMenuContent(comic: comic, actions: comicActions)
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
            return String(localized: "Continue Reading")
        case .recent:
            return String(localized: "Recently Added")
        case .favorites:
            return String(localized: "Favorites")
        }
    }

    private func previewHeroSourceID(
        for kind: LibrarySpecialCollectionKind,
        comic: LibraryComic
    ) -> String {
        "library-preview-\(viewModel.descriptor.id.uuidString)-\(kind.id)-\(comic.id)"
    }

    private func collectionPreviewHeader(
        for kind: LibrarySpecialCollectionKind
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(previewSectionTitle(for: kind))
                .font(AppFont.title2(.bold))
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Spacing.sm)

            Button {
                appNavigator?.navigate(
                    .library(.specialCollection(viewModel.descriptor, kind))
                )
            } label: {
                HStack(spacing: Spacing.xxxs) {
                    Text("All")

                    Image(systemName: "chevron.forward")
                        .font(AppFont.caption(.semibold))
                }
                .font(AppFont.subheadline())
                .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
    }


    // MARK: - Items

    private func comicGridItem(_ comic: LibraryComic, context: ReaderNavigationContext) -> some View {
        Group {
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
                HeroTapButton { frame in
                    presentComic(comic, context: context, sourceFrame: frame)
                } label: {
                    LibraryComicCard(
                        comic: comic,
                        coverURL: viewModel.coverURL(for: comic),
                        coverSource: viewModel.coverSource(for: comic),
                        heroSourceID: viewModel.heroSourceID(for: comic)
                    )
                    .equatable()
                }
                .buttonStyle(.plain)
                .contextMenu {
                    LibraryComicMenuContent(comic: comic, actions: comicActions)
                }
            }
        }
    }

    @ViewBuilder
    private func comicListRow(_ comic: LibraryComic, context: ReaderNavigationContext) -> some View {
        if isSelectionMode {
            Button {
                toggleSelection(for: comic)
            } label: {
                LibraryComicRow(
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
            HeroTapButton { frame in
                presentComic(comic, context: context, sourceFrame: frame)
            } label: {
                LibraryComicRow(
                    comic: comic,
                    coverURL: viewModel.coverURL(for: comic),
                    coverSource: viewModel.coverSource(for: comic),
                    heroSourceID: viewModel.heroSourceID(for: comic),
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

    private func folderListRow(_ folder: LibraryFolder) -> some View {
        Button {
            openFolder(folder.id)
        } label: {
            LibraryFolderRow(
                folder: folder,
                coverURL: viewModel.coverURL(for: folder),
                previewCoverURLs: viewModel.previewCoverURLs(for: folder)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSelectionMode)
    }

    private var comicActions: LibraryComicActions {
        LibraryComicActions(
            toggleFavorite: { viewModel.toggleFavorite(for: $0) },
            toggleRead: { viewModel.toggleReadStatus(for: $0) },
            organize: { organizingComic = $0 },
            setRating: { rating, comic in viewModel.setRating(rating, for: comic) },
            editMetadata: { editingComic = $0 },
            showInfo: presentInfoSheet,
            delete: viewModel.canRemoveComics ? { deletingComic = $0 } : nil
        )
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var browsingToolbar: some ToolbarContent {
        if canSelectComics {
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
                Section {
                    importHereMenu
                }

                Section {
                    Picker("View As", selection: displayModeBinding) {
                        ForEach(LibraryBrowserDisplayMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImageName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.palette)
                }

                Section {
                    Button {
                        presentComicInfoImportSheet()
                    } label: {
                        Label("Import Comic Info…", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(viewModel.content == nil || !viewModel.canImportLibraryComicInfo)

                    Menu {
                        if viewModel.canRefreshCurrentFolder {
                            Button {
                                viewModel.refreshCurrentFolder()
                            } label: {
                                Label("This Folder", systemImage: "folder")
                            }
                        }

                        Button {
                            viewModel.refreshLibrary()
                        } label: {
                            Label("Entire Library", systemImage: "books.vertical")
                        }
                        .disabled(!viewModel.canRefreshLibrary)
                    } label: {
                        Label("Refresh & Scan", systemImage: "arrow.clockwise")
                    }
                    .disabled(!viewModel.canScanFromCurrentContext)

                    if libraryListViewModel != nil {
                        Button {
                            presentLibraryInfoSheet()
                        } label: {
                            Label("Library Info", systemImage: "info.circle")
                        }
                    }
                }
        }
    }

    /// "Import Here…" into the current library and folder; read-only folders
    /// keep the item, disabled, with the reason.
    @ViewBuilder
    private var importHereMenu: some View {
        if viewModel.supportsDirectLibraryImports {
            Menu {
                importHereMenuItems
            } label: {
                Label("Import Here…", systemImage: "square.and.arrow.down")
            }
            .disabled(!canImportComicFiles)
        } else {
            Button {} label: {
                // Title, subtitle and icon as direct children show the subtitle in menus.
                Text("Import Here…")
                Text("The folder is read-only")
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(true)
        }
    }

    /// A disabled parent Menu does not disable its items, so each item checks too.
    @ViewBuilder
    private var importHereMenuItems: some View {
        Button {
            presentImportPicker(.files)
        } label: {
            Label("Choose Files…", systemImage: "doc")
        }
        .disabled(!canImportComicFiles)

        Button {
            presentImportPicker(.folder)
        } label: {
            Label("Choose Folder…", systemImage: "folder")
        }
        .disabled(!canImportComicFiles)
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
                performBatchReadAction(!allSelectedAreRead)
            } label: {
                Label(
                    allSelectedAreRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: allSelectedAreRead ? "circle" : "checkmark.circle"
                )
            }
            .tint(.appAccent)
            .disabled(selectedComicIDs.isEmpty)

            Button {
                performBatchFavoriteAction(!allSelectedAreFavorites)
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

            if viewModel.canRemoveComics {
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
    }

    // MARK: - Task bar

    @ViewBuilder
    private var taskBanner: some View {
        if viewModel.isImportingComics {
            TaskBanner(
                content: viewModel.importProgress?.taskBannerContent(
                    destinationName: importDestinationName
                ) ?? TaskBannerContent(
                    phase: .running(fraction: nil),
                    title: String(localized: "Preparing Import"),
                    detail: String(localized: "To \(importDestinationName)")
                ),
                onClose: viewModel.cancelComicImport
            )
        } else if let scanProgress = viewModel.scanProgress {
            // Scans cannot be cancelled, so there is no ×.
            TaskBanner(
                content: TaskBannerContent(
                    phase: .running(fraction: nil),
                    title: scanProgress.title,
                    detail: scanProgress.detailLine
                )
            )
        } else if let taskResult = viewModel.taskResult {
            TaskBanner(content: taskResult) {
                viewModel.taskResult = nil
            }
        } else if let completion = viewModel.scanCompletion {
            TaskBanner(
                content: TaskBannerContent(
                    phase: .succeeded,
                    title: completion.title,
                    detail: completion.message
                ),
                onClose: viewModel.dismissScanCompletion
            )
        }
    }

    private var importDestinationName: String {
        if let folder = viewModel.content?.folder, !folder.isRoot {
            return "\(viewModel.descriptor.displayName) › \(folder.displayName)"
        }
        return viewModel.descriptor.displayName
    }

    // MARK: - State

    private var recentWindowOption: LibraryRecentWindowOption {
        LibraryRecentWindowOption(rawValue: recentWindowRawValue) ?? .defaultOption
    }

    private var canImportComicFiles: Bool {
        viewModel.canImportComicFiles && !viewModel.hasActiveSearch
    }

    private var canSelectComics: Bool {
        !viewModel.hasActiveSearch && !visibleComics.isEmpty
    }

    private var visibleComics: [LibraryComic] {
        if viewModel.hasActiveSearch {
            return sortedComics(viewModel.searchResults?.comics ?? [])
        }

        return filteredComics(viewModel.content?.comics ?? [])
    }

    private func filteredComics(_ comics: [LibraryComic]) -> [LibraryComic] {
        sortedComics(comics).filter(quickFilter.matches)
    }

    private var selectedComics: [LibraryComic] {
        visibleComics.filter { selectedComicIDs.contains($0.id) }
    }

    private var allSelectedAreRead: Bool {
        !selectedComics.isEmpty && selectedComics.allSatisfy(\.read)
    }

    private var allSelectedAreFavorites: Bool {
        !selectedComics.isEmpty && selectedComics.allSatisfy(\.isFavorite)
    }

    private var comicInfoImportTargetComics: [LibraryComic] {
        isSelectionMode ? selectedComics : visibleComics
    }

    private var comicInfoImportScope: BatchComicInfoImportScope {
        isSelectionMode ? .selected : .visible
    }

    private var currentFolderIDForComicInfoScope: Int64? {
        guard let folder = viewModel.content?.folder, !folder.isRoot else {
            return nil
        }
        return folder.id
    }

    private var visibleComicIDs: [Int64] {
        visibleComics.map(\.id)
    }

    private var areAllVisibleComicsSelected: Bool {
        let visibleIDs = Set(visibleComicIDs)
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedComicIDs)
    }

    private var selectionTitle: String {
        let count = selectedComicIDs.count
        return count == 1
            ? String(localized: "1 Selected")
            : String(localized: "\(count) Selected")
    }

    private var progressMessage: String {
        if let scanProgress = viewModel.scanProgress {
            return scanProgress.title
        }

        if viewModel.isInitializingLibrary {
            return String(localized: "Initializing Library")
        }

        if viewModel.isRefreshingLibrary {
            return String(localized: "Refreshing Library")
        }

        return String(localized: "Opening Library")
    }

    private var sortModeBinding: Binding<LibraryComicSortMode> {
        Binding(
            get: { comicSortMode },
            set: { applySortMode($0) }
        )
    }

    private var displayModeBinding: Binding<LibraryBrowserDisplayMode> {
        Binding(
            get: { displayMode },
            set: { applyDisplayMode($0) }
        )
    }

    private func handleReaderComicUpdate(_ updatedComic: LibraryComic) {
        viewModel.applyUpdatedComic(updatedComic)
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

    // MARK: - Actions

    private func presentImportPicker(_ route: ImportHereRoute) {
        presentedImportPicker = route
        activeImportPicker = route
    }

    private func handleImportHere(_ result: Result<[URL], Error>, route: ImportHereRoute?) {
        switch result {
        case .success(let urls):
            guard let route else {
                return
            }
            viewModel.importComicFiles(from: urls, traverseDirectories: route == .folder)
        case .failure(let error):
            viewModel.alert = AppAlertState(
                title: String(localized: "Import Failed"),
                message: error.userFacingMessage
            )
        }
    }

    private var presentationObservers: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: editingComic?.id) { _, _ in
                presentEditingComicSheetIfNeeded()
            }
            .onChange(of: organizingComic?.id) { _, _ in
                presentOrganizingComicSheetIfNeeded()
            }
    }

    private func presentComic(
        _ comic: LibraryComic,
        context: ReaderNavigationContext,
        sourceFrame: CGRect,
        preferredHeroSourceID: String? = nil
    ) {
        let heroSourceID = preferredHeroSourceID ?? viewModel.heroSourceID(for: comic)
        let registeredFrame = HeroSourceRegistry.shared.frame(for: heroSourceID)
        let effectiveSourceFrame = registeredFrame == .zero ? sourceFrame : registeredFrame
        let previewImage = LocalCoverTransitionCache.shared.image(for: heroSourceID)
            ?? viewModel.cachedTransitionImage(for: comic)

        appPresenter?.presentReader(
            .local(
                LocalReaderPresentation(
                    descriptor: viewModel.descriptor,
                    comic: comic,
                    navigationContext: context,
                    heroSourceID: heroSourceID,
                    sourceFrame: effectiveSourceFrame,
                    previewImage: previewImage,
                    onComicUpdated: handleReaderComicUpdate,
                    onDismiss: nil
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
                id: "library.browser.edit.\(comic.id)",
                content: AnyView(
                    ComicMetadataEditorSheet(
                        descriptor: viewModel.descriptor,
                        comic: comic,
                        dependencies: dependencies,
                        coverURL: viewModel.coverURL(for: comic),
                        coverSource: viewModel.coverSource(for: comic)
                    ) { updatedComic in
                        viewModel.applyUpdatedComic(updatedComic)
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
                id: "library.browser.organize.\(comic.id)",
                content: AnyView(
                    ComicOrganizationSheet(
                        descriptor: viewModel.descriptor,
                        comic: comic,
                        dependencies: dependencies
                    )
                ),
                onDismiss: {
                    organizingComic = nil
                    viewModel.load()
                }
            )
        )
    }

    private func presentInfoSheet(for comic: LibraryComic) {
        appPresenter?.presentSheet(
            .content(
                id: "library.browser.info.\(comic.id)",
                content: AnyView(
                    LibraryComicInfoSheet(
                        comic: comic,
                        libraryName: viewModel.descriptor.displayName,
                        coverURL: viewModel.coverURL(for: comic),
                        coverSource: viewModel.coverSource(for: comic)
                    )
                )
            )
        )
    }

    private func presentLibraryInfoSheet() {
        guard let libraryListViewModel else {
            return
        }

        appPresenter?.presentSheet(
            .content(
                id: "library.info.\(viewModel.descriptor.id.uuidString)",
                content: AnyView(
                    LibraryInfoSheet(
                        listViewModel: libraryListViewModel,
                        libraryID: viewModel.descriptor.id
                    ) {
                        appNavigator?.navigate(.library(.home))
                    }
                )
            )
        )
    }

    private func presentBatchMetadataSheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.browser.batchMetadata.\(selectedComicIDs.sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicMetadataSheet(
                        descriptor: viewModel.descriptor,
                        comicIDs: Array(selectedComicIDs),
                        dependencies: dependencies
                    ) {
                        endSelectionMode()
                        viewModel.load()
                    }
                )
            )
        )
    }

    private func presentComicInfoImportSheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.browser.infoImport.\(comicInfoImportTargetComics.map(\.id).sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicInfoImportSheet(
                        descriptor: viewModel.descriptor,
                        comics: comicInfoImportTargetComics,
                        scope: comicInfoImportScope,
                        folderID: currentFolderIDForComicInfoScope,
                        includesLibraryScope: viewModel.canImportLibraryComicInfo,
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
                )
            )
        )
    }

    private func presentBatchOrganizationSheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.browser.batchOrganization.\(selectedComicIDs.sorted().map(String.init).joined(separator: ","))",
                content: AnyView(
                    BatchComicOrganizationSheet(
                        descriptor: viewModel.descriptor,
                        comicIDs: Array(selectedComicIDs),
                        dependencies: dependencies
                    ) {
                        endSelectionMode()
                        viewModel.load()
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

    private func endSelectionMode() {
        isSelectionMode = false
        isConfirmingSelectionDeletion = false
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

    private func openFolder(_ folderID: Int64) {
        appNavigator?.navigate(.library(.openFolder(viewModel.descriptor, folderID: folderID)))
    }

    private func applyDisplayMode(_ mode: LibraryBrowserDisplayMode) {
        displayMode = mode
        Self.persistDisplayMode(mode)
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
                let displayedSearchComics = sortedComics(results.comics)

                if results.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: String(localized: "No Results"),
                            description: String(localized: "No folders or comics matched \"\(results.query)\".")
                        )
                        .padding(.vertical, Spacing.xl)
                    }
                } else {
                    if !results.folders.isEmpty {
                        Section {
                            ForEach(results.folders) { folder in
                                folderListRow(folder)
                            }
                        } header: {
                            sectionHeader(String(localized: "Matching Folders"), count: results.folders.count)
                        }
                    }

                    if !displayedSearchComics.isEmpty {
                        Section {
                            ForEach(displayedSearchComics) { comic in
                                comicListRow(
                                    comic,
                                    context: ReaderNavigationContext(
                                        title: String(localized: "Search"),
                                        comics: displayedSearchComics
                                    )
                                )
                            }
                        } header: {
                            sectionHeader(String(localized: "Matching Comics"), count: displayedSearchComics.count)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct LibraryComicPresentation: Identifiable {
    let id: UUID
    let comic: LibraryComic
    let navigationContext: ReaderNavigationContext

    init(comic: LibraryComic, navigationContext: ReaderNavigationContext) {
        self.id = UUID()
        self.comic = comic
        self.navigationContext = navigationContext
    }

    func updatingComic(_ updatedComic: LibraryComic) -> Self {
        var updatedNavigationContext = navigationContext
        if let index = updatedNavigationContext.comics.firstIndex(where: { $0.id == updatedComic.id }) {
            updatedNavigationContext.comics[index] = updatedComic
        }

        return Self(
            id: id,
            comic: updatedComic,
            navigationContext: updatedNavigationContext
        )
    }

    private init(
        id: UUID,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext
    ) {
        self.id = id
        self.comic = comic
        self.navigationContext = navigationContext
    }
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
            return String(localized: "List")
        case .grid:
            return String(localized: "Grid")
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
