import SwiftUI
import UniformTypeIdentifiers

struct LibraryHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("libraryHome.selectedLibraryID") private var storedSelectedLibraryID = ""
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var isLibraryFolderImporterPresented = false
    @State private var isComicFileImporterPresented = false
    @State private var selectedLibraryID: UUID?
    @State private var libraryActionsItem: LibraryListItem?
    @State private var renamingLibraryItem: LibraryListItem?
    @State private var libraryInfoItem: LibraryListItem?
    @State private var pendingLibraryAction: PendingLibraryAction?
    @State private var latestRemoteSession: RemoteComicReadingSession?

    var body: some View {
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .fileImporter(
            isPresented: $isLibraryFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importLibraries(from: urls)
            case .failure(let error):
                viewModel.presentImportError(error)
            }
        }
        .fileImporter(
            isPresented: $isComicFileImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importLibraries(from: urls)
            case .failure(let error):
                viewModel.presentImportError(error)
            }
        }
        .onAppear {
            viewModel.reload()
            synchronizeSelection()
            refreshRemoteAccessSummary()
        }
        .onChange(of: viewModel.items) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: selectedLibraryID) { _, newValue in
            storedSelectedLibraryID = newValue?.uuidString ?? ""
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshRemoteAccessSummary()
            }
        }
        .sheet(item: $libraryActionsItem) { item in
            LibraryHomeLibraryActionsSheet(
                item: item,
                onDone: { libraryActionsItem = nil },
                onRename: {
                    queueLibraryAction(.rename(item))
                },
                onViewInfo: {
                    queueLibraryAction(.info(item))
                },
                onRemove: {
                    viewModel.removeLibrary(id: item.id)
                    libraryActionsItem = nil
                }
            )
        }
        .sheet(item: $renamingLibraryItem) { item in
            LibraryRenameSheet(item: item) { proposedName in
                viewModel.renameLibrary(id: item.id, to: proposedName)
            }
        }
        .sheet(item: $libraryInfoItem) { item in
            LibraryInfoSheet(item: item)
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: libraryActionsItem) { _, newValue in
            guard newValue == nil, let pendingLibraryAction else {
                return
            }

            self.pendingLibraryAction = nil
            switch pendingLibraryAction {
            case .rename(let item):
                renamingLibraryItem = item
            case .info(let item):
                libraryInfoItem = item
            }
        }
    }

    private var usesSplitViewLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var compactLayout: some View {
        NavigationStack {
            List {
                overviewSection
                compactRemoteAccessSection
                compactLibrariesSection
            }
            .navigationTitle("YACReader")
            .toolbar {
                addLibraryToolbarItem
            }
            .refreshable {
                viewModel.reload()
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView {
            List(selection: $selectedLibraryID) {
                sidebarOverviewSection
                splitRemoteAccessSection
                splitLibrariesSection
            }
            .navigationTitle("YACReader")
            .listStyle(.sidebar)
            .toolbar {
                addLibraryToolbarItem
            }
            .refreshable {
                viewModel.reload()
            }
        } detail: {
            NavigationStack {
                if let selectedItem {
                    LibraryBrowserView(
                        descriptor: selectedItem.descriptor,
                        folderID: preferredFolderID(for: selectedItem),
                        dependencies: dependencies
                    )
                    .id(selectedItem.id)
                } else {
                    LibraryHomeDetailPlaceholder(
                        itemCount: viewModel.items.count,
                        onAddLibrary: {
                            presentLibraryFolderImporter()
                        }
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var addLibraryToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    presentLibraryFolderImporter()
                } label: {
                    Label("Add Library Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    presentComicFileImporter()
                } label: {
                    Label("Import Comic Files", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    private var selectedItem: LibraryListItem? {
        guard let selectedLibraryID else {
            return nil
        }

        return viewModel.items.first(where: { $0.id == selectedLibraryID })
    }

    private var resumeLibraryItem: LibraryListItem? {
        if let selectedItem {
            return selectedItem
        }

        if let storedLibraryID = UUID(uuidString: storedSelectedLibraryID) {
            return viewModel.items.first(where: { $0.id == storedLibraryID })
        }

        return viewModel.items.first
    }

    private func synchronizeSelection() {
        if viewModel.items.isEmpty {
            selectedLibraryID = nil
        } else if let selectedLibraryID,
                  viewModel.items.contains(where: { $0.id == selectedLibraryID }) {
            return
        } else if let storedLibraryID = UUID(uuidString: storedSelectedLibraryID),
                  viewModel.items.contains(where: { $0.id == storedLibraryID }) {
            selectedLibraryID = storedLibraryID
        } else {
            selectedLibraryID = viewModel.items.first?.id
        }
    }

    private func preferredFolderID(for item: LibraryListItem) -> Int64 {
        LibraryBrowserView.lastOpenedFolderID(for: item.id)
    }

    private func presentLibraryFolderImporter() {
        isLibraryFolderImporterPresented = true
    }

    private func presentComicFileImporter() {
        isComicFileImporterPresented = true
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue Where You Left Off")
                    .font(.headline)

                if let resumeLibraryItem {
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: resumeLibraryItem.descriptor,
                            folderID: preferredFolderID(for: resumeLibraryItem),
                            dependencies: dependencies
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 30, height: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(resumeLibraryItem.descriptor.name)
                                        .font(.subheadline.weight(.semibold))

                                    Text("Resume your last-used workspace without starting from the library root again.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }

                            HStack(spacing: 8) {
                                StatusBadge(title: "\(viewModel.items.count) libraries", tint: .blue)
                                StatusBadge(title: resumeLibraryItem.descriptor.storageMode.title, tint: resumeLibraryItem.descriptor.storageMode.tintColor)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Add an existing library folder, or import comic archives into Imported Comics.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        presentLibraryFolderImporter()
                    } label: {
                        Label("Add Library", systemImage: "folder.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        presentComicFileImporter()
                    } label: {
                        Label("Import Comics", systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var compactLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Libraries Yet",
                    systemImage: "books.vertical",
                    description: Text("Choose a library folder, or select comic files (zip/rar/cbz/cbr/pdf) to import into Imported Comics.")
                )
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: item.descriptor,
                            folderID: preferredFolderID(for: item),
                            dependencies: dependencies
                        )
                    } label: {
                        LibraryRowView(
                            item: item,
                            trailingAccessoryReservedWidth: compactLibraryActionReservedWidth
                        )
                    }
                    .overlay(alignment: .trailing) {
                        libraryQuickActionButton(for: item)
                            .padding(.trailing, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
                .onDelete(perform: viewModel.removeLibraries)
            }
        }
    }

    private var compactRemoteAccessSection: some View {
        Section("Remote Access") {
            NavigationLink {
                RemoteServerListView(dependencies: dependencies)
            } label: {
                RemoteAccessRow(compact: true, latestSession: latestRemoteSession)
            }
        }
    }

    private var sidebarOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Library Workspace")
                    .font(.headline)

                Text(sidebarWorkspaceSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(title: "\(viewModel.items.count) libraries", tint: .blue)
                    StatusBadge(title: "iPad", tint: .green)
                    if let resumeLibraryItem {
                        StatusBadge(
                            title: resumeLibraryItem.descriptor.name,
                            tint: resumeLibraryItem.descriptor.storageMode.tintColor
                        )
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var sidebarWorkspaceSummary: String {
        if let resumeLibraryItem {
            return "Keep libraries in reach while the detail pane resumes \(resumeLibraryItem.descriptor.name) close to where you left off."
        }

        return "Use the sidebar to keep libraries in reach while browsing folders and reading on the detail side."
    }

    private var splitLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Libraries Yet",
                    systemImage: "books.vertical",
                    description: Text("Add a library folder, or import comic files into Imported Comics.")
                )
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.items) { item in
                    LibrarySidebarRowView(
                        item: item,
                        trailingAccessoryReservedWidth: 40
                    )
                        .overlay(alignment: .trailing) {
                            libraryQuickActionButton(for: item)
                                .padding(.trailing, 8)
                        }
                        .tag(item.id)
                }
                .onDelete(perform: viewModel.removeLibraries)
            }
        }
    }

    private var splitRemoteAccessSection: some View {
        Section("Remote Access") {
            NavigationLink {
                RemoteServerListView(dependencies: dependencies)
            } label: {
                RemoteAccessRow(compact: false, latestSession: latestRemoteSession)
            }
        }
    }

    private var compactLibraryActionReservedWidth: CGFloat {
        88
    }

    private func libraryQuickActionButton(for item: LibraryListItem) -> some View {
        LibraryHomeQuickActionButton(prominent: !usesSplitViewLayout) {
            libraryActionsItem = item
        }
    }

    private func queueLibraryAction(_ action: PendingLibraryAction) {
        pendingLibraryAction = action
        libraryActionsItem = nil
    }

    private func refreshRemoteAccessSummary() {
        let activeServerIDs = Set(((try? dependencies.remoteServerProfileStore.load()) ?? []).map(\.id))
        let sessions = (try? dependencies.remoteReadingProgressStore.loadSessions()) ?? []
        latestRemoteSession = sessions.first { activeServerIDs.contains($0.serverID) }
    }
}

private struct LibraryRowView: View {
    let item: LibraryListItem
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(item.descriptor.storageMode.tintColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.descriptor.name)
                        .font(.headline)

                    Text(item.descriptor.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: item.descriptor.storageMode.title,
                    tint: item.descriptor.storageMode.tintColor
                )
            }

            HStack(spacing: 8) {
                StatusBadge(title: item.accessSnapshot.sourceStatus, tint: item.accessSnapshot.sourceExists ? .green : .red)
                StatusBadge(title: item.accessSnapshot.writeStatus, tint: item.accessSnapshot.sourceWritable ? .green : .orange)
                StatusBadge(title: item.accessSnapshot.metadataExists ? "Metadata" : "No Metadata", tint: item.accessSnapshot.metadataExists ? .blue : .gray)
            }

            Text(item.accessSnapshot.database.summaryLine)
                .font(.subheadline)
                .foregroundStyle(item.accessSnapshot.database.exists ? .primary : .secondary)

            if let error = item.accessSnapshot.lastError ?? item.accessSnapshot.database.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private struct LibrarySidebarRowView: View {
    let item: LibraryListItem
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title3)
                .foregroundStyle(item.descriptor.storageMode.tintColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.descriptor.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.accessSnapshot.database.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    StatusBadge(
                        title: item.descriptor.storageMode.title,
                        tint: item.descriptor.storageMode.tintColor
                    )
                    StatusBadge(
                        title: item.accessSnapshot.sourceExists ? "Ready" : "Needs Access",
                        tint: item.accessSnapshot.sourceExists ? .green : .orange
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private struct LibraryHomeDetailPlaceholder: View {
    let itemCount: Int
    let onAddLibrary: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.blue)

                Text(itemCount == 0 ? "Add a Library" : "Select a Library")
                    .font(.largeTitle.weight(.semibold))

                Text(descriptionText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 10) {
                StatusBadge(title: "Sidebar", tint: .blue)
                StatusBadge(title: "Folders", tint: .green)
                StatusBadge(title: "Reader", tint: .orange)
            }

            if itemCount == 0 {
                Button(action: onAddLibrary) {
                    Label("Add Library or Comics", systemImage: "plus")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.secondarySystemBackground),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var descriptionText: String {
        if itemCount == 0 {
            return "Import a YACReader library folder, or select comic files (zip/rar/cbz/cbr/pdf) to build your Imported Comics library."
        }

        return "Keep your libraries in the sidebar, browse the folder tree on the right, and move into reading without losing navigation context."
    }
}

private struct RemoteAccessRow: View {
    let compact: Bool
    let latestSession: RemoteComicReadingSession?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Remote SMB Servers")
                    .font(.headline)

                Text(descriptionText)
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : 2)

                if let latestSession {
                    Label(
                        "Last remote comic: \(latestSession.displayName) · \(latestSession.progressText)",
                        systemImage: "book.closed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 1)
                }

                HStack(spacing: 6) {
                    StatusBadge(title: "SMB", tint: .blue)
                    StatusBadge(title: "Single Comics", tint: .green)
                    StatusBadge(title: "On-Demand", tint: .orange)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
    }

    private var descriptionText: String {
        "Connect to an SMB share, browse remote folders, and open a single comic file without importing an entire library."
    }
}

private enum PendingLibraryAction {
    case rename(LibraryListItem)
    case info(LibraryListItem)
}
