import SwiftUI

struct RemoteServerDetailView: View {
    @Environment(\.dismiss) private var dismiss

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var profile: RemoteServerProfile
    @State private var recentSessions: [RemoteComicReadingSession] = []
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var isShowingActions = false
    @State private var pendingAction: RemoteServerDetailPendingAction?
    @State private var navigationRequest: RemoteServerDetailNavigationRequest?

    init(profile: RemoteServerProfile, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _profile = State(initialValue: profile)
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
            Section {
                NavigationLink {
                    RemoteServerBrowserView(
                        profile: profile,
                        currentPath: RemoteServerBrowserViewModel.lastBrowsedPath(for: profile),
                        dependencies: dependencies
                    )
                } label: {
                    serverStatusCard
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("Recent Comics") {
                if recentSessions.isEmpty {
                    ContentUnavailableView(
                        "No Browsing History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Open a comic from this SMB server and it will appear here.")
                    )
                    .padding(.vertical, 24)
                } else {
                    ForEach(recentSessions) { session in
                        NavigationLink {
                            RemoteComicLoadingView(
                                profile: profile,
                                item: session.directoryItem,
                                dependencies: dependencies
                            )
                        } label: {
                            RemoteOfflineComicCard(
                                session: session,
                                profile: profile,
                                availability: dependencies.remoteServerBrowsingService.cachedAvailability(
                                    for: session.comicFileReference
                                ),
                                showsNavigationIndicator: true,
                                showsServerName: false
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingActions = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Server Actions")
            }
        }
        .task {
            viewModel.loadIfNeeded()
            refreshDetailState()
        }
        .onAppear {
            refreshDetailState()
        }
        .refreshable {
            refreshDetailState(forceReload: true)
        }
        .sheet(item: $editorDraft) { draft in
            RemoteServerEditorSheet(draft: draft) { updatedDraft in
                let result = viewModel.save(draft: updatedDraft)
                if case .success = result {
                    editorDraft = nil
                    refreshDetailState(forceReload: true)
                }
                return result
            }
        }
        .sheet(isPresented: $isShowingActions) {
            RemoteServerActionsSheet(
                profile: profile,
                savedFolderCount: viewModel.shortcutCount(for: profile),
                offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount,
                cacheSummary: viewModel.cacheSummary(for: profile),
                onDone: { isShowingActions = false },
                onEdit: {
                    pendingAction = .edit
                    isShowingActions = false
                },
                onOpenSavedFolders: {
                    pendingAction = .openSavedFolders
                    isShowingActions = false
                },
                onOpenOfflineShelf: {
                    pendingAction = .openOfflineShelf
                    isShowingActions = false
                },
                onClearCache: {
                    pendingAction = .clearCache
                    isShowingActions = false
                },
                onDelete: {
                    pendingAction = .delete
                    isShowingActions = false
                }
            )
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .navigationDestination(item: $navigationRequest) { request in
            switch request {
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
        .onChange(of: isShowingActions) { _, isShowing in
            guard !isShowing, let pendingAction else {
                return
            }

            self.pendingAction = nil
            switch pendingAction {
            case .edit:
                editorDraft = viewModel.makeEditDraft(for: profile)
            case .openSavedFolders:
                navigationRequest = .savedFolders(profile)
            case .openOfflineShelf:
                navigationRequest = .offlineShelf(profile)
            case .clearCache:
                viewModel.clearCache(for: profile)
                refreshDetailState(forceReload: true)
            case .delete:
                viewModel.delete(profile)
                dismiss()
            }
        }
    }

    private var serverStatusCard: some View {
        SectionSummaryCard(
            title: "Open SMB Browser",
            badges: statusBadges,
            titleFont: .title3.weight(.semibold),
            cornerRadius: 20,
            contentPadding: 16,
            strokeOpacity: 0.04
        ) {
            SummaryMetricGroup(
                metrics: [
                    SummaryMetricItem(
                        title: "History",
                        value: "\(recentSessions.count)",
                        tint: .blue
                    ),
                    SummaryMetricItem(
                        title: "Saved",
                        value: "\(viewModel.shortcutCount(for: profile))",
                        tint: .teal
                    ),
                    SummaryMetricItem(
                        title: "Offline",
                        value: "\(viewModel.cacheSummary(for: profile).fileCount)",
                        tint: .green
                    )
                ],
                style: .compactValue,
                horizontalSpacing: 8,
                verticalSpacing: 8
            )

            FormOverviewContent(
                items: [
                    FormOverviewItem(title: "Host", value: profile.normalizedHost),
                    FormOverviewItem(title: "Share", value: profile.shareDisplaySummary),
                    FormOverviewItem(title: "Folder", value: browserEntryPath)
                ]
            )

            Label("Tap to browse this server", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
        }
    }

    private var statusBadges: [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(title: profile.providerKind.title, tint: profile.providerKind.tintColor),
            StatusBadgeItem(
                title: profile.authenticationMode.title,
                tint: profile.authenticationMode == .guest ? .orange : .green
            )
        ]

        if !profile.usesDefaultPort {
            badges.append(StatusBadgeItem(title: ":\(profile.port)", tint: .teal))
        }

        return badges
    }

    private var browserEntryPath: String {
        let lastPath = RemoteServerBrowserViewModel.lastBrowsedPath(for: profile)
        return lastPath.isEmpty ? "/" : lastPath
    }

    private func refreshDetailState(forceReload: Bool = false) {
        if forceReload {
            viewModel.load()
        }

        if let updatedProfile = viewModel.profile(withID: profile.id) {
            profile = updatedProfile
        }

        recentSessions = viewModel.recentSessions(for: profile)
    }
}

private enum RemoteServerDetailPendingAction {
    case edit
    case openSavedFolders
    case openOfflineShelf
    case clearCache
    case delete
}

private enum RemoteServerDetailNavigationRequest: Identifiable, Hashable {
    case savedFolders(RemoteServerProfile)
    case offlineShelf(RemoteServerProfile)

    var id: String {
        switch self {
        case .savedFolders(let profile):
            return "saved:\(profile.id.uuidString)"
        case .offlineShelf(let profile):
            return "offline:\(profile.id.uuidString)"
        }
    }
}
