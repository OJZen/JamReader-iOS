import SwiftUI

struct RemoteServerListView: View {
    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var actionsProfile: RemoteServerProfile?
    @State private var pendingAction: PendingRemoteServerAction?

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

                Text("Global remote cache cleanup now lives in Settings > Remote Cache, so this page only keeps server-specific actions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    StatusBadge(title: "SMB", tint: .blue)
                    StatusBadge(title: "Single Comic Files", tint: .green)
                    StatusBadge(title: "On-Demand", tint: .orange)
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
    @State private var navigationRequest: RemoteBrowserNavigationRequest?
    @State private var feedbackDismissTask: Task<Void, Never>?

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
                        saveVisibleComicsButton
                        importCurrentFolderButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        upOneLevelButton
                        sessionRootButton
                        saveVisibleComicsButton
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
                            RemoteBrowserItemActionMenuButton(
                                item: item,
                                cacheAvailability: .unavailable,
                                onOpen: { openPrimaryAction(for: item) },
                                onOpenOffline: nil,
                                onSaveOffline: nil,
                                onRemoveOffline: nil,
                                onImport: { importRequest = .directory(item) }
                            )
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
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            RemoteBrowserItemActionMenuButton(
                                item: item,
                                cacheAvailability: availability,
                                onOpen: { openPrimaryAction(for: item) },
                                onOpenOffline: availability.hasLocalCopy ? {
                                    openOfflineCopy(for: item)
                                } : nil,
                                onSaveOffline: {
                                    Task<Void, Never> {
                                        await viewModel.saveComicForOffline(
                                            item,
                                            forceRefresh: availability.kind != .unavailable
                                        )
                                    }
                                },
                                onRemoveOffline: availability.hasLocalCopy ? {
                                    viewModel.removeOfflineCopy(for: item)
                                } : nil,
                                onImport: { importRequest = .comic(item) }
                            )
                            .padding(.trailing, 4)
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
                        .buttonStyle(.plain)

                        RemoteBrowserItemActionMenuButton(
                            item: item,
                            cacheAvailability: availability,
                            onOpen: { openPrimaryAction(for: item) },
                            onOpenOffline: item.canOpenAsComic && availability.hasLocalCopy ? {
                                openOfflineCopy(for: item)
                            } : nil,
                            onSaveOffline: item.canOpenAsComic ? {
                                Task<Void, Never> {
                                    await viewModel.saveComicForOffline(
                                        item,
                                        forceRefresh: availability.kind != .unavailable
                                    )
                                }
                            } : nil,
                            onRemoveOffline: item.canOpenAsComic && availability.hasLocalCopy ? {
                                viewModel.removeOfflineCopy(for: item)
                            } : nil,
                            onImport: importAction.map { action in { action(item) } }
                        )
                        .padding(10)
                    }
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
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
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
    private var importCurrentFolderButton: some View {
        if viewModel.canImportCurrentFolderRecursively {
            Button {
                importRequest = .currentFolder
            } label: {
                Label(importCurrentFolderButtonTitle, systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var saveVisibleComicsButton: some View {
        if !displayedComicFiles.isEmpty {
            Button {
                Task<Void, Never> {
                    await viewModel.saveComicsForOffline(displayedComicFiles)
                }
            } label: {
                Label("Save Visible Comics", systemImage: "arrow.down.circle")
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
        let trackedLimit = displayMode == .grid ? 42 : 24
        let candidateIDs = displayedComicFiles.prefix(trackedLimit).map(\.id).joined(separator: "|")
        return "\(viewModel.profile.id.uuidString)#\(displayMode.rawValue)#\(sortMode.rawValue)#\(trimmedSearchText)#\(Int(displayScale * 100))#\(candidateIDs)"
    }

    private func preheatVisibleThumbnails() async {
        guard !viewModel.isLoading, !displayedComicFiles.isEmpty else {
            return
        }

        let maxDimension: CGFloat = displayMode == .grid ? 208 : 76
        let maxPixelSize = Int(maxDimension * max(displayScale, 1))
        let primaryLimit = displayMode == .grid ? 18 : 12
        let secondaryLimit = displayMode == .grid ? 24 : 12

        await RemoteComicThumbnailPipeline.shared.preheat(
            for: viewModel.profile,
            items: displayedComicFiles,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: primaryLimit,
            concurrency: displayMode == .grid ? 4 : 3
        )

        guard !Task.isCancelled,
              displayedComicFiles.count > primaryLimit
        else {
            return
        }

        await RemoteComicThumbnailPipeline.shared.preheat(
            for: viewModel.profile,
            items: displayedComicFiles,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: secondaryLimit,
            skipCount: primaryLimit,
            concurrency: 2
        )
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

    private var importCurrentFolderButtonTitle: String {
        supportsVisibleResultsImportScope ? "Import Results" : "Import This Folder"
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

private struct RemoteBrowserItemActionMenuButton: View {
    let item: RemoteDirectoryItem
    let cacheAvailability: RemoteComicCachedAvailability
    let onOpen: () -> Void
    let onOpenOffline: (() -> Void)?
    let onSaveOffline: (() -> Void)?
    let onRemoveOffline: (() -> Void)?
    let onImport: (() -> Void)?

    var body: some View {
        Menu {
            Button(action: onOpen) {
                Label(item.isDirectory ? "Open Folder" : "Open Comic", systemImage: item.isDirectory ? "folder.open" : "book.closed")
            }

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
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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
