import SwiftUI

struct BrowseHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let dependencies: AppDependencies

    @ObservedObject private var viewModel: RemoteServerListViewModel
    @Binding private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var navigationRequest: BrowseHomeNavigationRequest?
    @State private var splitSelection: BrowseHomeSplitSelection?
    @State private var splitSyncTask: Task<Void, Never>?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var containerWidth: CGFloat = 0

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
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .readContainerWidth(into: $containerWidth)
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            debounceSplitSync()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: containerWidth) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: displayedProfiles.map(\.id)) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: quickAccessItems.map(\.id)) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: editorDraft?.id) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else {
                return
            }

            handleEditorDismissal()
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
                    synchronizeSplitSelection()
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

    private var usesSplitViewLayout: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularNavigationSplitMinWidth)
    }

    private var compactLayout: some View {
        NavigationStack {
            compactContent
                .navigationTitle("Browse")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    addServerToolbarItem
                }
                .refreshable {
                    viewModel.load()
                }
                .navigationDestination(item: $navigationRequest) { request in
                    navigationDestination(for: request)
                }
        }
    }

    private var compactContent: some View {
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

    private var splitViewLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if displayedProfiles.isEmpty && !showsQuickAccess {
                    BrowseHomeEmptyState(onAddServer: presentCreateServerSheet)
                        .background(Color.surfaceGrouped)
                } else {
                    List(selection: splitSelectionBinding) {
                        splitServersSection

                        if showsQuickAccess {
                            splitQuickAccessSection
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                addServerToolbarItem
            }
            .refreshable {
                viewModel.load()
            }
        } detail: {
            NavigationStack {
                if let splitSelection {
                    splitDetailDestination(for: splitSelection)
                } else {
                    BrowseHomeDetailPlaceholder(
                        hasServers: !displayedProfiles.isEmpty,
                        onAddServer: presentCreateServerSheet
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Servers Section

    @ViewBuilder
    private var serversSection: some View {
        Section {
            ForEach(displayedProfiles) { profile in
                Button {
                    navigationRequest = .serverDetail(profile)
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

    @ViewBuilder
    private var splitServersSection: some View {
        Section("Servers") {
            ForEach(displayedProfiles) { profile in
                Button {
                    splitSelection = .server(profile.id)
                } label: {
                    BrowseHomeServerRow(profile: profile, showsDisclosureIndicator: false)
                }
                .buttonStyle(.plain)
                .tag(BrowseHomeSplitSelection.server(profile.id) as BrowseHomeSplitSelection?)
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
            }
        }
    }

    // MARK: - Quick Access Section

    private var quickAccessSection: some View {
        Section {
            ForEach(quickAccessItems) { item in
                Button {
                    navigationRequest = item.navigationRequest
                } label: {
                    BrowseHomeQuickAccessRow(item: item)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Shortcuts")
        }
    }

    private var splitQuickAccessSection: some View {
        Section("Shortcuts") {
            ForEach(quickAccessItems) { item in
                Button {
                    splitSelection = item.splitSelection
                } label: {
                    BrowseHomeQuickAccessRow(item: item, showsDisclosureIndicator: false)
                }
                .buttonStyle(.plain)
                .tag(item.splitSelection as BrowseHomeSplitSelection?)
            }
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
                    navigationRequest: .savedFolders
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
                    navigationRequest: .offlineShelf
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

    @ViewBuilder
    private func navigationDestination(for request: BrowseHomeNavigationRequest) -> some View {
        switch request {
        case .serverDetail(let profile):
            RemoteServerDetailView(
                profile: profile,
                dependencies: dependencies
            )
        case .savedFolders:
            SavedRemoteFoldersView(dependencies: dependencies)
        case .offlineShelf:
            RemoteOfflineShelfView(dependencies: dependencies)
        }
    }

    @ViewBuilder
    private func splitDetailDestination(for selection: BrowseHomeSplitSelection) -> some View {
        switch selection {
        case .server(let profileID):
            if let profile = displayedProfiles.first(where: { $0.id == profileID }) {
                RemoteServerDetailView(
                    profile: profile,
                    dependencies: dependencies,
                    onRequestEdit: requestEditorPresentation
                )
            } else {
                ContentUnavailableView(
                    "Server Unavailable",
                    systemImage: "server.rack",
                    description: Text("This server is no longer available on this device.")
                )
            }
        case .savedFolders:
            SavedRemoteFoldersView(dependencies: dependencies)
        case .offlineShelf:
            RemoteOfflineShelfView(dependencies: dependencies)
        }
    }

    private func presentCreateServerSheet() {
        requestEditorPresentation(viewModel.makeCreateDraft())
    }

    private func requestEditorPresentation(_ draft: RemoteServerEditorDraft) {
        // Freeze split-view sync while the system sheet is open so the detail
        // column does not change underneath the presenter host.
        splitSyncTask?.cancel()
        splitSyncTask = nil

        if usesSplitViewLayout {
            let editorDraftBinding = _editorDraft
            DispatchQueue.main.async {
                guard editorDraftBinding.wrappedValue == nil else {
                    return
                }

                editorDraftBinding.wrappedValue = draft
            }
        } else {
            editorDraft = draft
        }
    }

    private func debounceSplitSync() {
        guard editorDraft == nil else {
            return
        }

        splitSyncTask?.cancel()
        splitSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            synchronizeSplitSelection()
        }
    }

    private func synchronizeSplitSelection() {
        guard usesSplitViewLayout else {
            splitSelection = nil
            return
        }

        guard editorDraft == nil else {
            return
        }

        let validSelections = Set(
            displayedProfiles.map { BrowseHomeSplitSelection.server($0.id) }
            + quickAccessItems.map(\.splitSelection)
        )

        if let splitSelection, validSelections.contains(splitSelection) {
            return
        }

        splitSelection = displayedProfiles.first.map { .server($0.id) }
            ?? quickAccessItems.first?.splitSelection
    }

    private func handleEditorDismissal() {
        debounceSplitSync()
    }

    private var splitSelectionBinding: Binding<BrowseHomeSplitSelection?> {
        Binding(
            get: { splitSelection },
            set: { newValue in
                guard editorDraft == nil else {
                    return
                }

                splitSelection = newValue
            }
        )
    }
}

// MARK: - Navigation

private enum BrowseHomeNavigationRequest: Identifiable, Hashable {
    case serverDetail(RemoteServerProfile)
    case savedFolders
    case offlineShelf

    var id: String {
        switch self {
        case .serverDetail(let profile):
            return "server:\(profile.id.uuidString)"
        case .savedFolders:
            return "saved-folders"
        case .offlineShelf:
            return "offline-shelf"
        }
    }
}

private enum BrowseHomeSplitSelection: Hashable {
    case server(UUID)
    case savedFolders
    case offlineShelf
}

// MARK: - Supporting Types

private struct BrowseHomeShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let navigationRequest: BrowseHomeNavigationRequest

    var splitSelection: BrowseHomeSplitSelection {
        switch navigationRequest {
        case .serverDetail(let profile):
            return .server(profile.id)
        case .savedFolders:
            return .savedFolders
        case .offlineShelf:
            return .offlineShelf
        }
    }
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

private struct BrowseHomeDetailPlaceholder: View {
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
