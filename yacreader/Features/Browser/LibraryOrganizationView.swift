import SwiftUI

struct LibraryOrganizationView: View {
    private enum LayoutMetrics {
        static let horizontalInset: CGFloat = 12
        static let rowAccessoryReservedWidth: CGFloat = 34
        static let compactGridMinWidth: CGFloat = 165
        static let compactGridMaxWidth: CGFloat = 220
        static let regularGridMinWidth: CGFloat = 240
        static let regularGridMaxWidth: CGFloat = 320
        static let wideGridMinContainerWidth: CGFloat = 860
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: LibraryOrganizationViewModel
    @State private var sortMode: LibraryOrganizationSortMode
    @State private var preferredDisplayMode: LibraryComicDisplayMode
    @State private var displayMode: LibraryComicDisplayMode
    @State private var hasConfiguredPreferredDisplayMode = false
    @State private var searchQuery = ""
    @State private var editingCollection: LibraryOrganizationCollection?
    @State private var deletingCollection: LibraryOrganizationCollection?
    @State private var navigationCollection: LibraryOrganizationCollection?
    @State private var containerWidth: CGFloat = 0

    init(
        descriptor: LibraryDescriptor,
        sectionKind: LibraryOrganizationSectionKind,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _sortMode = State(initialValue: Self.loadStoredSortMode(for: sectionKind))
        let storedDisplayMode = Self.loadStoredDisplayMode(for: sectionKind)
        _preferredDisplayMode = State(initialValue: storedDisplayMode)
        _displayMode = State(initialValue: storedDisplayMode)
        _viewModel = StateObject(
            wrappedValue: LibraryOrganizationViewModel(
                descriptor: descriptor,
                sectionKind: sectionKind,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading \(viewModel.sectionKind.title)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentBody
            }
        }
        .readContainerWidth(into: $containerWidth)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentCreateSheet()
                } label: {
                    Image(systemName: "plus")
                }
            }

            if usesCondensedTopBarActions {
                if hasCondensedTopBarActions {
                    ToolbarItem(placement: .topBarTrailing) {
                        condensedTopBarActionsMenu
                    }
                }
            } else {
                if supportsGridDisplay {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            displayModeMenuContent
                        } label: {
                            Image(systemName: displayMode.systemImageName)
                        }
                    }
                }

                if canSortCollections {
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
        .refreshable {
            viewModel.load()
        }
        .searchable(text: $searchQuery, prompt: "Search \(viewModel.sectionKind.title)")
        .sheet(isPresented: $viewModel.isShowingCreateSheet) {
            LibraryOrganizationCreateSheet(viewModel: viewModel)
        }
        .sheet(item: $editingCollection) { collection in
            LibraryOrganizationCollectionEditorSheet(collection: collection) { name, color in
                viewModel.updateCollection(
                    collection,
                    name: name,
                    labelColor: color
                )
            }
        }
        .confirmationDialog(
            deletingCollectionDialogTitle,
            isPresented: deletingCollectionConfirmationBinding,
            titleVisibility: .visible,
            presenting: deletingCollection
        ) { collection in
            Button(deleteCollectionActionTitle(for: collection), role: .destructive) {
                if viewModel.deleteCollection(collection) {
                    deletingCollection = nil
                }
            }

            Button("Cancel", role: .cancel) {
                deletingCollection = nil
            }
        } message: { collection in
            Text(deleteCollectionMessage(for: collection))
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .navigationDestination(item: $navigationCollection) { collection in
            LibraryOrganizationCollectionDetailView(
                descriptor: viewModel.descriptor,
                collection: collection,
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

    private var listContent: some View {
        List {
            if displayedCollections.isEmpty {
                Section {
                    emptyStateView
                }
            } else {
                Section(contentSectionTitle) {
                    ForEach(displayedCollections) { collection in
                        Button {
                            navigationCollection = collection
                        } label: {
                            InsetListRowCard {
                                LibraryOrganizationCollectionRow(
                                    collection: collection,
                                    trailingAccessoryReservedWidth: LayoutMetrics.rowAccessoryReservedWidth
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            collectionActionMenu(
                                for: collection,
                                style: .icon
                            )
                            .padding(.trailing, 8)
                        }
                        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                    }
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if displayedCollections.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(contentSectionTitle)
                            .font(.headline)

                        LazyVGrid(columns: collectionGridColumns, alignment: .leading, spacing: 16) {
                            ForEach(displayedCollections) { collection in
                                NavigationLink {
                                    LibraryOrganizationCollectionDetailView(
                                        descriptor: viewModel.descriptor,
                                        collection: collection,
                                        dependencies: dependencies
                                    )
                                } label: {
                                    LibraryOrganizationCollectionCard(collection: collection)
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .topTrailing) {
                                    collectionActionMenu(for: collection, style: .elevatedIcon)
                                        .padding(12)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .adaptiveContentWidth(1120)
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

    private var displayedCollections: [LibraryOrganizationCollection] {
        let orderedCollections = sortedCollections(viewModel.collections)

        guard hasSearchQuery else {
            return orderedCollections
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return orderedCollections.filter { collection in
            collection.displayTitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var contentSectionTitle: String {
        hasSearchQuery ? "Results" : viewModel.sectionKind.title
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateTitle: String {
        hasSearchQuery ? "No Matches" : viewModel.sectionKind.emptyStateTitle
    }

    private var emptyStateDescription: String {
        hasSearchQuery
            ? "No matches for \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\"."
            : viewModel.sectionKind.emptyStateDescription
    }

    private var emptyStateSystemImage: String {
        hasSearchQuery ? "magnifyingglass" : viewModel.sectionKind.systemImageName
    }

    private var supportsGridDisplay: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularInlineActionMinWidth)
    }

    private var usesCondensedTopBarActions: Bool {
        !supportsGridDisplay
    }

    private var hasCondensedTopBarActions: Bool {
        canSortCollections
    }

    private var usesProminentCollectionActions: Bool {
        false
    }

    private var canSortCollections: Bool {
        !viewModel.collections.isEmpty
    }

    private var collectionGridColumns: [GridItem] {
        let widthRange = usesWideCollectionGridMetrics
            ? LayoutMetrics.regularGridMinWidth...LayoutMetrics.regularGridMaxWidth
            : LayoutMetrics.compactGridMinWidth...LayoutMetrics.compactGridMaxWidth
        return [GridItem(.adaptive(minimum: widthRange.lowerBound, maximum: widthRange.upperBound), spacing: 16)]
    }

    private var usesWideCollectionGridMetrics: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= LayoutMetrics.wideGridMinContainerWidth)
    }

    private func sortedCollections(_ collections: [LibraryOrganizationCollection]) -> [LibraryOrganizationCollection] {
        collections.sorted { lhs, rhs in
            switch sortMode {
            case .name:
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            case .comicCountDescending:
                if lhs.comicCount == rhs.comicCount {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }

                return lhs.comicCount > rhs.comicCount
            case .comicCountAscending:
                if lhs.comicCount == rhs.comicCount {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }

                return lhs.comicCount < rhs.comicCount
            }
        }
    }

    private func applySortMode(_ mode: LibraryOrganizationSortMode) {
        sortMode = mode
        Self.persistSortMode(mode, for: viewModel.sectionKind)
    }

    @ViewBuilder
    private var condensedTopBarActionsMenu: some View {
        Menu {
            if canSortCollections {
                Menu {
                    sortModeMenuContent
                } label: {
                    Label("Sort Collections", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More Collection Actions")
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
        ForEach(LibraryOrganizationSortMode.allCases) { mode in
            Button {
                applySortMode(mode)
            } label: {
                HStack {
                    Text(mode.title)
                    Spacer()
                    if sortMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        preferredDisplayMode = mode
        Self.persistDisplayMode(mode, for: viewModel.sectionKind)
        displayMode = supportsGridDisplay ? mode : .list
    }

    private static func sortModeStorageKey(for sectionKind: LibraryOrganizationSectionKind) -> String {
        "libraryOrganizationOverviewSortMode.\(sectionKind.rawValue)"
    }

    private static func loadStoredSortMode(
        for sectionKind: LibraryOrganizationSectionKind
    ) -> LibraryOrganizationSortMode {
        let defaults = UserDefaults.standard
        let storageKey = sortModeStorageKey(for: sectionKind)

        if let rawValue = defaults.string(forKey: storageKey),
           let mode = LibraryOrganizationSortMode(rawValue: rawValue) {
            return mode
        }

        return .name
    }

    private static func persistSortMode(
        _ mode: LibraryOrganizationSortMode,
        for sectionKind: LibraryOrganizationSectionKind
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: sortModeStorageKey(for: sectionKind)
        )
    }

    private static func displayModeStorageKey(for sectionKind: LibraryOrganizationSectionKind) -> String {
        "libraryOrganizationOverviewDisplayMode.\(sectionKind.rawValue)"
    }

    private static func loadStoredDisplayMode(
        for sectionKind: LibraryOrganizationSectionKind
    ) -> LibraryComicDisplayMode {
        let defaults = UserDefaults.standard
        let storageKey = displayModeStorageKey(for: sectionKind)

        if let rawValue = defaults.string(forKey: storageKey),
           let mode = LibraryComicDisplayMode(rawValue: rawValue) {
            return mode
        }

        return .grid
    }

    private static func persistDisplayMode(
        _ mode: LibraryComicDisplayMode,
        for sectionKind: LibraryOrganizationSectionKind
    ) {
        UserDefaults.standard.set(
            mode.rawValue,
            forKey: displayModeStorageKey(for: sectionKind)
        )
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

    @ViewBuilder
    private func collectionActionMenu(
        for collection: LibraryOrganizationCollection,
        style: CollectionActionAffordanceStyle = .icon
    ) -> some View {
        Menu {
            Button {
                editingCollection = collection
            } label: {
                Label(
                    collection.type == .label ? "Edit Tag" : "Edit Reading List",
                    systemImage: "square.and.pencil"
                )
            }

            Button(role: .destructive) {
                deletingCollection = collection
            } label: {
                Label(
                    deleteCollectionActionTitle(for: collection),
                    systemImage: "trash"
                )
            }
        } label: {
            Group {
                if style == .compactCapsule {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                } else if style == .elevatedIcon {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collection Actions")
    }
}

private enum CollectionActionAffordanceStyle {
    case icon
    case compactCapsule
    case elevatedIcon
}

private struct LibraryOrganizationCreateSheet: View {
    @ObservedObject var viewModel: LibraryOrganizationViewModel

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(viewModel.sectionKind.createNamePrompt, text: $viewModel.pendingCollectionName)
                        .focused($isNameFieldFocused)
                }

                if viewModel.supportsLabelColorSelection {
                    Section("Color") {
                        Picker("Color", selection: $viewModel.selectedLabelColor) {
                            ForEach(LibraryLabelColor.allCases) { color in
                                HStack {
                                    Circle()
                                        .fill(color.swiftUIColor)
                                        .frame(width: 12, height: 12)
                                    Text(color.displayName)
                                }
                                .tag(color)
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.sectionKind.createActionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: viewModel.dismissCreateSheet)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: viewModel.createCollection)
                        .disabled(viewModel.pendingCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .adaptiveSheetWidth(520)
        .presentationDetents([.medium])
        .onAppear {
            isNameFieldFocused = true
        }
    }
}
