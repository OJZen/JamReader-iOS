import SwiftUI

private enum BrowseLayoutMetrics {
    static let iconSize: CGFloat = 32
}

struct BrowseHomeView: View {

    let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var navigationRequest: BrowseHomeNavigationRequest?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: RemoteServerListViewModel(
                profileStore: dependencies.remoteServerProfileStore,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedProfiles.isEmpty && !showsQuickAccess {
                    EmptyStateView(
                        systemImage: "server.rack",
                        title: "No Servers",
                        description: "Add a remote server to browse your comic library over the network.",
                        actionTitle: "Add Server"
                    ) {
                        editorDraft = viewModel.makeCreateDraft()
                    }
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
            .navigationTitle("浏览")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorDraft = viewModel.makeCreateDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Remote Server")
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
            .sheet(item: $editorDraft) { draft in
                RemoteServerEditorSheet(draft: draft) { updatedDraft in
                    let result = viewModel.save(draft: updatedDraft)
                    if case .success = result {
                        editorDraft = nil
                    }
                    return result
                }
            }
            .alert(item: $viewModel.alert) { alert in
                makeRemoteAlert(for: alert)
            }
            .navigationDestination(item: $navigationRequest) { request in
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
                        editorDraft = viewModel.makeEditDraft(for: profile)
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
                        editorDraft = viewModel.makeEditDraft(for: profile)
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
                    navigationRequest = item.navigationRequest
                } label: {
                    BrowseHomeQuickAccessRow(item: item)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Quick Access")
        }
    }

    // MARK: - Data

    private var displayedProfiles: [RemoteServerProfile] {
        viewModel.profiles.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
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
                    subtitle: "\(totalSavedFolderCount) bookmarked",
                    systemImage: "star.fill",
                    tint: .teal,
                    badgeCount: totalSavedFolderCount,
                    navigationRequest: .savedFolders
                )
            )
        }

        if totalOfflineCopyCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "offline-shelf",
                    title: "Offline Shelf",
                    subtitle: "\(totalOfflineCopyCount) cached",
                    systemImage: "arrow.down.circle.fill",
                    tint: .green,
                    badgeCount: totalOfflineCopyCount,
                    navigationRequest: .offlineShelf
                )
            )
        }

        return items
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

// MARK: - Supporting Types

private struct BrowseHomeShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let badgeCount: Int
    let navigationRequest: BrowseHomeNavigationRequest
}

// MARK: - Server Row

private struct BrowseHomeServerRow: View {
    let profile: RemoteServerProfile

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: protocolSystemImage)
                .font(AppFont.body(.semibold))
                .foregroundStyle(.white)
                .frame(
                    width: BrowseLayoutMetrics.iconSize,
                    height: BrowseLayoutMetrics.iconSize
                )
                .background(
                    profile.providerKind.tintColor,
                    in: RoundedRectangle(
                        cornerRadius: CornerRadius.sm,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(profile.name)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xxs) {
                    Text(profile.endpointDisplaySummary)
                        .lineLimit(1)

                    Text("·")

                    Text(profile.providerKind.title)
                }
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.right")
                .font(AppFont.caption2(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(AppFont.body(.semibold))
                .foregroundStyle(.white)
                .frame(
                    width: BrowseLayoutMetrics.iconSize,
                    height: BrowseLayoutMetrics.iconSize
                )
                .background(
                    item.tint,
                    in: RoundedRectangle(
                        cornerRadius: CornerRadius.sm,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)

                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            Text("\(item.badgeCount)")
                .font(AppFont.subheadline())
                .foregroundStyle(Color.textSecondary)

            Image(systemName: "chevron.right")
                .font(AppFont.caption2(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}
