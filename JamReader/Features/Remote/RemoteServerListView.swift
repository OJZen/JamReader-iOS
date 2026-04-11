import SwiftUI

struct RemoteServerListView: View {
    private enum LayoutMetrics {
        static let rowAccessoryReservedWidth: CGFloat = 36
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var navigationRequest: RemoteServerListNavigationRequest?
    @State private var containerWidth: CGFloat = 0

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
        List {
            if viewModel.profiles.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Remote Servers",
                        systemImage: "server.rack",
                        description: Text("Add a server to browse comics.")
                    )
                    .padding(.vertical, 24)
                }
            } else {
                Section("Servers") {
                    ForEach(viewModel.profiles) { profile in
                        Button {
                            navigationRequest = .detail(profile)
                        } label: {
                            RemoteServerRow(
                                profile: profile,
                                recentHistoryCount: viewModel.recentSessions(for: profile).count,
                                savedFolderCount: viewModel.shortcutCount(for: profile),
                                offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount,
                                trailingAccessoryReservedWidth: persistentRowActionReservedWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            if showsPersistentRowActions {
                                persistentActionMenu(for: profile)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Remote Servers")
        .navigationBarTitleDisplayMode(.inline)
        .readContainerWidth(into: $containerWidth)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorDraft = viewModel.makeCreateDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
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
            remoteServerEditor(for: draft)
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .navigationDestination(item: $navigationRequest) { request in
            switch request {
            case .detail(let profile):
                RemoteServerDetailView(
                    profile: profile,
                    dependencies: dependencies
                )
            case .savedFolders(let profile):
                SavedRemoteFoldersView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            case .offlineShelf(let profile):
                RemoteOfflineShelfView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            }
        }
    }

    private var showsPersistentRowActions: Bool {
        horizontalSizeClass == .regular
            && containerWidth >= AppLayout.regularInlineActionMinWidth
    }

    private var persistentRowActionReservedWidth: CGFloat {
        showsPersistentRowActions ? LayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private func remoteServerEditor(
        for draft: RemoteServerEditorDraft
    ) -> some View {
        RemoteServerEditorSheet(draft: draft) { updatedDraft in
            let alertState = viewModel.save(draft: updatedDraft)
            if alertState == nil {
                editorDraft = nil
            }
            return alertState
        }
        .id(draft.id)
    }

    @ViewBuilder
    private func remoteServerActionMenuContent(
        for profile: RemoteServerProfile
    ) -> some View {
        let savedFolderCount = viewModel.shortcutCount(for: profile)
        let offlineCopyCount = viewModel.cacheSummary(for: profile).fileCount
        let recentHistoryCount = viewModel.recentSessions(for: profile).count
        let cacheSummary = viewModel.cacheSummary(for: profile)

        Button {
            editorDraft = viewModel.makeEditDraft(for: profile)
        } label: {
            Label("Edit Server", systemImage: "square.and.pencil")
        }

        if savedFolderCount > 0 {
            Button {
                navigationRequest = .savedFolders(profile)
            } label: {
                Label(
                    savedFolderCount == 1 ? "Saved Folder" : "Saved Folders",
                    systemImage: "star"
                )
            }
        }

        if offlineCopyCount > 0 {
            Button {
                navigationRequest = .offlineShelf(profile)
            } label: {
                Label(
                    offlineCopyCount == 1 ? "Offline Copy" : "Offline Shelf",
                    systemImage: "arrow.down.circle"
                )
            }
        }

        if recentHistoryCount > 0 {
            Button(role: .destructive) {
                viewModel.clearRecentHistory(for: profile)
            } label: {
                Label("Clear History", systemImage: "clock.arrow.circlepath")
            }
        }

        if !cacheSummary.isEmpty {
            Button(role: .destructive) {
                viewModel.clearCache(for: profile)
            } label: {
                Label("Clear Downloads", systemImage: "trash")
            }
        }

        Button(role: .destructive) {
            viewModel.delete(profile)
        } label: {
            Label("Delete Server", systemImage: "trash")
        }
    }

    private func persistentActionMenu(for profile: RemoteServerProfile) -> some View {
        Menu {
            remoteServerActionMenuContent(for: profile)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(profile.displayTitle)")
    }
}

struct RemoteServerRow: View {
    let profile: RemoteServerProfile
    let recentHistoryCount: Int
    let savedFolderCount: Int
    let offlineCopyCount: Int
    var trailingAccessoryReservedWidth: CGFloat = 0

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

                Text(connectionSummary)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                if let statusSummary {
                    Text(statusSummary)
                        .font(AppFont.caption())
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.right")
                .font(AppFont.caption2(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .padding(.trailing, trailingAccessoryReservedWidth)
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

    private var connectionSummary: String {
        profile.endpointDisplaySummary.isEmpty
            ? profile.providerKind.title
            : profile.endpointDisplaySummary
    }

    private var statusSummary: String? {
        let segments = [
            savedFolderCount > 0 ? "\(savedFolderCount) saved" : nil,
            offlineCopyCount > 0 ? "\(offlineCopyCount) downloaded" : nil
        ]
        .compactMap { $0 }

        if !segments.isEmpty {
            return segments.joined(separator: " · ")
        }

        guard recentHistoryCount > 0 else {
            return nil
        }

        return recentHistoryCount == 1 ? "1 recent" : "\(recentHistoryCount) recent"
    }
}

extension RemoteServerProfile {
    var endpointDisplaySummary: String {
        endpointDisplayHost
    }

    var shareDisplaySummary: String {
        providerRootDisplayPath
    }
}


private enum RemoteServerListNavigationRequest: Identifiable, Hashable {
    case detail(RemoteServerProfile)
    case savedFolders(RemoteServerProfile)
    case offlineShelf(RemoteServerProfile)

    var id: String {
        switch self {
        case .detail(let profile):
            return "detail:\(profile.id.uuidString)"
        case .savedFolders(let profile):
            return "saved:\(profile.id.uuidString)"
        case .offlineShelf(let profile):
            return "offline:\(profile.id.uuidString)"
        }
    }
}
