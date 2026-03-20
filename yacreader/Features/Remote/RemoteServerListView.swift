import SwiftUI

struct RemoteServerListView: View {
    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var actionsProfile: RemoteServerProfile?
    @State private var pendingAction: PendingRemoteServerAction?
    @State private var navigationRequest: RemoteServerListNavigationRequest?

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
            summarySection

            if viewModel.profiles.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No SMB Servers",
                        systemImage: "server.rack",
                        description: Text("Add an SMB server to start browsing.")
                    )
                    .padding(.vertical, 24)
                }
            } else {
                Section("Saved Servers") {
                    ForEach(viewModel.profiles) { profile in
                        NavigationLink {
                            RemoteServerBrowserView(
                                profile: profile,
                                currentPath: RemoteServerBrowserViewModel.lastBrowsedPath(for: profile),
                                dependencies: dependencies
                            )
                        } label: {
                            RemoteServerRow(
                                profile: profile,
                                latestSession: viewModel.latestSession(for: profile),
                                savedFolderCount: viewModel.shortcutCount(for: profile),
                                offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount,
                                trailingAccessoryReservedWidth: 88
                            )
                        }
                        .overlay(alignment: .trailing) {
                            RemoteServerManageButton {
                                actionsProfile = profile
                            }
                            .padding(.trailing, 6)
                        }
                    }
                }
            }
        }
        .navigationTitle("Remote Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorDraft = viewModel.makeCreateDraft()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.refreshRecentActivity()
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
        .sheet(item: $actionsProfile) { profile in
            RemoteServerActionsSheet(
                profile: profile,
                savedFolderCount: viewModel.shortcutCount(for: profile),
                offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount,
                cacheSummary: viewModel.cacheSummary(for: profile),
                onDone: { actionsProfile = nil },
                onEdit: {
                    pendingAction = .edit(profile)
                    actionsProfile = nil
                },
                onOpenSavedFolders: {
                    pendingAction = .openSavedFolders(profile)
                    actionsProfile = nil
                },
                onOpenOfflineShelf: {
                    pendingAction = .openOfflineShelf(profile)
                    actionsProfile = nil
                },
                onClearCache: {
                    pendingAction = .clearCache(profile)
                    actionsProfile = nil
                },
                onDelete: {
                    pendingAction = .delete(profile)
                    actionsProfile = nil
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
        .onChange(of: actionsProfile) { _, newValue in
            guard newValue == nil, let pendingAction else {
                return
            }

            self.pendingAction = nil
            switch pendingAction {
            case .edit(let profile):
                editorDraft = viewModel.makeEditDraft(for: profile)
            case .openSavedFolders(let profile):
                navigationRequest = .savedFolders(profile)
            case .openOfflineShelf(let profile):
                navigationRequest = .offlineShelf(profile)
            case .clearCache(let profile):
                viewModel.clearCache(for: profile)
            case .delete(let profile):
                viewModel.delete(profile)
            }
        }
    }

    private var summarySection: some View {
        Section {
            SectionSummaryCard(
                title: "Manage SMB Servers",
                titleFont: .headline,
                cornerRadius: 20,
                contentPadding: 16,
                strokeOpacity: 0.04
            ) {
                SummaryMetricGroup(
                    metrics: [
                        SummaryMetricItem(title: "Servers", value: viewModel.serverCountText, tint: .blue),
                        SummaryMetricItem(title: "Saved Folders", value: viewModel.shortcutCountText, tint: .teal),
                        SummaryMetricItem(title: "Recent", value: viewModel.recentServerCountText, tint: .green)
                    ],
                    style: .compactValue,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                )
            }
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

struct RemoteServerRow: View {
    let profile: RemoteServerProfile
    let latestSession: RemoteComicReadingSession?
    let savedFolderCount: Int
    let offlineCopyCount: Int
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: profile.providerKind.systemImage)
                .font(.title3)
                .foregroundStyle(profile.providerKind.tintColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)

                RemoteServerMetadataRow(
                    title: "Host",
                    value: profile.normalizedHost
                )

                RemoteServerMetadataRow(
                    title: "Share",
                    value: profile.shareDisplaySummary,
                    lineLimit: 2
                )

                if let latestSession {
                    RemoteServerMetadataRow(
                        title: "Recent",
                        value: "\(latestSession.displayName) · \(latestSession.progressText)",
                        lineLimit: 2
                    )
                }

                RemoteServerStatusBadgeRow(profile: profile)

                AdaptiveStatusBadgeGroup(
                    badges: storageBadges,
                    horizontalSpacing: 6,
                    verticalSpacing: 6
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    private var storageBadges: [StatusBadgeItem] {
        var badges: [StatusBadgeItem] = []

        if savedFolderCount > 0 {
            badges.append(
                StatusBadgeItem(
                    title: savedFolderCount == 1 ? "1 saved folder" : "\(savedFolderCount) saved folders",
                    tint: .teal
                )
            )
        }

        if offlineCopyCount > 0 {
            badges.append(
                StatusBadgeItem(
                    title: offlineCopyCount == 1 ? "1 offline copy" : "\(offlineCopyCount) offline copies",
                    tint: .blue
                )
            )
        }

        return badges
    }
}

private struct RemoteServerManageButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remote Server Actions")
    }
}

struct RemoteServerActionsSheet: View {
    let profile: RemoteServerProfile
    let savedFolderCount: Int
    let offlineCopyCount: Int
    let cacheSummary: RemoteComicCacheSummary
    let onDone: () -> Void
    let onEdit: () -> Void
    let onOpenSavedFolders: () -> Void
    let onOpenOfflineShelf: () -> Void
    let onClearCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(profile.name)
                        .font(.headline)

                    RemoteServerStatusBadgeRow(profile: profile, showsPortBadge: false)

                    RemoteServerMetadataRow(
                        title: "Host",
                        value: profile.normalizedHost
                    )

                    RemoteServerMetadataRow(
                        title: "Share",
                        value: profile.shareDisplaySummary,
                        lineLimit: 2
                    )
                }

                Section("Manage") {
                    Button(action: onEdit) {
                        Label("Edit SMB Server", systemImage: "square.and.pencil")
                    }
                }

                if savedFolderCount > 0 || offlineCopyCount > 0 {
                    Section("Browse") {
                        if savedFolderCount > 0 {
                            Button(action: onOpenSavedFolders) {
                                Label(
                                    savedFolderCount == 1 ? "Open Saved Folder" : "Open Saved Folders",
                                    systemImage: "star"
                                )
                            }
                        }

                        if offlineCopyCount > 0 {
                            Button(action: onOpenOfflineShelf) {
                                Label(
                                    offlineCopyCount == 1 ? "Open Offline Copy" : "Open Offline Shelf",
                                    systemImage: "arrow.down.circle"
                                )
                            }
                        }
                    }
                }

                Section("Storage") {
                    LabeledContent("Downloaded Cache") {
                        Text(cacheSummary.isEmpty ? "None" : cacheSummary.summaryText)
                            .foregroundStyle(.secondary)
                    }

                    if !cacheSummary.isEmpty {
                        Button(role: .destructive, action: onClearCache) {
                            Label("Clear Download Cache", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete SMB Server", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Server Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct RemoteServerStatusBadgeRow: View {
    let profile: RemoteServerProfile
    var showsPortBadge = true

    var body: some View {
        AdaptiveStatusBadgeGroup(
            badges: statusBadges,
            horizontalSpacing: 6,
            verticalSpacing: 6
        )
    }

    private var statusBadges: [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(title: profile.providerKind.title, tint: profile.providerKind.tintColor),
            StatusBadgeItem(
                title: profile.authenticationMode.title,
                tint: profile.authenticationMode == .guest ? .orange : .green
            )
        ]

        if showsPortBadge, !profile.usesDefaultPort {
            badges.append(StatusBadgeItem(title: ":\(profile.port)", tint: .teal))
        }

        return badges
    }
}

struct RemoteServerMetadataRow: View {
    let title: String
    let value: String
    var lineLimit = 1

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(lineLimit)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

extension RemoteServerProfile {
    var shareDisplaySummary: String {
        let shareComponent = normalizedShareName.isEmpty ? "" : "/\(normalizedShareName)"
        let combinedPath = "\(shareComponent)\(normalizedBaseDirectoryPath)"
        return combinedPath.isEmpty ? "/" : combinedPath
    }
}

private enum PendingRemoteServerAction {
    case edit(RemoteServerProfile)
    case openSavedFolders(RemoteServerProfile)
    case openOfflineShelf(RemoteServerProfile)
    case clearCache(RemoteServerProfile)
    case delete(RemoteServerProfile)
}

private enum RemoteServerListNavigationRequest: Identifiable, Hashable {
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

struct RemoteServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RemoteServerEditorDraft) -> Result<Void, RemoteAlertState>

    @State private var draft: RemoteServerEditorDraft
    @State private var alert: RemoteAlertState?
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: RemoteServerEditorDraft,
        onSave: @escaping (RemoteServerEditorDraft) -> Result<Void, RemoteAlertState>
    ) {
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $draft.name)
                        .focused($isNameFieldFocused)

                    TextField("Host", text: $draft.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Port", text: $draft.portText)
                        .keyboardType(.numberPad)

                    TextField("Share", text: $draft.shareName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Base directory", text: $draft.baseDirectoryPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("Base directory is optional. Example: `/Manga/Weekly`.")
                }

                Section {
                    Picker("Mode", selection: $draft.authenticationMode) {
                        ForEach(RemoteServerAuthenticationMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }

                    if draft.authenticationMode.requiresUsername {
                        TextField("Username", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if draft.authenticationMode.requiresPassword {
                        SecureField(
                            draft.hasStoredPassword
                                ? "Password (leave blank to keep current)"
                                : "Password",
                            text: $draft.password
                        )
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    if draft.authenticationMode.requiresPassword, draft.hasStoredPassword {
                        Text("Leave password empty to keep the saved Keychain credential.")
                    }
                }
            }
            .navigationTitle(draft.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.actionTitle) {
                        switch onSave(draft) {
                        case .success:
                            break
                        case .failure(let alertState):
                            alert = alertState
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert(item: $alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .task {
            guard !Task.isCancelled else {
                return
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else {
                return
            }

            isNameFieldFocused = true
        }
    }
}

struct RemoteServerBrowserView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerBrowserViewModel
    @State private var displayMode: LibraryComicDisplayMode = .list
    @State private var hasConfiguredDisplayMode = false
    @State private var sortMode: RemoteDirectorySortMode = .nameAscending
    @State private var hasConfiguredSortMode = false
    @State private var searchText = ""
    @State private var importRequest: RemoteBrowserImportRequest?
    @State private var navigationRequest: RemoteBrowserNavigationRequest?
    @State private var pendingOfflineRemoval: PendingRemoteOfflineRemoval?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var visibleComicIDs: Set<String> = []

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: RemoteServerBrowserViewModel(
                profile: profile,
                currentPath: currentPath,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore,
                importedComicsImportService: dependencies.importedComicsImportService,
                folderShortcutStore: dependencies.remoteFolderShortcutStore
            )
        )
    }

    var body: some View {
        browserContent
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { browserToolbar }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: thumbnailPreheatRequestID) {
            await preheatVisibleThumbnails()
        }
        .onAppear {
            viewModel.refreshProgressState()
            viewModel.refreshShortcutState()
            configureDisplayModeIfNeeded()
            configureSortModeIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.feedback?.id) { _, _ in
            scheduleFeedbackDismissalIfNeeded()
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
            visibleComicIDs.removeAll()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Filter this SMB folder"
        )
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let activeImportDescription = viewModel.activeImportDescription {
                    RemoteBrowserImportProgressView(description: activeImportDescription)
                }

                if let feedback = viewModel.feedback {
                    RemoteBrowserFeedbackCard(
                        feedback: feedback,
                        onPrimaryAction: feedback.primaryAction.map { action in
                            {
                                viewModel.dismissFeedback()
                                handleRemoteAlertPrimaryAction(action)
                            }
                        },
                        onDismiss: {
                            viewModel.dismissFeedback()
                        }
                    )
                }
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert, onPrimaryAction: handleRemoteAlertPrimaryAction(_:))
        }
        .confirmationDialog(
            pendingOfflineRemoval?.title ?? "Remove downloaded copies?",
            isPresented: Binding(
                get: { pendingOfflineRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingOfflineRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingOfflineRemoval {
                Button(pendingOfflineRemoval.buttonTitle, role: .destructive) {
                    viewModel.removeOfflineCopies(for: pendingOfflineRemoval.items)
                    self.pendingOfflineRemoval = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingOfflineRemoval = nil
            }
        } message: {
            if let pendingOfflineRemoval {
                Text(pendingOfflineRemoval.message)
            }
        }
        .sheet(item: $importRequest, content: importSheet)
        .navigationDestination(item: $navigationRequest, destination: navigationDestination)
    }

    @ViewBuilder
    private var browserContent: some View {
        if displayMode == .grid {
            gridBody
        } else {
            listBody
        }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.toggleCurrentFolderShortcut()
            } label: {
                Image(systemName: viewModel.isCurrentFolderSaved ? "star.fill" : "star")
            }

            Button {
                toggleDisplayMode()
            } label: {
                Image(systemName: alternateDisplayMode.systemImageName)
            }
            .accessibilityLabel("Switch to \(alternateDisplayMode.title) View")

            Menu {
                Section("Sort") {
                    ForEach(RemoteDirectorySortMode.allCases) { mode in
                        Button {
                            applySortMode(mode)
                        } label: {
                            HStack {
                                Label(mode.title, systemImage: mode.systemImageName)

                                if sortMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func importSheet(for request: RemoteBrowserImportRequest) -> some View {
        switch request {
        case .comic:
            LibraryImportDestinationSheet(
                title: request.destinationPickerTitle,
                message: request.destinationPickerMessage,
                dependencies: dependencies,
                preferredSelection: nil
            ) { selection in
                Task {
                    await performImport(
                        request,
                        destinationSelection: selection,
                        scope: .currentFolderOnly
                    )
                }
            }
        case .currentFolder, .directory:
            RemoteImportOptionsSheet(
                title: request.destinationPickerTitle,
                message: request.destinationPickerMessage,
                confirmLabel: "Import",
                availableScopes: availableImportScopes(for: request),
                defaultScope: defaultImportScope(for: request),
                dependencies: dependencies,
                preferredSelection: nil
            ) { selection, scope in
                Task {
                    await performImport(
                        request,
                        destinationSelection: selection,
                        scope: scope
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func navigationDestination(for request: RemoteBrowserNavigationRequest) -> some View {
        switch request {
        case .directory(let path):
            RemoteServerBrowserView(
                profile: viewModel.profile,
                currentPath: path,
                dependencies: dependencies
            )
        case .comic(let item, let openMode):
            RemoteComicLoadingView(
                profile: viewModel.profile,
                item: item,
                dependencies: dependencies,
                openMode: openMode
            )
        }
    }

    private var listBody: some View {
        List {
            summarySection
            listContentSections
        }
    }

    private var gridBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                gridContentSections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var summarySection: some View {
        Section {
            summaryCard
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }

    private var summaryCard: some View {
        SectionSummaryCard(
            title: viewModel.profile.name,
            badges: summaryBadges,
            titleFont: .title3.weight(.semibold),
            cornerRadius: 20,
            contentPadding: 16,
            strokeOpacity: 0.04
        ) {
            summaryContent
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormOverviewContent(items: browserOverviewItems)

            if showsFolderActionCluster {
                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        upOneLevelButton
                        sessionRootButton
                        contentActionsMenu
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        upOneLevelButton
                        sessionRootButton
                        contentActionsMenu
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listContentSections: some View {
        if viewModel.isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Connecting to SMB Share")
                        .padding(.vertical, 20)
                    Spacer()
                }
            }
        } else if viewModel.loadIssue != nil {
            Section {
                remoteErrorContent()
            }
        } else if viewModel.items.isEmpty {
            Section {
                browserUnavailableContent(
                    title: "No Remote Files",
                    systemImage: "folder",
                    description: emptyFolderDescription
                )
            }
        } else if !hasVisibleItems {
            Section {
                browserUnavailableContent(
                    title: "No Matches",
                    systemImage: "magnifyingglass",
                    description: noMatchesDescription
                )
            }
        } else {
            if !displayedDirectories.isEmpty {
                Section("Folders") {
                    ForEach(displayedDirectories) { item in
                        Button {
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteDirectoryItemListRow(
                                item: item,
                                readingSession: nil,
                                cacheAvailability: .unavailable,
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService,
                                trailingAccessoryReservedWidth: 46
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            browserItemActionMenuButton(for: item)
                            .padding(.trailing, 4)
                        }
                    }
                }
            }

            if !displayedComicFiles.isEmpty {
                Section {
                    ForEach(displayedComicFiles) { item in
                        let availability = viewModel.cacheAvailability(for: item)

                        Button {
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteDirectoryItemListRow(
                                item: item,
                                readingSession: viewModel.progress(for: item),
                                cacheAvailability: availability,
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService,
                                trailingAccessoryReservedWidth: 46
                            )
                        }
                        .onAppear {
                            markComicVisible(item)
                        }
                        .onDisappear {
                            markComicInvisible(item)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            browserItemActionMenuButton(for: item)
                            .padding(.trailing, 4)
                        }
                    }
                } header: {
                    Text("Comic Files")
                } footer: {
                    if let unsupportedFilesNoticeText {
                        Text(unsupportedFilesNoticeText)
                    }
                }
            }
        }
    }

    private var summaryBadges: [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: viewModel.capabilities.providerKind.title,
                tint: viewModel.capabilities.providerKind.tintColor
            ),
            StatusBadgeItem(title: displayMode.title, tint: .blue),
            StatusBadgeItem(title: sortMode.shortTitle, tint: .teal)
        ]

        if viewModel.isCurrentFolderSaved {
            badges.append(StatusBadgeItem(title: "Saved", tint: .yellow))
        }

        if !trimmedSearchText.isEmpty {
            badges.append(StatusBadgeItem(title: "Filtering", tint: .orange))
        }

        return badges
    }

    private var browserOverviewItems: [FormOverviewItem] {
        [
            FormOverviewItem(title: "Location", value: viewModel.connectionDetailText),
            FormOverviewItem(title: "Current Folder", value: viewModel.currentPathDisplayText),
            FormOverviewItem(title: trimmedSearchText.isEmpty ? "Visible" : "Matches", value: browserVisibleSummaryText)
        ]
    }

    @ViewBuilder
    private var gridContentSections: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView("Connecting to SMB Share")
                    .padding(.vertical, 20)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if viewModel.loadIssue != nil {
            remoteErrorContent()
                .frame(maxWidth: .infinity)
        } else if viewModel.items.isEmpty {
            browserUnavailableContent(
                title: "No Remote Files",
                systemImage: "folder",
                description: emptyFolderDescription
            )
        } else if !hasVisibleItems {
            browserUnavailableContent(
                title: "No Matches",
                systemImage: "magnifyingglass",
                description: noMatchesDescription
            )
        } else {
            if !displayedDirectories.isEmpty {
                remoteGridSection(title: "Folders", items: displayedDirectories)
            }

            if !displayedComicFiles.isEmpty {
                remoteGridSection(title: "Comic Files", items: displayedComicFiles)

                if displayedUnsupportedFileCount > 0 {
                    unsupportedFilesNoticeView
                }
            }
        }
    }

    private func remoteGridSection(
        title: String,
        items: [RemoteDirectoryItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 156, maximum: 206), spacing: 12)],
                spacing: 12
            ) {
                ForEach(items) { item in
                    let availability = viewModel.cacheAvailability(for: item)

                    ZStack(alignment: .topTrailing) {
                        Button {
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteDirectoryGridCard(
                                item: item,
                                readingSession: viewModel.progress(for: item),
                                cacheAvailability: availability,
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService
                            )
                        }
                        .onAppear {
                            markComicVisible(item)
                        }
                        .onDisappear {
                            markComicInvisible(item)
                        }
                        .buttonStyle(.plain)

                        browserItemActionMenuButton(for: item)
                        .padding(10)
                    }
                }
            }
        }
    }

    private func remoteErrorContent() -> some View {
        let loadIssue = viewModel.loadIssue

        return ContentUnavailableView {
            Label(
                loadIssue?.title ?? "Remote Folder Unavailable",
                systemImage: "wifi.exclamationmark"
            )
        } description: {
            Text(loadIssue?.message ?? "This remote folder could not be opened.")
        } actions: {
            errorRecoveryActions(loadIssue: loadIssue)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func errorRecoveryActions(loadIssue: RemoteBrowserLoadIssue?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recoverySuggestion = loadIssue?.recoverySuggestion {
                Label(recoverySuggestion, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }
            }

            if loadIssue?.prefersPathRecoveryActions == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        upOneLevelButton
                        sessionRootButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        upOneLevelButton
                        sessionRootButton
                    }
                }
            }
        }
    }

    private var retryButton: some View {
        Button {
            Task<Void, Never> {
                await viewModel.load()
            }
        } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func manageServersButton(loadIssue: RemoteBrowserLoadIssue?) -> some View {
        if loadIssue?.showsManageServersAction == true {
            NavigationLink {
                RemoteServerListView(dependencies: dependencies)
            } label: {
                Label("Manage Servers", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var continueReadingButton: some View {
        if let recoverySession = viewModel.recoverySession,
           let loadIssue = viewModel.loadIssue,
           loadIssue.allowsOfflineRecovery {
            NavigationLink {
                RemoteComicLoadingView(
                    profile: viewModel.profile,
                    item: recoverySession.directoryItem,
                    dependencies: dependencies
                )
            } label: {
                Label("Open Last Comic", systemImage: "book.closed")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var offlineShelfButton: some View {
        if let loadIssue = viewModel.loadIssue,
           loadIssue.allowsOfflineRecovery,
           viewModel.offlineRecoveryCount > 1 {
            NavigationLink {
                RemoteOfflineShelfView(dependencies: dependencies)
            } label: {
                Label("Offline Shelf", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var showsFolderActionCluster: Bool {
        viewModel.parentPath != nil || viewModel.canImportCurrentFolderRecursively || !displayedComicFiles.isEmpty
    }

    @ViewBuilder
    private var upOneLevelButton: some View {
        if let parentPath = viewModel.parentPath {
            NavigationLink {
                RemoteServerBrowserView(
                    profile: viewModel.profile,
                    currentPath: parentPath,
                    dependencies: dependencies
                )
            } label: {
                Label("Up One Level", systemImage: "arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var contentActionsMenu: some View {
        if viewModel.canImportCurrentFolderRecursively || !displayedComicFiles.isEmpty {
            Menu {
                if !displayedComicFiles.isEmpty {
                    Button {
                        Task<Void, Never> {
                            await viewModel.saveComicsForOffline(displayedComicFiles)
                        }
                    } label: {
                        Label(saveVisibleComicsButtonTitle, systemImage: "arrow.down.circle")
                    }
                }

                if !visibleOfflineComicFiles.isEmpty {
                    Button(role: .destructive) {
                        presentVisibleOfflineRemovalConfirmation()
                    } label: {
                        Label(removeVisibleOfflineCopiesButtonTitle, systemImage: "trash")
                    }
                }

                if viewModel.canImportCurrentFolderRecursively {
                    Button {
                        importRequest = .currentFolder
                    } label: {
                        Label(importCurrentFolderButtonTitle, systemImage: "square.and.arrow.down.on.square")
                    }
                }
            } label: {
                Label(contentActionsMenuTitle, systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var sessionRootButton: some View {
        if let parentPath = viewModel.parentPath, parentPath != viewModel.rootPath {
            NavigationLink {
                RemoteServerBrowserView(
                    profile: viewModel.profile,
                    currentPath: viewModel.rootPath,
                    dependencies: dependencies
                )
            } label: {
                Label("Session Root", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
        }
    }

    private func configureDisplayModeIfNeeded() {
        guard !hasConfiguredDisplayMode else {
            return
        }

        hasConfiguredDisplayMode = true
        displayMode = dependencies.remoteBrowserPreferencesStore.loadDisplayMode(
            for: viewModel.profile.id,
            defaultMode: horizontalSizeClass == .regular ? .grid : .list
        )
    }

    private func configureSortModeIfNeeded() {
        guard !hasConfiguredSortMode else {
            return
        }

        hasConfiguredSortMode = true
        sortMode = dependencies.remoteBrowserPreferencesStore.loadSortMode(
            for: viewModel.profile.id
        )
    }

    private var thumbnailPreheatRequestID: String {
        let plan = thumbnailPreheatPlan
        return "\(viewModel.profile.id.uuidString)#\(displayMode.rawValue)#\(sortMode.rawValue)#\(trimmedSearchText)#\(Int(displayScale * 100))#\(plan.requestSignature)"
    }

    private func preheatVisibleThumbnails() async {
        guard !viewModel.isLoading, !displayedComicFiles.isEmpty else {
            return
        }

        let maxDimension: CGFloat = displayMode == .grid ? 208 : 76
        let maxPixelSize = Int(maxDimension * max(displayScale, 1))
        let plan = thumbnailPreheatPlan

        await preheatThumbnails(
            in: plan.primaryRange,
            maxPixelSize: maxPixelSize,
            concurrency: displayMode == .grid ? 4 : 3
        )

        guard !Task.isCancelled else {
            return
        }

        for secondaryRange in plan.secondaryRanges {
            await preheatThumbnails(
                in: secondaryRange,
                maxPixelSize: maxPixelSize,
                concurrency: 2
            )

            guard !Task.isCancelled else {
                return
            }
        }
    }

    private var thumbnailPreheatPlan: ThumbnailPreheatPlan {
        let items = displayedComicFiles
        guard !items.isEmpty else {
            return ThumbnailPreheatPlan(
                primaryRange: 0..<0,
                secondaryRanges: [],
                requestSignature: "empty"
            )
        }

        let visibleIndexes = items.enumerated().compactMap { index, item in
            visibleComicIDs.contains(item.id) ? index : nil
        }

        let defaultVisibleUpperBound = min(
            items.count - 1,
            displayMode == .grid ? 5 : 2
        )
        let visibleLowerBound = visibleIndexes.min() ?? 0
        let visibleUpperBound = visibleIndexes.max() ?? defaultVisibleUpperBound

        let primaryLeadingPadding = displayMode == .grid ? 18 : 8
        let primaryTrailingPadding = displayMode == .grid ? 6 : 2
        let secondaryLeadingPadding = displayMode == .grid ? 42 : 18
        let secondaryTrailingPadding = displayMode == .grid ? 12 : 4

        let primaryStart = max(0, visibleLowerBound - primaryTrailingPadding)
        let primaryEndExclusive = min(items.count, visibleUpperBound + primaryLeadingPadding + 1)
        let primaryRange = primaryStart..<primaryEndExclusive

        let secondaryStart = max(0, visibleLowerBound - secondaryTrailingPadding)
        let secondaryEndExclusive = min(items.count, visibleUpperBound + secondaryLeadingPadding + 1)

        var secondaryRanges: [Range<Int>] = []
        if secondaryStart < primaryRange.lowerBound {
            secondaryRanges.append(secondaryStart..<primaryRange.lowerBound)
        }
        if primaryRange.upperBound < secondaryEndExclusive {
            secondaryRanges.append(primaryRange.upperBound..<secondaryEndExclusive)
        }

        let visibleSignature = visibleIndexes.map(String.init).joined(separator: ",")
        let secondarySignature = secondaryRanges
            .map { "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: "|")

        return ThumbnailPreheatPlan(
            primaryRange: primaryRange,
            secondaryRanges: secondaryRanges,
            requestSignature: "\(visibleSignature)#\(primaryRange.lowerBound)-\(primaryRange.upperBound)#\(secondarySignature)"
        )
    }

    private func preheatThumbnails(
        in range: Range<Int>,
        maxPixelSize: Int,
        concurrency: Int
    ) async {
        guard !range.isEmpty else {
            return
        }

        await RemoteComicThumbnailPipeline.shared.preheat(
            for: viewModel.profile,
            items: displayedComicFiles,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: range.count,
            skipCount: range.lowerBound,
            concurrency: concurrency
        )
    }

    private func markComicVisible(_ item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        visibleComicIDs.insert(item.id)
    }

    private func markComicInvisible(_ item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        visibleComicIDs.remove(item.id)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedDirectories: [RemoteDirectoryItem] {
        filteredAndSorted(viewModel.directories)
    }

    private var displayedComicFiles: [RemoteDirectoryItem] {
        filteredAndSorted(viewModel.comicFiles)
    }

    private var visibleOfflineComicFiles: [RemoteDirectoryItem] {
        displayedComicFiles.filter { viewModel.cacheAvailability(for: $0).hasLocalCopy }
    }

    private var displayedUnsupportedFileCount: Int {
        filteredItems(viewModel.items).reduce(into: 0) { count, item in
            if item.kind == .unsupportedFile {
                count += 1
            }
        }
    }

    private var hasVisibleItems: Bool {
        !displayedDirectories.isEmpty || !displayedComicFiles.isEmpty
    }

    private var emptyFolderDescription: String {
        if trimmedSearchText.isEmpty {
            return "No folders or supported comics in this location."
        }

        return noMatchesDescription
    }

    private var noMatchesDescription: String {
        "No folders or comics match \"\(trimmedSearchText)\"."
    }

    private var browserVisibleSummaryText: String {
        let folderCount = displayedDirectories.count
        let comicCount = displayedComicFiles.count
        let hiddenCount = displayedUnsupportedFileCount

        var segments = [
            folderCount == 1 ? "1 folder" : "\(folderCount) folders",
            comicCount == 1 ? "1 comic" : "\(comicCount) comics"
        ]

        if hiddenCount > 0 {
            segments.append(hiddenCount == 1 ? "1 hidden" : "\(hiddenCount) hidden")
        }

        return segments.joined(separator: " · ")
    }

    private var unsupportedFilesNoticeText: String? {
        guard displayedUnsupportedFileCount > 0 else {
            return nil
        }

        return displayedUnsupportedFileCount == 1
            ? "1 unsupported file hidden."
            : "\(displayedUnsupportedFileCount) unsupported files hidden."
    }

    @ViewBuilder
    private var unsupportedFilesNoticeView: some View {
        if let unsupportedFilesNoticeText {
            Text(unsupportedFilesNoticeText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func browserUnavailableContent(
        title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func filteredItems(_ items: [RemoteDirectoryItem]) -> [RemoteDirectoryItem] {
        guard !trimmedSearchText.isEmpty else {
            return items
        }

        return items.filter { item in
            item.name.localizedStandardContains(trimmedSearchText)
        }
    }

    private func filteredAndSorted(_ items: [RemoteDirectoryItem]) -> [RemoteDirectoryItem] {
        filteredItems(items).sorted(using: sortMode)
    }

    private func performImport(
        _ request: RemoteBrowserImportRequest,
        destinationSelection: LibraryImportDestinationSelection,
        scope: RemoteDirectoryImportScope
    ) async {
        switch request {
        case .currentFolder:
            if scope == .visibleResults {
                await viewModel.importVisibleComics(
                    displayedComicFiles,
                    destinationSelection: destinationSelection
                )
            } else {
                await viewModel.importCurrentFolder(
                    destinationSelection: destinationSelection,
                    scope: scope
                )
            }
        case .directory(let item):
            await viewModel.importDirectory(
                item,
                destinationSelection: destinationSelection,
                scope: scope
            )
        case .comic(let item):
            await viewModel.importComic(item, destinationSelection: destinationSelection)
        }
    }

    private func openPrimaryAction(for item: RemoteDirectoryItem) {
        if item.isDirectory {
            navigationRequest = .directory(item.path)
        } else if item.canOpenAsComic {
            navigationRequest = .comic(item, .automatic)
        }
    }

    private func openOfflineCopy(for item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        navigationRequest = .comic(item, .preferLocalCache)
    }

    @ViewBuilder
    private func browserItemActionMenuButton(for item: RemoteDirectoryItem) -> some View {
        let availability = viewModel.cacheAvailability(for: item)

        RemoteBrowserItemActionMenuButton(
            item: item,
            cacheAvailability: availability,
            onOpenOffline: openOfflineAction(for: item, availability: availability),
            onSaveOffline: saveOfflineAction(for: item, availability: availability),
            onRemoveOffline: removeOfflineAction(for: item, availability: availability),
            onImport: importAction(for: item)
        )
    }

    private func openOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic, availability.hasLocalCopy else {
            return nil
        }

        return {
            openOfflineCopy(for: item)
        }
    }

    private func saveOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic else {
            return nil
        }

        return {
            Task<Void, Never> {
                await viewModel.saveComicForOffline(
                    item,
                    forceRefresh: availability.kind != .unavailable
                )
            }
        }
    }

    private func removeOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic, availability.hasLocalCopy else {
            return nil
        }

        return {
            viewModel.removeOfflineCopy(for: item)
        }
    }

    private func importAction(for item: RemoteDirectoryItem) -> (() -> Void)? {
        if item.isDirectory {
            return {
                importRequest = .directory(item)
            }
        }

        guard item.canOpenAsComic else {
            return nil
        }

        return {
            importRequest = .comic(item)
        }
    }

    private var alternateDisplayMode: LibraryComicDisplayMode {
        switch displayMode {
        case .list:
            return .grid
        case .grid:
            return .list
        }
    }

    private var supportsVisibleResultsImportScope: Bool {
        !trimmedSearchText.isEmpty && !displayedComicFiles.isEmpty
    }

    private var saveVisibleComicsButtonTitle: String {
        trimmedSearchText.isEmpty ? "Save Visible Comics" : "Save Results Offline"
    }

    private var removeVisibleOfflineCopiesButtonTitle: String {
        trimmedSearchText.isEmpty ? "Remove Downloaded Copies" : "Remove Downloaded Result Copies"
    }

    private var importCurrentFolderButtonTitle: String {
        supportsVisibleResultsImportScope ? "Import Results" : "Import This Folder"
    }

    private var contentActionsMenuTitle: String {
        trimmedSearchText.isEmpty ? "Content Actions" : "Result Actions"
    }

    private func availableImportScopes(for request: RemoteBrowserImportRequest) -> [RemoteDirectoryImportScope] {
        switch request {
        case .currentFolder:
            if supportsVisibleResultsImportScope {
                return [.visibleResults, .currentFolderOnly, .includeSubfolders]
            }
            return [.currentFolderOnly, .includeSubfolders]
        case .directory:
            return [.currentFolderOnly, .includeSubfolders]
        case .comic:
            return [.currentFolderOnly]
        }
    }

    private func defaultImportScope(for request: RemoteBrowserImportRequest) -> RemoteDirectoryImportScope {
        switch request {
        case .currentFolder:
            return supportsVisibleResultsImportScope ? .visibleResults : .includeSubfolders
        case .directory:
            return .includeSubfolders
        case .comic:
            return .currentFolderOnly
        }
    }

    private func toggleDisplayMode() {
        applyDisplayMode(alternateDisplayMode)
    }

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        displayMode = mode
        dependencies.remoteBrowserPreferencesStore.saveDisplayMode(
            mode,
            for: viewModel.profile.id
        )
    }

    private func applySortMode(_ mode: RemoteDirectorySortMode) {
        sortMode = mode
        dependencies.remoteBrowserPreferencesStore.saveSortMode(
            mode,
            for: viewModel.profile.id
        )
    }

    private func handleRemoteAlertPrimaryAction(_ action: RemoteAlertPrimaryAction) {
        switch action {
        case .openLibrary(let libraryID, let folderID):
            AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
        }
    }

    private func presentVisibleOfflineRemovalConfirmation() {
        let items = visibleOfflineComicFiles
        guard !items.isEmpty else {
            return
        }

        let noun: String
        if trimmedSearchText.isEmpty {
            noun = items.count == 1 ? "visible comic" : "visible comics"
        } else {
            noun = items.count == 1 ? "matching result" : "matching results"
        }

        pendingOfflineRemoval = PendingRemoteOfflineRemoval(
            items: items,
            title: removeVisibleOfflineCopiesButtonTitle,
            buttonTitle: removeVisibleOfflineCopiesButtonTitle,
            message: "Only the downloaded copies of the current \(noun) will be removed from this device. The SMB server, saved folder, and reading progress stay intact."
        )
    }

    private func scheduleFeedbackDismissalIfNeeded() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil

        guard let feedback = viewModel.feedback,
              let autoDismissAfter = feedback.autoDismissAfter
        else {
            return
        }

        feedbackDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                guard !Task.isCancelled else {
                    return
                }

                if viewModel.feedback?.id == feedback.id {
                    viewModel.dismissFeedback()
                }
            } catch {
                // Ignore cancellation.
            }
        }
    }
}

private struct ThumbnailPreheatPlan {
    let primaryRange: Range<Int>
    let secondaryRanges: [Range<Int>]
    let requestSignature: String
}

func makeRemoteAlert(
    for alert: RemoteAlertState,
    onPrimaryAction: @escaping (RemoteAlertPrimaryAction) -> Void = { _ in }
) -> Alert {
    if let primaryAction = alert.primaryAction {
        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            primaryButton: .default(Text(primaryAction.title)) {
                onPrimaryAction(primaryAction)
            },
            secondaryButton: .cancel(Text("Not Now"))
        )
    }

    return Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
    )
}

private enum RemoteBrowserImportRequest: Identifiable {
    case currentFolder
    case directory(RemoteDirectoryItem)
    case comic(RemoteDirectoryItem)

    var id: String {
        switch self {
        case .currentFolder:
            return "currentFolder"
        case .directory(let item):
            return "directory:\(item.id)"
        case .comic(let item):
            return "comic:\(item.id)"
        }
    }

    var destinationPickerTitle: String {
        switch self {
        case .currentFolder:
            return "Import Folder"
        case .directory:
            return "Import Directory"
        case .comic:
            return "Import Comic"
        }
    }

    var destinationPickerMessage: String {
        switch self {
        case .currentFolder:
            return "Choose where to copy comics from this folder."
        case .directory(let item):
            return "Choose where to copy comics from \(item.name)."
        case .comic(let item):
            return "Choose where to copy \(item.name)."
        }
    }
}

private enum RemoteBrowserNavigationRequest: Identifiable, Hashable {
    case directory(String)
    case comic(RemoteDirectoryItem, RemoteComicOpenMode)

    var id: String {
        switch self {
        case .directory(let path):
            return "directory:\(path)"
        case .comic(let item, let openMode):
            switch openMode {
            case .automatic:
                return "comic:\(item.id):automatic"
            case .preferLocalCache:
                return "comic:\(item.id):offline"
            }
        }
    }
}

private struct PendingRemoteOfflineRemoval {
    let items: [RemoteDirectoryItem]
    let title: String
    let buttonTitle: String
    let message: String
}

private struct RemoteBrowserItemActionMenuButton: View {
    let item: RemoteDirectoryItem
    let cacheAvailability: RemoteComicCachedAvailability
    let onOpenOffline: (() -> Void)?
    let onSaveOffline: (() -> Void)?
    let onRemoveOffline: (() -> Void)?
    let onImport: (() -> Void)?

    var body: some View {
        RemoteCardActionMenuButton(accessibilityLabel: "Remote Item Actions") {
            if let onOpenOffline {
                Button(action: onOpenOffline) {
                    Label(
                        cacheAvailability.kind == .stale ? "Open Older Downloaded Copy" : "Open Downloaded Copy",
                        systemImage: "arrow.down.circle"
                    )
                }
            }

            if let onSaveOffline {
                Button(action: onSaveOffline) {
                    Label(saveOfflineTitle, systemImage: saveOfflineSystemImage)
                }
            }

            if let onRemoveOffline {
                Button(role: .destructive, action: onRemoveOffline) {
                    Label("Remove Downloaded Copy", systemImage: "trash")
                }
            }

            if let onImport {
                Button(action: onImport) {
                    Label(
                        item.isDirectory ? "Import Folder to Library" : "Import to Library",
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
        }
    }

    private var saveOfflineTitle: String {
        switch cacheAvailability.kind {
        case .unavailable:
            return "Save for Offline"
        case .current:
            return "Refresh Downloaded Copy"
        case .stale:
            return "Update Downloaded Copy"
        }
    }

    private var saveOfflineSystemImage: String {
        switch cacheAvailability.kind {
        case .unavailable:
            return "arrow.down.circle"
        case .current, .stale:
            return "arrow.clockwise.circle"
        }
    }
}
