import SwiftUI

struct BrowseHomeView: View {
    @Environment(\.appNavigator) private var appNavigator
    @AppStorage(AppNavigationStorageKeys.browseHomeSelection) private var storedSelectionRawValue = ""

    let dependencies: AppDependencies

    @ObservedObject private var viewModel: RemoteServerListViewModel
    @Binding private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var splitSelection: BrowseHomeSplitSelection?

    init(
        dependencies: AppDependencies,
        viewModel: RemoteServerListViewModel,
        editorDraft: Binding<RemoteServerEditorDraft?>
    ) {
        self.dependencies = dependencies
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _editorDraft = editorDraft
    }

    var body: some View {
        content
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            addServerToolbarItem
        }
        .refreshable {
            viewModel.load()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            restoreSelectionIfNeeded()
        }
        .onChange(of: displayedProfiles.map(\.id)) { _, _ in
            restoreSelectionIfNeeded()
        }
        .onChange(of: splitSelection) { _, newValue in
            persistSelection(newValue)
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .confirmationDialog(
            "Delete Server?",
            isPresented: Binding(
                get: { pendingDeletionProfile != nil },
                set: { if !$0 { pendingDeletionProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletionProfile {
                Button("Delete \(pendingDeletionProfile.name)", role: .destructive) {
                    viewModel.delete(pendingDeletionProfile)
                    self.pendingDeletionProfile = nil
                    restoreSelectionIfNeeded()
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionProfile = nil
            }
        } message: {
            if let pendingDeletionProfile {
                Text("This removes \(pendingDeletionProfile.name) and clears its local offline data on this device.")
            }
        }
    }

    private var content: some View {
        Group {
            if displayedProfiles.isEmpty && !showsQuickAccess {
                BrowseHomeEmptyState(onAddServer: presentCreateServerSheet)
            } else {
                List {
                    serversSection

                    if showsQuickAccess {
                        quickAccessSection
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Servers Section

    @ViewBuilder
    private var serversSection: some View {
        Section {
            ForEach(displayedProfiles) { profile in
                Button {
                    open(.server(profile.id))
                } label: {
                    BrowseHomeServerRow(profile: profile)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        requestEditorPresentation(viewModel.makeEditDraft(for: profile))
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        requestEditorPresentation(viewModel.makeEditDraft(for: profile))
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Servers")
        }
    }

    // MARK: - Quick Access Section

    private var quickAccessSection: some View {
        Section {
            ForEach(quickAccessItems) { item in
                Button {
                    open(item.splitSelection)
                } label: {
                    BrowseHomeQuickAccessRow(item: item)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Shortcuts")
        }
    }

    // MARK: - Data

    private var displayedProfiles: [RemoteServerProfile] {
        viewModel.profiles.sorted {
            $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var totalSavedFolderCount: Int {
        viewModel.profiles.reduce(0) { $0 + viewModel.shortcutCount(for: $1) }
    }

    private var totalOfflineCopyCount: Int {
        viewModel.profiles.reduce(0) { $0 + viewModel.cacheSummary(for: $1).fileCount }
    }

    private var showsQuickAccess: Bool {
        !quickAccessItems.isEmpty
    }

    private var quickAccessItems: [BrowseHomeShortcutItem] {
        var items = [BrowseHomeShortcutItem]()

        if totalSavedFolderCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "saved-folders",
                    title: "Saved Folders",
                    subtitle: totalSavedFolderCount == 1 ? "1 saved" : "\(totalSavedFolderCount) saved",
                    systemImage: "star.fill",
                    tint: .teal,
                    splitSelection: .savedFolders
                )
            )
        }

        if totalOfflineCopyCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "offline-shelf",
                    title: "Offline Shelf",
                    subtitle: totalOfflineCopyCount == 1 ? "1 downloaded" : "\(totalOfflineCopyCount) downloaded",
                    systemImage: "arrow.down.circle.fill",
                    tint: .green,
                    splitSelection: .offlineShelf
                )
            )
        }

        return items
    }

    @ToolbarContentBuilder
    private var addServerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: presentCreateServerSheet) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Remote Server")
        }
    }

    private func presentCreateServerSheet() {
        requestEditorPresentation(viewModel.makeCreateDraft())
    }

    private func requestEditorPresentation(_ draft: RemoteServerEditorDraft) {
        editorDraft = draft
    }

    private func persistSelection(_ selection: BrowseHomeSplitSelection?) {
        storedSelectionRawValue = selection?.storageValue ?? ""
    }

    private func restoreSelectionIfNeeded() {
        guard splitSelection == nil else {
            return
        }

        let restoredSelection = BrowseHomeSplitSelection(storageValue: storedSelectionRawValue)
        let validSelections = Set(
            displayedProfiles.map { BrowseHomeSplitSelection.server($0.id) }
            + quickAccessItems.map(\.splitSelection)
        )
        if let restoredSelection, validSelections.contains(restoredSelection) {
            splitSelection = restoredSelection
        }
    }

    private func open(_ selection: BrowseHomeSplitSelection) {
        splitSelection = selection
        switch selection {
        case .server(let profileID):
            appNavigator?.navigate(.browse(.serverDetail(profileID)))
        case .savedFolders:
            appNavigator?.navigate(.browse(.savedFolders(nil)))
        case .offlineShelf:
            appNavigator?.navigate(.browse(.offlineShelf(nil)))
        }
    }
}

// MARK: - Navigation

private enum BrowseHomeSplitSelection: Hashable {
    case server(UUID)
    case savedFolders
    case offlineShelf

    init?(storageValue: String) {
        if storageValue == "saved-folders" {
            self = .savedFolders
            return
        }

        if storageValue == "offline-shelf" {
            self = .offlineShelf
            return
        }

        let prefix = "server:"
        guard storageValue.hasPrefix(prefix) else {
            return nil
        }

        let rawIdentifier = String(storageValue.dropFirst(prefix.count))
        guard let serverID = UUID(uuidString: rawIdentifier) else {
            return nil
        }

        self = .server(serverID)
    }

    var storageValue: String {
        switch self {
        case .server(let serverID):
            return "server:\(serverID.uuidString)"
        case .savedFolders:
            return "saved-folders"
        case .offlineShelf:
            return "offline-shelf"
        }
    }
}

// MARK: - Supporting Types

private struct BrowseHomeShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let splitSelection: BrowseHomeSplitSelection
}

// MARK: - Server Row

private struct BrowseHomeServerRow: View {
    let profile: RemoteServerProfile
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: protocolSystemImage,
                tint: profile.providerKind.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(profile.displayTitle)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xxs) {
                    Text(profile.endpointDisplaySummary)
                        .lineLimit(1)
                }
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }

    private var protocolSystemImage: String {
        switch profile.providerKind {
        case .smb:
            return "externaldrive.connected.to.line.below"
        case .webdav:
            return "globe"
        }
    }
}

// MARK: - Quick Access Row

private struct BrowseHomeQuickAccessRow: View {
    let item: BrowseHomeShortcutItem
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(systemImage: item.systemImage, tint: item.tint)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)

                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

private struct BrowseHomeEmptyState: View {
    let onAddServer: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "server.rack",
            title: "No Servers",
            description: "Add a server to browse comics.",
            actionTitle: "Add Server",
            action: onAddServer
        )
    }
}

struct BrowseHomeDetailPlaceholder: View {
    let hasServers: Bool
    let onAddServer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                hasServers ? "Select a Server" : "Add a Server",
                systemImage: "server.rack"
            )
        } description: {
            Text(
                hasServers
                    ? "Choose a server or shortcut."
                    : "Add a server to browse comics."
            )
        } actions: {
            if !hasServers {
                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceGrouped)
    }
}
