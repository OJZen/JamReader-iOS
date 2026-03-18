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
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
        )
    }

    var body: some View {
        List {
            summarySection
            continueReadingSection

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
                if viewModel.save(draft: updatedDraft) {
                    editorDraft = nil
                }
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
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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

    @ViewBuilder
    private var continueReadingSection: some View {
        if let session = viewModel.mostRecentSession,
           let profile = viewModel.profile(for: session.serverID) {
            Section {
                NavigationLink {
                    RemoteComicLoadingView(
                        profile: profile,
                        item: session.directoryItem,
                        dependencies: dependencies
                    )
                } label: {
                    RemoteContinueReadingRow(session: session)
                }
            } header: {
                Text("Continue Reading")
            } footer: {
                Text("Resume the most recent remote comic without re-browsing the SMB folder tree first.")
            }
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

private struct RemoteContinueReadingRow: View {
    let session: RemoteComicReadingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)

                    Text(session.serverName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                StatusBadge(title: session.providerKind.title, tint: session.providerKind.tintColor)
                StatusBadge(title: session.progressText, tint: session.read ? .green : .orange)
            }

            Text("Last opened \(session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

    let onSave: (RemoteServerEditorDraft) -> Void

    @State private var draft: RemoteServerEditorDraft
    @FocusState private var isNameFieldFocused: Bool

    init(
        draft: RemoteServerEditorDraft,
        onSave: @escaping (RemoteServerEditorDraft) -> Void
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
                        onSave(draft)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            isNameFieldFocused = true
        }
    }
}

struct RemoteServerBrowserView: View {
    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerBrowserViewModel

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
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
        )
    }

    var body: some View {
        List {
            summarySection

            if !viewModel.isAtRootPath {
                Section {
                    NavigationLink {
                        RemoteServerBrowserView(
                            profile: viewModel.profile,
                            currentPath: viewModel.rootPath,
                            dependencies: dependencies
                        )
                    } label: {
                        Label("Return to Session Root", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Jump back to the saved base directory for this server without popping through each parent folder.")
                }
            }

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Connecting to SMB Share")
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else if let loadErrorMessage = viewModel.loadErrorMessage {
                Section {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Remote Browser Not Ready Yet",
                            systemImage: "wifi.exclamationmark",
                            description: Text(loadErrorMessage)
                        )

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await viewModel.load()
                                }
                            } label: {
                                Label("Try Again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)

                            if !viewModel.isAtRootPath {
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
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
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
            } else {
                if !viewModel.directories.isEmpty {
                    Section("Folders") {
                        ForEach(viewModel.directories) { item in
                            NavigationLink {
                                RemoteServerBrowserView(
                                    profile: viewModel.profile,
                                    currentPath: item.path,
                                    dependencies: dependencies
                                )
                            } label: {
                                RemoteDirectoryItemRow(item: item, readingSession: nil)
                            }
                        }
                    }
                }

                if !viewModel.comicFiles.isEmpty {
                    Section {
                        ForEach(viewModel.comicFiles) { item in
                            NavigationLink {
                                RemoteComicLoadingView(
                                    profile: viewModel.profile,
                                    item: item,
                                    dependencies: dependencies
                                )
                            } label: {
                                RemoteDirectoryItemRow(
                                    item: item,
                                    readingSession: viewModel.progress(for: item)
                                )
                            }
                        }
                    } header: {
                        Text("Comic Files")
                    } footer: {
                        if viewModel.unsupportedFileCount > 0 {
                            Text("\(viewModel.unsupportedFileCount) unsupported remote files are hidden in this folder.")
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.load()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.refreshProgressState()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var summarySection: some View {
        Section {
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

                HStack(spacing: 8) {
                    StatusBadge(title: viewModel.capabilities.providerKind.title, tint: viewModel.capabilities.providerKind.tintColor)
                    StatusBadge(title: "Browse Directories", tint: .blue)
                    StatusBadge(title: "Single Comic Files", tint: .green)
                }

                Text("Client: \(viewModel.capabilities.plannedClientLibrary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct RemoteDirectoryItemRow: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.richtext.fill")
                .foregroundStyle(item.isDirectory ? .blue : .green)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)

                HStack(spacing: 8) {
                    if let readingSession {
                        Label(readingSession.progressText, systemImage: "bookmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(readingSession.read ? .green : .orange)
                    }

                    if let fileSize = item.fileSize, !item.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let modifiedAt = item.modifiedAt {
                        Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
