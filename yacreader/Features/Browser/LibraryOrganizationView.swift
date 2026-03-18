import SwiftUI

struct LibraryOrganizationView: View {
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
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if supportsGridDisplay {
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
            }

            if canSortCollections {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentCreateSheet()
                } label: {
                    Image(systemName: "plus")
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
        .onChange(of: horizontalSizeClass) { _, newValue in
            adaptDisplayMode(to: newValue)
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

            if displayedCollections.isEmpty {
                Section {
                    emptyStateView
                }
            } else {
                Section(viewModel.sectionKind.title) {
                    ForEach(displayedCollections) { collection in
                        NavigationLink {
                            LibraryOrganizationCollectionDetailView(
                                descriptor: viewModel.descriptor,
                                collection: collection,
                                dependencies: dependencies
                            )
                        } label: {
                            LibraryOrganizationCollectionRow(
                                collection: collection,
                                trailingAccessoryReservedWidth: 40
                            )
                        }
                        .overlay(alignment: .trailing) {
                            collectionActionMenu(for: collection)
                                .padding(.trailing, 8)
                        }
                    }
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard

                if displayedCollections.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(viewModel.sectionKind.title)
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
                                    collectionActionMenu(for: collection, compact: true)
                                        .padding(12)
                                }
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
                Text(viewModel.sectionKind.title)
                    .font(.headline)

                Text(viewModel.sectionKind.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.sectionKind.title)
                .font(.title3.weight(.semibold))

            Text(viewModel.sectionKind.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                StatusBadge(title: summaryCountText, tint: .green)
                if hasSearchQuery {
                    StatusBadge(title: "Filtered", tint: .orange)
                }
                StatusBadge(title: displayMode.title, tint: .blue)
                StatusBadge(title: sortMode.title, tint: .teal)
            }

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var summaryText: String {
        if hasSearchQuery {
            return displayedCollections.count == 1
                ? "1 collection matches \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\"."
                : "\(displayedCollections.count) collections match \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\"."
        }

        return viewModel.summaryText
    }

    private var summaryCountText: String {
        displayedCollections.count == 1 ? "1 collection" : "\(displayedCollections.count) collections"
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateTitle: String {
        hasSearchQuery ? "No Matches" : viewModel.sectionKind.emptyStateTitle
    }

    private var emptyStateDescription: String {
        hasSearchQuery
            ? "No \(viewModel.sectionKind.title.lowercased()) matched \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\"."
            : viewModel.sectionKind.emptyStateDescription
    }

    private var emptyStateSystemImage: String {
        hasSearchQuery ? "magnifyingglass" : viewModel.sectionKind.systemImageName
    }

    private var supportsGridDisplay: Bool {
        horizontalSizeClass == .regular
    }

    private var canSortCollections: Bool {
        !viewModel.collections.isEmpty
    }

    private var collectionGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)]
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

    private func adaptDisplayMode(to sizeClass: UserInterfaceSizeClass?) {
        if sizeClass == .regular {
            displayMode = preferredDisplayMode
        } else if displayMode == .grid {
            displayMode = .list
        }
    }

    @ViewBuilder
    private func collectionActionMenu(
        for collection: LibraryOrganizationCollection,
        compact: Bool = false
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
                if compact {
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

private struct LibraryOrganizationCreateSheet: View {
    @ObservedObject var viewModel: LibraryOrganizationViewModel

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(viewModel.sectionKind.createActionTitle) {
                    TextField(viewModel.sectionKind.createNamePrompt, text: $viewModel.pendingCollectionName)
                        .focused($isNameFieldFocused)

                    if viewModel.supportsLabelColorSelection {
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
        .presentationDetents([.medium])
        .onAppear {
            isNameFieldFocused = true
        }
    }
}
