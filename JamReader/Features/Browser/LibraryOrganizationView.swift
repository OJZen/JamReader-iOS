import SwiftUI

/// Tags or reading lists of one library: the same page structure for both.
/// Edit renames, recolors or deletes; long press and swipe are shortcuts.
/// See docs/design-system/components/ScreenCollections.
struct LibraryOrganizationView: View {
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter

    @StateObject private var viewModel: LibraryOrganizationViewModel
    @State private var searchQuery = ""
    @State private var editMode: EditMode = .inactive
    @State private var editingCollection: LibraryOrganizationCollection?
    @State private var deletingCollection: LibraryOrganizationCollection?
    @AppStorage private var sortModeRawValue: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        descriptor: LibraryDescriptor,
        sectionKind: LibraryOrganizationSectionKind,
        dependencies: AppDependencies
    ) {
        _viewModel = StateObject(
            wrappedValue: LibraryOrganizationViewModel(
                descriptor: descriptor,
                sectionKind: sectionKind,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager
            )
        )
        _sortModeRawValue = AppStorage(
            wrappedValue: LibraryOrganizationSortMode.name.rawValue,
            "libraryOrganizationOverviewSortMode.\(sectionKind.rawValue)"
        )
    }

    var body: some View {
        List {
            Section {
                if displayedCollections.isEmpty {
                    emptyStateView
                } else {
                    ForEach(displayedCollections) { collection in
                        row(for: collection)
                    }
                    .onDelete { offsets in
                        deletingCollection = offsets.first.map { displayedCollections[$0] }
                    }
                }
            } header: {
                sectionHeader
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                } label: {
                    Label(
                        editMode.isEditing ? "Done" : "Edit",
                        systemImage: editMode.isEditing ? "checkmark" : "pencil"
                    )
                }
                .labelStyle(.titleOnly)
                .disabled(viewModel.collections.isEmpty && !editMode.isEditing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.presentCreateSheet()
                } label: {
                    Label(viewModel.sectionKind.createActionTitle, systemImage: "plus")
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.load()
        }
        .refreshable {
            viewModel.load()
        }
        .searchable(
            text: $searchQuery,
            prompt: Text("Search in “\(viewModel.navigationTitle)”")
        )
        .onChange(of: viewModel.isShowingCreateSheet) { _, isPresented in
            if isPresented {
                presentCreateSheetIfNeeded()
            } else {
                appPresenter?.dismissSheet()
            }
        }
        .onChange(of: editingCollection?.id) { _, _ in
            presentEditingCollectionSheetIfNeeded()
        }
        .confirmationDialog(
            deletingCollection.map(LibraryCollectionDeletionCopy.title(for:)) ?? "",
            isPresented: Binding(
                get: { deletingCollection != nil },
                set: { isPresented in
                    if !isPresented {
                        deletingCollection = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: deletingCollection
        ) { collection in
            Button(LibraryCollectionDeletionCopy.actionTitle(for: collection.type), role: .destructive) {
                if viewModel.deleteCollection(collection) {
                    deletingCollection = nil
                }
            }
        } message: { collection in
            Text(LibraryCollectionDeletionCopy.message(for: collection.type))
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func row(for collection: LibraryOrganizationCollection) -> some View {
        Button {
            if editMode.isEditing {
                editingCollection = collection
            } else {
                appNavigator?.navigate(.library(.organizationCollection(viewModel.descriptor, collection)))
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                collectionMark(for: collection)

                Text(collection.displayTitle)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(collection.comicCount)")
                    .font(AppFont.body().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)

                Image(systemName: editMode.isEditing ? "info.circle" : "chevron.forward")
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(editMode.isEditing ? Color.appAccent : Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(editMode.isEditing ? Text("Edits the name and color") : Text("Opens the comics"))
        .contextMenu {
            collectionActions(for: collection)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deletingCollection = collection
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingCollection = collection
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.appJam)
        }
    }

    /// Tag color only ever appears as a 10pt dot next to the name.
    @ViewBuilder
    private func collectionMark(for collection: LibraryOrganizationCollection) -> some View {
        switch collection.type {
        case .label:
            Circle()
                .fill((collection.labelColor ?? .blue).swiftUIColor)
                .frame(width: 10, height: 10)
                .frame(width: 20)
                .accessibilityHidden(true)
        case .readingList:
            Image(systemName: "list.bullet")
                .font(AppFont.subheadline(.semibold))
                .foregroundStyle(Color.appSuccess)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func collectionActions(for collection: LibraryOrganizationCollection) -> some View {
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
            // Title, subtitle and icon as direct children show the subtitle in menus.
            Text(LibraryCollectionDeletionCopy.actionTitle(for: collection.type))
            Text("Comics are not deleted")
            Image(systemName: "trash")
        }
    }

    /// Library and count on the left, the sort menu fixed on the right.
    private var sectionHeader: some View {
        // Large text puts the sort menu under the subtitle instead of breaking words.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return layout {
            Text(subtitle)
                .font(AppFont.subheadline().monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.collections.count > 1 {
                Menu {
                    Picker("Sort", selection: sortModeBinding) {
                        ForEach(LibraryOrganizationSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                        .font(AppFont.subheadline(.semibold))
                        .foregroundStyle(Color.appAccent)
                }
                .accessibilityLabel(Text("Sort"))
                .accessibilityValue(Text(sortMode.title))
            }
        }
        .textCase(nil)
    }

    private var sortMode: LibraryOrganizationSortMode {
        LibraryOrganizationSortMode(rawValue: sortModeRawValue) ?? .name
    }

    private var sortModeBinding: Binding<LibraryOrganizationSortMode> {
        Binding(
            get: { sortMode },
            set: { sortModeRawValue = $0.rawValue }
        )
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            hasSearchQuery ? String(localized: "No Matches") : viewModel.sectionKind.emptyStateTitle,
            systemImage: hasSearchQuery ? "magnifyingglass" : viewModel.sectionKind.collectionSystemImageName,
            description: Text(
                hasSearchQuery
                    ? String(localized: "No matches for “\(trimmedSearchQuery)”.")
                    : viewModel.sectionKind.emptyStateDescription
            )
        )
        .listRowBackground(Color.clear)
    }

    private var subtitle: String {
        let count = viewModel.collections.count
        let countText: String
        switch viewModel.sectionKind {
        case .labels:
            countText = count == 1 ? String(localized: "1 tag") : String(localized: "\(count) tags")
        case .readingLists:
            countText = count == 1 ? String(localized: "1 list") : String(localized: "\(count) lists")
        }
        return "\(viewModel.descriptor.displayName) · \(countText)"
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchQuery: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var displayedCollections: [LibraryOrganizationCollection] {
        let ordered = viewModel.collections.sorted(by: sortMode)

        guard hasSearchQuery else {
            return ordered
        }

        return ordered.filter { $0.displayTitle.localizedCaseInsensitiveContains(trimmedSearchQuery) }
    }

    private func presentCreateSheetIfNeeded() {
        guard viewModel.isShowingCreateSheet else {
            return
        }

        appPresenter?.presentSheet(
            .content(
                id: "library.organization.create.\(viewModel.sectionKind.rawValue)",
                content: AnyView(LibraryOrganizationCreateSheet(viewModel: viewModel)),
                onDismiss: {
                    viewModel.dismissCreateSheet()
                }
            )
        )
    }

    private func presentEditingCollectionSheetIfNeeded() {
        guard let collection = editingCollection else {
            return
        }

        appPresenter?.presentSheet(
            .content(
                id: "library.organization.collectionEditor.\(collection.id)",
                content: AnyView(
                    LibraryOrganizationCollectionEditorSheet(collection: collection) { name, color in
                        viewModel.updateCollection(
                            collection,
                            name: name,
                            labelColor: color
                        )
                    }
                ),
                onDismiss: {
                    editingCollection = nil
                }
            )
        )
    }
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
