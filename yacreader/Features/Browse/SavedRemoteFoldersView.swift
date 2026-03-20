import Combine
import SwiftUI

struct SavedRemoteFoldersView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: SavedRemoteFoldersViewModel
    @State private var searchText = ""
    @State private var renameEntry: SavedRemoteFoldersViewModel.ShortcutEntry?
    @State private var pendingRemovalEntry: SavedRemoteFoldersViewModel.ShortcutEntry?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: SavedRemoteFoldersViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        List {
            summarySection

            if filteredEntries.isEmpty {
                emptyStateSection
            } else {
                Section("Saved SMB Folders") {
                    ForEach(filteredEntries) { entry in
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
                                trailingAccessoryReservedWidth: 46
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            SavedRemoteFolderActionMenuButton(
                                onRename: {
                                    renameEntry = entry
                                },
                                onRemove: {
                                    pendingRemovalEntry = entry
                                }
                            )
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Folders")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search saved SMB folders")
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
                Text("\"\(entry.shortcut.title)\" will be removed from Browse shortcuts. The remote folder itself will stay untouched.")
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

    private var filteredEntries: [SavedRemoteFoldersViewModel.ShortcutEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return viewModel.entries
        }

        return viewModel.entries.filter { entry in
            entry.shortcut.title.localizedCaseInsensitiveContains(query)
                || entry.profile.name.localizedCaseInsensitiveContains(query)
                || entry.shortcut.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.summaryTitle)
                    .font(.headline)

                Text(viewModel.summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        Section {
            if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No Saved Folders Yet",
                    systemImage: "star",
                    description: Text("Save frequently used SMB directories from the remote browser to keep them one tap away.")
                )
                .padding(.vertical, 18)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .padding(.vertical, 18)
            }
        }
    }
}

@MainActor
final class SavedRemoteFoldersViewModel: ObservableObject {
    typealias ShortcutEntry = RemoteResolvedFolderShortcut

    @Published private(set) var entries: [ShortcutEntry] = []
    @Published var alert: BrowseHomeAlert?

    private let shortcutSnapshotStore: RemoteFolderShortcutSnapshotStore
    private let shortcutStore: RemoteFolderShortcutStore
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.shortcutSnapshotStore = dependencies.remoteFolderShortcutSnapshotStore
        self.shortcutStore = dependencies.remoteFolderShortcutStore
    }

    var summaryTitle: String {
        switch entries.count {
        case 0:
            return "Keep favorite SMB folders close"
        case 1:
            return "1 saved folder shortcut"
        default:
            return "\(entries.count) saved folder shortcuts"
        }
    }

    var summaryText: String {
        if entries.isEmpty {
            return "Save the directories you revisit most often so Browse can jump straight back into them."
        }

        return "Open, rename, or remove your favorite SMB directories here without digging through the server tree again."
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func load() async {
        do {
            entries = try shortcutSnapshotStore.loadEntries()
            alert = nil
        } catch {
            entries = []
            alert = BrowseHomeAlert(
                title: "Saved Folders Unavailable",
                message: error.localizedDescription
            )
        }
    }

    func renameShortcut(_ entry: ShortcutEntry, to proposedTitle: String) {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alert = BrowseHomeAlert(
                title: "Shortcut Name Required",
                message: "Enter a display name for this saved SMB folder."
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
                message: error.localizedDescription
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
                message: error.localizedDescription
            )
        }
    }
}

private struct SavedRemoteFolderActionMenuButton: View {
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(action: onRename) {
                Label("Rename Shortcut", systemImage: "pencil")
            }

            Button(role: .destructive, action: onRemove) {
                Label("Remove Shortcut", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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

                    Text(entry.shortcut.path.isEmpty ? "/" : entry.shortcut.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Shortcut")
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
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }
}
