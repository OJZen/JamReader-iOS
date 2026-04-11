import Combine
import SwiftUI

private enum SavedRemoteFoldersLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let rowAccessoryReservedWidth: CGFloat = 36
}

struct SavedRemoteFoldersView: View {
    let dependencies: AppDependencies
    let focusedProfile: RemoteServerProfile?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: SavedRemoteFoldersViewModel
    @State private var searchText = ""
    @State private var renameEntry: SavedRemoteFoldersViewModel.ShortcutEntry?
    @State private var pendingRemovalEntry: SavedRemoteFoldersViewModel.ShortcutEntry?
    @State private var containerWidth: CGFloat = 0

    init(
        dependencies: AppDependencies,
        focusedProfile: RemoteServerProfile? = nil
    ) {
        self.dependencies = dependencies
        self.focusedProfile = focusedProfile
        _viewModel = StateObject(
            wrappedValue: SavedRemoteFoldersViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        List {
            if filteredEntries.isEmpty {
                emptyStateSection
            } else {
                ForEach(displayedSections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            NavigationLink {
                                RemoteServerBrowserView(
                                    profile: entry.profile,
                                    currentPath: entry.shortcut.path,
                                    dependencies: dependencies
                                )
                            } label: {
                                RemoteSavedFolderCard(
                                    shortcut: entry.shortcut,
                                    profile: entry.profile,
                                    showsNavigationIndicator: false,
                                    showsServerName: false,
                                    trailingAccessoryReservedWidth: itemAccessoryReservedWidth
                                )
                            }
                            .buttonStyle(.plain)
                            .insetCardListRow(horizontalInset: SavedRemoteFoldersLayoutMetrics.horizontalInset)
                            .overlay(alignment: .trailing) {
                                if showsPersistentItemActions {
                                    savedFolderActionMenu(for: entry)
                                        .padding(.trailing, 8)
                                }
                            }
                            .contextMenu {
                                savedFolderActionMenuContent(for: entry)
                            }
                        }
                    } header: {
                        sectionHeader(for: section)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .readContainerWidth(into: $containerWidth)
        .background(background)
        .overlay {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Saved Folders")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search folders")
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(item: $renameEntry) { entry in
            SavedRemoteFolderRenameSheet(entry: entry) { proposedTitle in
                viewModel.renameShortcut(entry, to: proposedTitle)
            }
        }
        .confirmationDialog(
            "Remove saved folder?",
            isPresented: Binding(
                get: { pendingRemovalEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemovalEntry = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let entry = pendingRemovalEntry {
                Button("Remove Shortcut", role: .destructive) {
                    viewModel.removeShortcut(entry)
                    pendingRemovalEntry = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingRemovalEntry = nil
            }
        } message: {
            if let entry = pendingRemovalEntry {
                Text("Removes the shortcut for \"\(entry.shortcut.title)\" only.")
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var showsPersistentItemActions: Bool {
        horizontalSizeClass == .regular
            && containerWidth >= AppLayout.regularInlineActionMinWidth
    }

    private var itemAccessoryReservedWidth: CGFloat {
        showsPersistentItemActions ? SavedRemoteFoldersLayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var filteredEntries: [SavedRemoteFoldersViewModel.ShortcutEntry] {
        let scopedEntries: [SavedRemoteFoldersViewModel.ShortcutEntry]
        if let focusedProfile {
            scopedEntries = viewModel.entries.filter { $0.profile.id == focusedProfile.id }
        } else {
            scopedEntries = viewModel.entries
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return scopedEntries
        }

        return scopedEntries.filter { entry in
            entry.shortcut.title.localizedCaseInsensitiveContains(query)
                || entry.profile.name.localizedCaseInsensitiveContains(query)
                || entry.shortcut.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayedSections: [SavedRemoteFolderSection] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.profile.id }

        return grouped.values
            .map { entries in
                SavedRemoteFolderSection(
                    profile: entries[0].profile,
                    entries: entries.sorted {
                        if $0.shortcut.updatedAt != $1.shortcut.updatedAt {
                            return $0.shortcut.updatedAt > $1.shortcut.updatedAt
                        }

                        return $0.shortcut.title.localizedStandardCompare($1.shortcut.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.profile.name.localizedStandardCompare($1.profile.name) == .orderedAscending
            }
    }

    private var focusedEntryCount: Int {
        if let focusedProfile {
            return viewModel.entries.filter { $0.profile.id == focusedProfile.id }.count
        }

        return viewModel.entries.count
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        Section {
            if focusedEntryCount == 0 {
                ContentUnavailableView(
                    focusedProfile == nil ? "No Saved Folders" : "No Saved Folders",
                    systemImage: "star",
                    description: Text(
                        focusedProfile == nil
                            ? "Save folders in Browse."
                            : "Save folders from this server in Browse."
                    )
                )
                .padding(.vertical, 18)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .padding(.vertical, 18)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: SavedRemoteFolderSection) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.profile.name)
                    .font(.subheadline.weight(.semibold))

                Text(savedFolderCountText(for: section))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)
        }
        .textCase(nil)
    }

    private func savedFolderCountText(
        for section: SavedRemoteFolderSection
    ) -> String {
        section.entries.count == 1 ? "1 saved" : "\(section.entries.count) saved"
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var background: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func savedFolderActionMenuContent(
        for entry: SavedRemoteFoldersViewModel.ShortcutEntry
    ) -> some View {
        Button {
            renameEntry = entry
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            pendingRemovalEntry = entry
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func savedFolderActionMenu(
        for entry: SavedRemoteFoldersViewModel.ShortcutEntry
    ) -> some View {
        Menu {
            savedFolderActionMenuContent(for: entry)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(entry.shortcut.title)")
    }

}

@MainActor
final class SavedRemoteFoldersViewModel: ObservableObject {
    typealias ShortcutEntry = RemoteResolvedFolderShortcut

    @Published private(set) var entries: [ShortcutEntry] = []
    @Published private(set) var isLoading = false
    @Published var alert: BrowseHomeAlert?

    private let shortcutSnapshotStore: RemoteFolderShortcutSnapshotStore
    private let shortcutStore: RemoteFolderShortcutStore
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.shortcutSnapshotStore = dependencies.remoteFolderShortcutSnapshotStore
        self.shortcutStore = dependencies.remoteFolderShortcutStore
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try shortcutSnapshotStore.loadEntries()
            alert = nil
        } catch {
            entries = []
            alert = BrowseHomeAlert(
                title: "Saved Folders Unavailable",
                message: error.userFacingMessage
            )
        }
    }

    func renameShortcut(_ entry: ShortcutEntry, to proposedTitle: String) {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alert = BrowseHomeAlert(
                title: "Shortcut Name Required",
                message: "Enter a display name for this saved remote folder."
            )
            return
        }

        do {
            try shortcutStore.renameShortcut(id: entry.shortcut.id, title: title)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                var updatedShortcut = entries[index].shortcut
                updatedShortcut.title = title
                updatedShortcut.updatedAt = Date()
                entries[index] = ShortcutEntry(shortcut: updatedShortcut, profile: entries[index].profile)
            }
        } catch {
            alert = BrowseHomeAlert(
                title: "Failed to Rename Shortcut",
                message: error.userFacingMessage
            )
        }
    }

    func removeShortcut(_ entry: ShortcutEntry) {
        do {
            try shortcutStore.removeShortcut(id: entry.shortcut.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            alert = BrowseHomeAlert(
                title: "Failed to Remove Shortcut",
                message: error.userFacingMessage
            )
        }
    }
}

private struct SavedRemoteFolderRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: SavedRemoteFoldersViewModel.ShortcutEntry
    let onSave: (String) -> Void

    @State private var proposedTitle: String
    @FocusState private var isFocused: Bool

    init(
        entry: SavedRemoteFoldersViewModel.ShortcutEntry,
        onSave: @escaping (String) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        _proposedTitle = State(initialValue: entry.shortcut.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Folder shortcut", text: $proposedTitle)
                        .focused($isFocused)

                    LabeledContent("Path") {
                        Text(entry.shortcut.path.isEmpty ? "/" : entry.shortcut.path)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(proposedTitle)
                        dismiss()
                    }
                    .disabled(proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .adaptiveSheetWidth(520)
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }
}

private struct SavedRemoteFolderSection: Identifiable {
    let profile: RemoteServerProfile
    let entries: [SavedRemoteFoldersViewModel.ShortcutEntry]

    var id: UUID {
        profile.id
    }
}
