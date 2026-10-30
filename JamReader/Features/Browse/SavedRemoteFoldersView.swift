import Combine
import SwiftUI
import os

struct SavedRemoteFoldersView: View {
    let dependencies: AppDependencies
    let focusedProfile: RemoteServerProfile?

    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter

    @StateObject private var viewModel: SavedRemoteFoldersViewModel
    @State private var searchText = ""
    @State private var pendingRemovalEntry: SavedRemoteFoldersViewModel.ShortcutEntry?
    @State private var editMode: EditMode = .inactive

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
                            savedFolderRow(for: entry)
                        }
                        .onDelete { offsets in
                            pendingRemovalEntry = offsets.first.map { section.entries[$0] }
                        }
                    } header: {
                        Text(section.profile.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .toolbar {
            if focusedEntryCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .fontWeight(editMode.isEditing ? .semibold : .regular)
                }
            }
        }
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
                Button("Remove", role: .destructive) {
                    viewModel.removeShortcut(entry)
                    pendingRemovalEntry = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingRemovalEntry = nil
            }
        } message: {
            if let entry = pendingRemovalEntry {
                Text("Removes “\(entry.shortcut.title)” from Saved Folders. Files on the server are not affected.")
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

    /// Tapping opens the folder; while editing it renames instead.
    private func savedFolderRow(
        for entry: SavedRemoteFoldersViewModel.ShortcutEntry
    ) -> some View {
        Button {
            if editMode.isEditing {
                presentRenameSheet(for: entry)
            } else {
                appNavigator?.navigate(
                    .browse(
                        .serverBrowser(
                            entry.profile.id,
                            path: entry.shortcut.path
                        )
                    )
                )
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(entry.shortcut.title)
                        .foregroundStyle(Color.textPrimary)
                    Text(entry.shortcut.path.isEmpty ? "/" : entry.shortcut.path)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: editMode.isEditing ? "pencil" : "chevron.forward")
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(editMode.isEditing ? Color.appAccent : Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(editMode.isEditing ? Text("Rename") : Text(""))
        .contextMenu {
            savedFolderActionMenuContent(for: entry)
        }
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
                    String(localized: "No Saved Folders"),
                    systemImage: "pin",
                    description: Text("Tap the pin in a remote folder to save it here.")
                )
                .padding(.vertical, 18)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .padding(.vertical, 18)
            }
        }
    }

    @ViewBuilder
    private func savedFolderActionMenuContent(
        for entry: SavedRemoteFoldersViewModel.ShortcutEntry
    ) -> some View {
        Button {
            presentRenameSheet(for: entry)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            pendingRemovalEntry = entry
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func presentRenameSheet(for entry: SavedRemoteFoldersViewModel.ShortcutEntry) {
        appPresenter?.presentSheet(
            .content(
                id: "saved-folder.rename.\(entry.shortcut.id)",
                content: AnyView(
                    SavedRemoteFolderRenameSheet(entry: entry) { proposedTitle in
                        viewModel.renameShortcut(entry, to: proposedTitle)
                    }
                )
            )
        )
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
    private let logger = AppLog.remote

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
            let loadedEntries = try shortcutSnapshotStore.loadEntries()
            entries = loadedEntries
            alert = nil
            logger.info(
                "Saved remote folders loaded count=\(loadedEntries.count)"
            )
        } catch {
            entries = []
            logger.error(
                "Saved remote folders load failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = BrowseHomeAlert(
                title: String(localized: "Saved Folders Unavailable"),
                message: error.userFacingMessage
            )
        }
    }

    func renameShortcut(_ entry: ShortcutEntry, to proposedTitle: String) {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            alert = BrowseHomeAlert(
                title: String(localized: "Shortcut Name Required"),
                message: String(localized: "Enter a display name for this saved remote folder.")
            )
            return
        }

        let shortcutID = entry.shortcut.id.uuidString
        let serverID = entry.shortcut.serverID.uuidString
        let provider = entry.shortcut.providerKind.rawValue
        let path = AppLogSanitizer.path(entry.shortcut.path)
        let sanitizedTitle = AppLogSanitizer.truncated(title)
        logger.info(
            "Saved remote folder rename requested shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public) path=\(path, privacy: .public) title=\(sanitizedTitle, privacy: .public)"
        )

        do {
            try shortcutStore.renameShortcut(id: entry.shortcut.id, title: title)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                var updatedShortcut = entries[index].shortcut
                updatedShortcut.title = title
                updatedShortcut.updatedAt = Date()
                entries[index] = ShortcutEntry(shortcut: updatedShortcut, profile: entries[index].profile)
            }
            logger.info(
                "Saved remote folder rename completed shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public)"
            )
        } catch {
            logger.error(
                "Saved remote folder rename failed shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = BrowseHomeAlert(
                title: String(localized: "Failed to Rename Shortcut"),
                message: error.userFacingMessage
            )
        }
    }

    func removeShortcut(_ entry: ShortcutEntry) {
        let shortcutID = entry.shortcut.id.uuidString
        let serverID = entry.shortcut.serverID.uuidString
        let provider = entry.shortcut.providerKind.rawValue
        let path = AppLogSanitizer.path(entry.shortcut.path)
        logger.info(
            "Saved remote folder remove requested shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public) path=\(path, privacy: .public)"
        )

        do {
            try shortcutStore.removeShortcut(id: entry.shortcut.id)
            entries.removeAll { $0.id == entry.id }
            logger.info(
                "Saved remote folder remove completed shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public)"
            )
        } catch {
            logger.error(
                "Saved remote folder remove failed shortcutID=\(shortcutID, privacy: .public) serverID=\(serverID, privacy: .public) provider=\(provider, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = BrowseHomeAlert(
                title: String(localized: "Failed to Remove Shortcut"),
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
