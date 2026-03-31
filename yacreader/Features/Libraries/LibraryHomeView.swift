import SwiftUI
import UniformTypeIdentifiers

struct LibraryHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("libraryHome.selectedLibraryID") private var storedSelectedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedLibraryID) private var pendingFocusedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedFolderID) private var pendingFocusedFolderID = ""
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var activeImportRoute: LibraryHomeImportRoute?
    @State private var importDestinationRoute: LibraryHomeImportRoute?
    @State private var pendingImportDestinationSelection: LibraryImportDestinationSelection = .importedComics
    @State private var selectedLibraryID: UUID?
    @State private var libraryActionsItem: LibraryListItem?
    @State private var renamingLibraryItem: LibraryListItem?
    @State private var libraryInfoItem: LibraryListItem?
    @State private var pendingLibraryAction: PendingLibraryAction?
    @State private var compactNavigationPath: [UUID] = []
    @State private var focusedLibraryIDOverride: UUID?
    @State private var focusedFolderIDOverride: Int64?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .fileImporter(
            isPresented: activeImportRouteBinding,
            allowedContentTypes: activeImportContentTypes,
            allowsMultipleSelection: true
        ) { result in
            let importRoute = activeImportRoute
            activeImportRoute = nil

            switch result {
            case .success(let urls):
                handleImportSelection(urls, for: importRoute)
            case .failure(let error):
                viewModel.presentImportError(error)
            }
        }
        .onAppear {
            viewModel.reload()
            synchronizeSelection()
            handlePendingLibraryFocusIfNeeded()
        }
        .onChange(of: viewModel.items) { _, _ in
            synchronizeSelection()
            handlePendingLibraryFocusIfNeeded()
        }
        .onChange(of: selectedLibraryID) { _, newValue in
            storedSelectedLibraryID = newValue?.uuidString ?? ""
        }
        .onChange(of: pendingFocusedLibraryID) { _, _ in
            handlePendingLibraryFocusIfNeeded()
        }
        .onChange(of: pendingFocusedFolderID) { _, _ in
            handlePendingLibraryFocusIfNeeded()
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
        .sheet(item: $importDestinationRoute) { route in
            LibraryImportDestinationSheet(
                title: route.destinationPickerTitle,
                message: route.destinationPickerMessage,
                dependencies: dependencies,
                preferredSelection: preferredImportDestinationSelection
            ) { selection in
                pendingImportDestinationSelection = selection
                queueImporterPresentation(for: route)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeLibraryAlert(for: alert)
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
        NavigationStack(path: $compactNavigationPath) {
            Group {
                if viewModel.items.isEmpty {
                    EmptyStateView(
                        systemImage: "books.vertical",
                        title: "No Libraries Yet",
                        description: "Add a library folder or import comics to get started.",
                        actionTitle: "Add Library",
                        action: { presentLibraryFolderImporter() }
                    )
                    .background(Color.surfaceGrouped)
                } else {
                    List {
                        compactLibrariesSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                addLibraryToolbarItem
            }
            .refreshable {
                viewModel.reload()
            }
            .navigationDestination(for: UUID.self) { libraryID in
                if let item = viewModel.items.first(where: { $0.id == libraryID }) {
                    LibraryBrowserView(
                        descriptor: item.descriptor,
                        folderID: preferredFolderID(for: item),
                        dependencies: dependencies
                    )
                    .id(item.id)
                    .onAppear {
                        selectedLibraryID = item.id
                        consumeFocusedOverride(for: item.id)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "books.vertical",
                        title: "Library Unavailable",
                        description: "This library is no longer available on this device."
                    )
                }
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedLibraryID) {
                splitLibrariesSection
            }
            .navigationTitle("Library")
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
                    .onAppear {
                        consumeFocusedOverride(for: selectedItem.id)
                    }
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
                    Label("Import Comic Files", systemImage: "doc.badge.plus")
                }

                Button {
                    presentComicFolderImporter()
                } label: {
                    Label("Import Comic Folder", systemImage: "folder.badge.plus")
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

    private func handlePendingLibraryFocusIfNeeded() {
        guard let libraryID = UUID(uuidString: pendingFocusedLibraryID),
              let item = compatibleLibraryItem(for: libraryID) else {
            return
        }

        focusedLibraryIDOverride = item.id
        focusedFolderIDOverride = Int64(pendingFocusedFolderID).map { max(1, $0) }

        selectedLibraryID = item.id

        if usesSplitViewLayout {
            compactNavigationPath = []
        } else {
            compactNavigationPath = [item.id]
        }

        pendingFocusedLibraryID = ""
        pendingFocusedFolderID = ""
    }

    private func compatibleLibraryItem(for libraryID: UUID) -> LibraryListItem? {
        guard let item = viewModel.items.first(where: { $0.id == libraryID }) else {
            return nil
        }

        if let compatibilityIssue = item.accessSnapshot.database.compatibilityIssueDescription {
            let versionText = item.accessSnapshot.database.version ?? "Unknown"
            viewModel.alert = AppAlertState(
                title: "Library Version Not Supported",
                message: compatibilityIssue + "\n\nDetected DB version: \(versionText)."
            )
            pendingFocusedLibraryID = ""
            pendingFocusedFolderID = ""
            return nil
        }

        return item
    }

    private func consumeFocusedOverride(for libraryID: UUID) {
        guard focusedLibraryIDOverride == libraryID else {
            return
        }

        focusedLibraryIDOverride = nil
        focusedFolderIDOverride = nil
    }

    private func preferredFolderID(for item: LibraryListItem) -> Int64 {
        if focusedLibraryIDOverride == item.id, let focusedFolderIDOverride {
            return focusedFolderIDOverride
        }

        return LibraryBrowserView.lastOpenedFolderID(for: item.id)
    }

    private func presentLibraryFolderImporter() {
        queueImporterPresentation(for: .libraryFolder)
    }

    private func presentComicFileImporter() {
        importDestinationRoute = .comicFiles
    }

    private func presentComicFolderImporter() {
        importDestinationRoute = .comicFolder
    }

    private var activeImportRouteBinding: Binding<Bool> {
        Binding(
            get: { activeImportRoute != nil },
            set: { isPresented in
                if !isPresented {
                    activeImportRoute = nil
                }
            }
        )
    }

    private var preferredImportDestinationSelection: LibraryImportDestinationSelection? {
        if let selectedLibraryID {
            return .library(selectedLibraryID)
        }

        if let resumeLibraryItem {
            return .library(resumeLibraryItem.id)
        }

        return .importedComics
    }

    private var activeImportContentTypes: [UTType] {
        switch activeImportRoute {
        case .libraryFolder:
            return [.folder]
        case .comicFolder:
            return [.folder]
        case .comicFiles, .none:
            return [.data]
        }
    }

    private func queueImporterPresentation(for route: LibraryHomeImportRoute) {
        DispatchQueue.main.async {
            activeImportRoute = route
        }
    }

    private func handleImportSelection(_ urls: [URL], for route: LibraryHomeImportRoute?) {
        guard !urls.isEmpty else {
            return
        }

        switch route {
        case .libraryFolder:
            viewModel.addLibraryFolders(from: urls)
        case .comicFiles:
            viewModel.importComicFiles(
                from: urls,
                destinationSelection: pendingImportDestinationSelection
            )
        case .comicFolder:
            viewModel.importComicDirectories(
                from: urls,
                destinationSelection: pendingImportDestinationSelection
            )
        case .none:
            viewModel.presentImportError(
                NSError(
                    domain: "LibraryHomeImportRoute",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "The selected import action could not be resolved."]
                )
            )
        }
    }

    private var compactLibrariesSection: some View {
        Section {
            ForEach(viewModel.items) { item in
                Button {
                    openLibrary(item.id)
                } label: {
                    LibraryRowView(item: item)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .contextMenu {
                    libraryContextMenuActions(for: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.removeLibrary(id: item.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    Button {
                        renamingLibraryItem = item
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onDelete(perform: viewModel.removeLibraries)
        } header: {
            Text("Libraries")
        }
    }

    private var splitLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "No Libraries Yet",
                    description: "Add a library folder or import comics."
                )
                .padding(.vertical, Spacing.xl)
            } else {
                ForEach(viewModel.items) { item in
                    LibrarySidebarRowView(item: item)
                        .tag(item.id)
                        .contextMenu {
                            libraryContextMenuActions(for: item)
                        }
                }
                .onDelete(perform: viewModel.removeLibraries)
            }
        }
    }

    @ViewBuilder
    private func libraryContextMenuActions(for item: LibraryListItem) -> some View {
        Button {
            renamingLibraryItem = item
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            libraryInfoItem = item
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.removeLibrary(id: item.id)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func openLibrary(_ libraryID: UUID) {
        guard let item = compatibleLibraryItem(for: libraryID) else {
            return
        }

        let libraryID = item.id
        selectedLibraryID = libraryID

        if usesSplitViewLayout {
            return
        }

        compactNavigationPath = [libraryID]
    }

    private func queueLibraryAction(_ action: PendingLibraryAction) {
        pendingLibraryAction = action
        libraryActionsItem = nil
    }
}

private enum LibraryHomeImportRoute: Identifiable {
    case libraryFolder
    case comicFiles
    case comicFolder

    var id: String {
        switch self {
        case .libraryFolder:
            return "libraryFolder"
        case .comicFiles:
            return "comicFiles"
        case .comicFolder:
            return "comicFolder"
        }
    }

    var destinationPickerTitle: String {
        switch self {
        case .libraryFolder:
            return "Choose Import Destination"
        case .comicFiles:
            return "Import Comic Files"
        case .comicFolder:
            return "Import Comic Folder"
        }
    }

    var destinationPickerMessage: String {
        switch self {
        case .libraryFolder:
            return "Choose where imported comics should be copied."
        case .comicFiles:
            return "Choose which local library should receive the selected comic files."
        case .comicFolder:
            return "Choose which local library should receive the comic files found in the selected folder."
        }
    }
}

private struct LibraryRowView: View {
    let item: LibraryListItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: "books.vertical.fill",
                tint: item.descriptor.storageMode.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.descriptor.name)
                    .font(AppFont.body(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(item.rowSubtitle)
                    .font(AppFont.subheadline())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(AppFont.caption(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

private struct LibrarySidebarRowView: View {
    let item: LibraryListItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: "books.vertical.fill",
                tint: item.descriptor.storageMode.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.descriptor.name)
                    .font(AppFont.headline())
                    .lineLimit(1)

                Text(item.rowSubtitle)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

private func makeLibraryAlert(for alert: AppAlertState) -> Alert {
    if let primaryAction = alert.primaryAction {
        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            primaryButton: .default(Text(primaryAction.title)) {
                switch primaryAction {
                case .openLibrary(let libraryID, let folderID):
                    AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
                }
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

private struct LibraryHomeDetailPlaceholder: View {
    let itemCount: Int
    let onAddLibrary: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                itemCount == 0 ? "Add a Library" : "Select a Library",
                systemImage: "books.vertical"
            )
        } description: {
            Text(descriptionText)
        } actions: {
            if itemCount == 0 {
                Button(action: onAddLibrary) {
                    Label("Add Library", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var descriptionText: String {
        if itemCount == 0 {
            return "Add a library folder or import comics."
        }

        return "Choose a library from the sidebar."
    }
}

private enum PendingLibraryAction {
    case rename(LibraryListItem)
    case info(LibraryListItem)
}

private struct LibraryStatusNote {
    let text: String
    let systemImage: String
    let tint: Color
}

private extension LibraryListItem {
    var libraryScaleSummary: String {
        let database = accessSnapshot.database

        if database.exists {
            let comicText = database.comicCount == 1 ? "1 comic" : "\(database.comicCount) comics"
            let folderText = database.folderCount == 1 ? "1 folder" : "\(database.folderCount) folders"
            return "\(comicText) · \(folderText)"
        }

        if accessSnapshot.sourceExists {
            return "Library database needs initialization."
        }

        return "Library is currently unavailable on this device."
    }

    func homeMetadataItems(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> [InlineMetadataItem] {
        var items = [availabilityMetadataItem]

        if accessSnapshot.sourceReadable {
            items.append(writeAccessMetadataItem)
        }

        items.append(storageMetadataItem(compatibilityPresentation: compatibilityPresentation))
        return items
    }

    func sidebarMetadataItems(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> [InlineMetadataItem] {
        homeMetadataItems(compatibilityPresentation: compatibilityPresentation)
    }

    private var availabilityMetadataItem: InlineMetadataItem {
        if !accessSnapshot.sourceExists {
            return InlineMetadataItem(
                systemImage: "exclamationmark.triangle.fill",
                text: "Needs Access",
                tint: .orange
            )
        }

        if accessSnapshot.sourceReadable {
            return InlineMetadataItem(
                systemImage: "checkmark.circle.fill",
                text: "Ready",
                tint: .green
            )
        }

        return InlineMetadataItem(
            systemImage: "lock.circle.fill",
            text: "Unavailable",
            tint: .orange
        )
    }

    private var writeAccessMetadataItem: InlineMetadataItem {
        InlineMetadataItem(
            systemImage: accessSnapshot.sourceWritable ? "square.and.pencil" : "lock.fill",
            text: accessSnapshot.writeStatus,
            tint: accessSnapshot.sourceWritable ? .green : .orange
        )
    }

    private func storageMetadataItem(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> InlineMetadataItem {
        if descriptor.storageMode == .mirrored || compatibilityPresentation.badgeTitle == "Desktop Compatible" {
            return InlineMetadataItem(
                systemImage: "desktopcomputer",
                text: "Desktop Compatible",
                tint: .blue
            )
        }

        return InlineMetadataItem(
            systemImage: "books.vertical.fill",
            text: "Local Library",
            tint: .teal
        )
    }

    func homeRowStatusNote(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> LibraryStatusNote? {
        if let error = accessSnapshot.lastError ?? accessSnapshot.database.lastError {
            return LibraryStatusNote(
                text: error,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        if let maintenanceRecord {
            return LibraryStatusNote(
                text: maintenanceRecord.summaryLine,
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: .secondary
            )
        }

        if let compatibilityNote = compatibilityPresentation.rowHint,
           let iconName = compatibilityPresentation.iconName {
            return LibraryStatusNote(
                text: compatibilityNote,
                systemImage: iconName,
                tint: .secondary
            )
        }

        return nil
    }

    func sidebarStatusNote(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> LibraryStatusNote? {
        if let maintenanceRecord {
            return LibraryStatusNote(
                text: maintenanceRecord.summaryLine,
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: .secondary
            )
        }

        if let compatibilityNote = compatibilityPresentation.rowHint,
           let iconName = compatibilityPresentation.iconName {
            return LibraryStatusNote(
                text: compatibilityNote,
                systemImage: iconName,
                tint: .secondary
            )
        }

        if let error = accessSnapshot.lastError ?? accessSnapshot.database.lastError {
            return LibraryStatusNote(
                text: error,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        return nil
    }
}
