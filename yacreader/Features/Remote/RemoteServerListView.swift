import SwiftUI

struct RemoteServerListView: View {
    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var actionsProfile: RemoteServerProfile?
    @State private var pendingAction: PendingRemoteServerAction?
    @State private var isShowingClearAllCacheConfirmation = false

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
                        "No SMB Servers Yet",
                        systemImage: "server.rack",
                        description: Text("Save SMB servers here, then browse remote folders and open individual comic archives without importing an entire library first.")
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
            viewModel.refreshCacheSummary()
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
                cacheSummary: viewModel.cacheSummary(for: profile),
                onDone: { actionsProfile = nil },
                onEdit: {
                    pendingAction = .edit(profile)
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
        .confirmationDialog(
            "Clear all downloaded remote comics?",
            isPresented: $isShowingClearAllCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Downloads", role: .destructive) {
                viewModel.clearAllCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes remote copies cached on this device. Saved SMB servers and reading progress stay intact.")
        }
        .onChange(of: actionsProfile) { _, newValue in
            guard newValue == nil, let pendingAction else {
                return
            }

            self.pendingAction = nil
            switch pendingAction {
            case .edit(let profile):
                editorDraft = viewModel.makeEditDraft(for: profile)
            case .clearCache(let profile):
                viewModel.clearCache(for: profile)
            case .delete(let profile):
                viewModel.delete(profile)
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Remote SMB Access")
                    .font(.headline)

                Text(viewModel.summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Browse home handles Continue Reading, Offline Shelf, and Saved Folders. This page stays focused on server setup and maintenance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    StatusBadge(title: "SMB", tint: .blue)
                    StatusBadge(title: "Single Comic Files", tint: .green)
                    StatusBadge(title: "On-Demand", tint: .orange)
                }

                if !viewModel.cacheSummary.isEmpty {
                    Label(viewModel.cacheSummary.summaryText, systemImage: "externaldrive.fill.badge.minus")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        isShowingClearAllCacheConfirmation = true
                    } label: {
                        Label("Clear All Downloads", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct RemoteServerRow: View {
    let profile: RemoteServerProfile
    let latestSession: RemoteComicReadingSession?
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: profile.providerKind.systemImage)
                .font(.title3)
                .foregroundStyle(profile.providerKind.tintColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.headline)

                Text(profile.connectionDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let latestSession {
                    Label(
                        "\(latestSession.displayName) · \(latestSession.progressText)",
                        systemImage: "book.closed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                HStack(spacing: 6) {
                    StatusBadge(title: profile.providerKind.title, tint: profile.providerKind.tintColor)
                    StatusBadge(title: profile.authenticationMode.title, tint: profile.authenticationMode == .guest ? .orange : .green)
                    if !profile.usesDefaultPort {
                        StatusBadge(title: ":\(profile.port)", tint: .teal)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private struct RemoteServerManageButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Manage", systemImage: "ellipsis.circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remote Server Actions")
    }
}

private struct RemoteServerActionsSheet: View {
    let profile: RemoteServerProfile
    let cacheSummary: RemoteComicCacheSummary
    let onDone: () -> Void
    let onEdit: () -> Void
    let onClearCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(profile.name)
                            .font(.headline)

                        Text(profile.connectionDisplayPath)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            StatusBadge(title: profile.providerKind.title, tint: profile.providerKind.tintColor)
                            StatusBadge(title: profile.authenticationMode.title, tint: profile.authenticationMode == .guest ? .orange : .green)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Manage") {
                    Button(action: onEdit) {
                        Label("Edit SMB Server", systemImage: "square.and.pencil")
                    }
                }

                Section {
                    if cacheSummary.isEmpty {
                        Label("No downloaded comics are cached for this server.", systemImage: "externaldrive")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Downloaded Cache") {
                            Text(cacheSummary.summaryText)
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive, action: onClearCache) {
                            Label("Clear Download Cache", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("This only removes downloaded remote copies kept on the device. It does not remove the SMB server profile.")
                }

                Section {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete SMB Server", systemImage: "trash")
                    }
                } footer: {
                    Text("Deleting a remote server removes its saved profile and any stored password reference from the app.")
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

private enum PendingRemoteServerAction {
    case edit(RemoteServerProfile)
    case clearCache(RemoteServerProfile)
    case delete(RemoteServerProfile)
}

private struct RemoteServerEditorSheet: View {
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
                Section("Server") {
                    TextField("Display name", text: $draft.name)
                        .focused($isNameFieldFocused)

                    Picker("Provider", selection: $draft.providerKind) {
                        ForEach(RemoteProviderKind.allCases) { provider in
                            Label(provider.title, systemImage: provider.systemImage)
                                .tag(provider)
                        }
                    }
                    .disabled(true)

                    TextField("Host", text: $draft.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Port", text: $draft.portText)
                        .keyboardType(.numberPad)

                    TextField("Share", text: $draft.shareName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Base directory (optional)", text: $draft.baseDirectoryPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Example: host `192.168.1.20`, share `Comics`, base directory `/Manga/Weekly`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Authentication") {
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

                        if draft.hasStoredPassword {
                            Text("Leave the password field blank to keep the existing credential already stored in Keychain.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
        Group {
            if displayMode == .grid {
                gridBody
            } else {
                listBody
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleCurrentFolderShortcut()
                } label: {
                    Image(systemName: viewModel.isCurrentFolderSaved ? "star.fill" : "star")
                }

                Menu {
                    Section("Display") {
                        ForEach(LibraryComicDisplayMode.allCases) { mode in
                            Button {
                                applyDisplayMode(mode)
                            } label: {
                                Label(mode.title, systemImage: mode.systemImageName)
                            }
                        }
                    }

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
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: thumbnailPreheatRequestID) {
            preheatVisibleThumbnails()
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Filter this SMB folder"
        )
        .safeAreaInset(edge: .bottom) {
            if let activeImportDescription = viewModel.activeImportDescription {
                RemoteBrowserImportProgressView(description: activeImportDescription)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert, onPrimaryAction: handleRemoteAlertPrimaryAction(_:))
        }
        .sheet(item: $importRequest) { request in
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
            summaryContent
        }
    }

    private var summaryCard: some View {
        summaryContent
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.profile.name)
                .font(.headline)

            Text(viewModel.connectionDetailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            LabeledContent("Current Folder") {
                Text(viewModel.currentPathDisplayText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Text(browserSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                StatusBadge(title: viewModel.capabilities.providerKind.title, tint: viewModel.capabilities.providerKind.tintColor)
                StatusBadge(title: displayMode.title, tint: .blue)
                StatusBadge(title: sortMode.shortTitle, tint: .teal)
                if viewModel.isCurrentFolderSaved {
                    StatusBadge(title: "Saved", tint: .yellow)
                }
                if !trimmedSearchText.isEmpty {
                    StatusBadge(title: "Filtering", tint: .orange)
                }
            }

            Text("Client: \(viewModel.capabilities.plannedClientLibrary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsFolderActionCluster {
                Divider()
                    .padding(.vertical, 2)

                Text("Folder Actions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        upOneLevelButton
                        sessionRootButton
                        importCurrentFolderButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        upOneLevelButton
                        sessionRootButton
                        importCurrentFolderButton
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
                ContentUnavailableView(
                    "No Remote Comics Yet",
                    systemImage: "folder",
                    description: Text(viewModel.summaryText)
                )
                .padding(.vertical, 24)
            }
        } else if !hasVisibleItems {
            Section {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text(browserSummaryText)
                )
                .padding(.vertical, 24)
            }
        } else {
            if !displayedDirectories.isEmpty {
                Section("Folders") {
                    ForEach(displayedDirectories) { item in
                        NavigationLink {
                            RemoteServerBrowserView(
                                profile: viewModel.profile,
                                currentPath: item.path,
                                dependencies: dependencies
                            )
                        } label: {
                            RemoteDirectoryItemListRow(
                                item: item,
                                readingSession: nil,
                                cacheAvailability: .unavailable,
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                importRequest = .directory(item)
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }

            if !displayedComicFiles.isEmpty {
                Section {
                    ForEach(displayedComicFiles) { item in
                        NavigationLink {
                            RemoteComicLoadingView(
                                profile: viewModel.profile,
                                item: item,
                                dependencies: dependencies
                            )
                        } label: {
                            RemoteDirectoryItemListRow(
                                item: item,
                                readingSession: viewModel.progress(for: item),
                                cacheAvailability: viewModel.cacheAvailability(for: item),
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                importRequest = .comic(item)
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("Comic Files")
                } footer: {
                    if displayedUnsupportedFileCount > 0 {
                        Text("\(displayedUnsupportedFileCount) unsupported remote files are hidden in this folder.")
                    }
                }
            }
        }
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
            ContentUnavailableView(
                "No Remote Comics Yet",
                systemImage: "folder",
                description: Text(browserSummaryText)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if !hasVisibleItems {
            ContentUnavailableView(
                "No Matches",
                systemImage: "magnifyingglass",
                description: Text(browserSummaryText)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            if !displayedDirectories.isEmpty {
                remoteGridSection(title: "Folders", items: displayedDirectories) { item in
                    importRequest = .directory(item)
                }
            }

            if !displayedComicFiles.isEmpty {
                remoteGridSection(title: "Comic Files", items: displayedComicFiles) { item in
                    importRequest = .comic(item)
                }

                if displayedUnsupportedFileCount > 0 {
                    Text("\(displayedUnsupportedFileCount) unsupported remote files are hidden in this folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func remoteGridSection(
        title: String,
        items: [RemoteDirectoryItem],
        importAction: ((RemoteDirectoryItem) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 16)],
                spacing: 16
            ) {
                ForEach(items) { item in
                    NavigationLink {
                        if item.isDirectory {
                            RemoteServerBrowserView(
                                profile: viewModel.profile,
                                currentPath: item.path,
                                dependencies: dependencies
                            )
                        } else {
                            RemoteComicLoadingView(
                                profile: viewModel.profile,
                                item: item,
                                dependencies: dependencies
                            )
                        }
                    } label: {
                        RemoteDirectoryGridCard(
                            item: item,
                            readingSession: viewModel.progress(for: item),
                            cacheAvailability: viewModel.cacheAvailability(for: item),
                            profile: viewModel.profile,
                            browsingService: dependencies.remoteServerBrowsingService,
                            onImport: importAction.map { action in
                                { action(item) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func remoteErrorContent() -> some View {
        let loadIssue = viewModel.loadIssue

        return VStack(alignment: .leading, spacing: 16) {
            ContentUnavailableView(
                loadIssue?.title ?? "Remote Browser Not Ready Yet",
                systemImage: "wifi.exclamationmark",
                description: Text(loadIssue?.message ?? "The remote folder could not be opened.")
            )

            if let recoverySuggestion = loadIssue?.recoverySuggestion {
                Label(recoverySuggestion, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        retryButton
                        manageServersButton(loadIssue: loadIssue)
                        continueReadingButton
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        retryButton
                        manageServersButton(loadIssue: loadIssue)
                        continueReadingButton
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
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var retryButton: some View {
        Button {
            Task {
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

    private var showsFolderActionCluster: Bool {
        viewModel.parentPath != nil || viewModel.canImportCurrentFolderRecursively
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
    private var importCurrentFolderButton: some View {
        if viewModel.canImportCurrentFolderRecursively {
            Button {
                importRequest = .currentFolder
            } label: {
                Label("Import This Folder", systemImage: "square.and.arrow.down.on.square")
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
        displayMode = Self.loadStoredDisplayMode(
            defaultMode: horizontalSizeClass == .regular ? .grid : .list
        )
    }

    private func configureSortModeIfNeeded() {
        guard !hasConfiguredSortMode else {
            return
        }

        hasConfiguredSortMode = true
        sortMode = Self.loadStoredSortMode()
    }

    private var thumbnailPreheatRequestID: String {
        let candidateIDs = displayedComicFiles.prefix(displayMode == .grid ? 18 : 12).map(\.id).joined(separator: "|")
        return "\(viewModel.profile.id.uuidString)#\(displayMode.rawValue)#\(sortMode.rawValue)#\(trimmedSearchText)#\(Int(displayScale * 100))#\(candidateIDs)"
    }

    private func preheatVisibleThumbnails() {
        guard !viewModel.isLoading, !displayedComicFiles.isEmpty else {
            return
        }

        let maxDimension: CGFloat = displayMode == .grid ? 208 : 76
        let maxPixelSize = Int(maxDimension * max(displayScale, 1))
        let limit = displayMode == .grid ? 18 : 12

        Task {
            await RemoteComicThumbnailPipeline.shared.preheat(
            for: viewModel.profile,
            items: displayedComicFiles,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: limit,
            concurrency: displayMode == .grid ? 4 : 3
            )
        }
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

    private var browserSummaryText: String {
        if let loadIssue = viewModel.loadIssue {
            return loadIssue.message
        }

        if viewModel.items.isEmpty {
            return viewModel.summaryText
        }

        if hasVisibleItems {
            let folderCount = displayedDirectories.count
            let comicCount = displayedComicFiles.count
            let hiddenCount = displayedUnsupportedFileCount
            let prefix: String
            if trimmedSearchText.isEmpty {
                prefix = "\(folderCount) folders and \(comicCount) comic files are visible here."
            } else {
                prefix = "\(folderCount) folders and \(comicCount) comic files match \"\(trimmedSearchText)\"."
            }

            if hiddenCount > 0 {
                return "\(prefix) \(hiddenCount) unsupported files are hidden."
            }

            return prefix
        }

        return "No folders or supported comic files in this SMB folder match \"\(trimmedSearchText)\"."
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
            await viewModel.importCurrentFolder(
                destinationSelection: destinationSelection,
                scope: scope
            )
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

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        displayMode = mode
        Self.persistDisplayMode(mode)
    }

    private func applySortMode(_ mode: RemoteDirectorySortMode) {
        sortMode = mode
        Self.persistSortMode(mode)
    }

    private static func loadStoredDisplayMode(defaultMode: LibraryComicDisplayMode) -> LibraryComicDisplayMode {
        let userDefaults = UserDefaults.standard
        let storageKey = "remoteServerBrowser.displayMode"
        if let rawValue = userDefaults.string(forKey: storageKey),
           let mode = LibraryComicDisplayMode(rawValue: rawValue) {
            return mode
        }

        return defaultMode
    }

    private static func persistDisplayMode(_ mode: LibraryComicDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "remoteServerBrowser.displayMode")
    }

    private static func loadStoredSortMode() -> RemoteDirectorySortMode {
        let storageKey = "remoteServerBrowser.sortMode"
        if let rawValue = UserDefaults.standard.string(forKey: storageKey),
           let mode = RemoteDirectorySortMode(rawValue: rawValue) {
            return mode
        }

        return .nameAscending
    }

    private static func persistSortMode(_ mode: RemoteDirectorySortMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "remoteServerBrowser.sortMode")
    }

    private func handleRemoteAlertPrimaryAction(_ action: RemoteAlertPrimaryAction) {
        switch action {
        case .openLibrary(let libraryID, let folderID):
            AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
        }
    }
}

private func makeRemoteAlert(
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
            return "Import Remote Folder"
        case .directory:
            return "Import Remote Directory"
        case .comic:
            return "Import Remote Comic"
        }
    }

    var destinationPickerMessage: String {
        switch self {
        case .currentFolder:
            return "Choose the import scope for this SMB folder, then pick which local library should receive the copied comics."
        case .directory(let item):
            return "Choose the import scope for \(item.name), then pick which local library should receive the copied comics."
        case .comic(let item):
            return "Choose which local library should receive \(item.name)."
        }
    }
}
