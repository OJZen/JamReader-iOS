import SwiftUI
import UniformTypeIdentifiers

struct LibraryHomeView: View {
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter

    @AppStorage("libraryHome.selectedLibraryID") private var storedSelectedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedLibraryID) private var pendingFocusedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedFolderID) private var pendingFocusedFolderID = ""
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var activeImportRoute: LibraryHomeImportRoute?
    @State private var pendingImportDestinationSelection: LibraryImportDestinationSelection = .importedComics
    @State private var selectedLibraryID: UUID?
    @State private var focusedLibraryIDOverride: UUID?
    @State private var focusedFolderIDOverride: Int64?

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                EmptyStateView(
                    systemImage: "books.vertical",
                    title: "No Libraries Yet",
                    description: "Create a library on this device, add a linked folder, or import comics to get started.",
                    actionTitle: "New Library",
                    action: { presentCreateLibrarySheet() }
                )
                .background(Color.surfaceGrouped)
            } else {
                content
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
        .alert(item: $viewModel.alert) { alert in
            makeLibraryAlert(for: alert)
        }
    }

    private var content: some View {
        List {
            librariesSection
        }
        .listStyle(.insetGrouped)
    }

    @ToolbarContentBuilder
    private var addLibraryToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    presentCreateLibrarySheet()
                } label: {
                    Label("New Library", systemImage: "plus.rectangle.on.folder.fill")
                }

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
              let item = libraryItem(for: libraryID) else {
            return
        }

        focusedLibraryIDOverride = item.id
        focusedFolderIDOverride = Int64(pendingFocusedFolderID).map { max(1, $0) }

        selectedLibraryID = item.id
        appNavigator?.navigate(
            .library(.openLibrary(item.id, folderID: focusedFolderIDOverride))
        )

        pendingFocusedLibraryID = ""
        pendingFocusedFolderID = ""
    }

    private func libraryItem(for libraryID: UUID) -> LibraryListItem? {
        viewModel.items.first(where: { $0.id == libraryID })
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

    private func presentCreateLibrarySheet() {
        appPresenter?.presentSheet(
            .content(
                id: "library.create",
                content: AnyView(
                    LibraryCreateSheet { proposedName in
                        guard let libraryID = viewModel.createLibrary(named: proposedName) else {
                            return false
                        }

                        appPresenter?.dismissSheet()
                        focusLibrary(libraryID)
                        return true
                    }
                )
            )
        )
    }

    private func presentComicFileImporter() {
        presentImportDestinationSheet(for: .comicFiles)
    }

    private func presentComicFolderImporter() {
        presentImportDestinationSheet(for: .comicFolder)
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

    private var librariesSection: some View {
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
                        Label(item.removalActionTitle, systemImage: "trash")
                    }
                    Button {
                        presentRenameSheet(for: item)
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

    @ViewBuilder
    private func libraryContextMenuActions(for item: LibraryListItem) -> some View {
        Button {
            presentRenameSheet(for: item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            presentInfoSheet(for: item)
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            viewModel.removeLibrary(id: item.id)
        } label: {
            Label(item.removalActionTitle, systemImage: "trash")
        }
    }

    private func openLibrary(_ libraryID: UUID) {
        guard let item = libraryItem(for: libraryID) else {
            return
        }

        let libraryID = item.id
        selectedLibraryID = libraryID
        appNavigator?.navigate(
            .library(.openLibrary(libraryID, folderID: preferredFolderID(for: item)))
        )
    }

    private func focusLibrary(_ libraryID: UUID) {
        selectedLibraryID = libraryID
        storedSelectedLibraryID = libraryID.uuidString
        appNavigator?.navigate(.library(.openLibrary(libraryID, folderID: nil)))
    }

    private func presentActionsSheet(for item: LibraryListItem) {
        appPresenter?.presentSheet(
            .content(
                id: "library.actions.\(item.id.uuidString)",
                content: AnyView(
                    LibraryHomeLibraryActionsSheet(
                        item: item,
                        onDone: { appPresenter?.dismissSheet() },
                        onRename: { presentRenameSheet(for: item) },
                        onViewInfo: { presentInfoSheet(for: item) },
                        onRemove: {
                            viewModel.removeLibrary(id: item.id)
                            appPresenter?.dismissSheet()
                        }
                    )
                )
            )
        )
    }

    private func presentRenameSheet(for item: LibraryListItem) {
        appPresenter?.presentSheet(
            .content(
                id: "library.rename.\(item.id.uuidString)",
                content: AnyView(
                    LibraryRenameSheet(item: item) { proposedName in
                        viewModel.renameLibrary(id: item.id, to: proposedName)
                    }
                )
            )
        )
    }

    private func presentInfoSheet(for item: LibraryListItem) {
        appPresenter?.presentSheet(
            .content(
                id: "library.info.\(item.id.uuidString)",
                content: AnyView(LibraryInfoSheet(item: item))
            )
        )
    }

    private func presentImportDestinationSheet(for route: LibraryHomeImportRoute) {
        appPresenter?.presentSheet(
            .content(
                id: "library.import.destination.\(route.id)",
                content: AnyView(
                    LibraryImportDestinationSheet(
                        title: route.destinationPickerTitle,
                        message: route.destinationPickerMessage,
                        dependencies: dependencies,
                        preferredSelection: preferredImportDestinationSelection
                    ) { selection in
                        pendingImportDestinationSelection = selection
                        appPresenter?.dismissSheet()
                        queueImporterPresentation(for: route)
                    }
                )
            )
        )
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
                tint: item.kindTint
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
                tint: item.kindTint
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

struct LibraryHomeDetailPlaceholder: View {
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
                    Label("New Library", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var descriptionText: String {
        if itemCount == 0 {
            return "Create a local library, add a linked folder, or import comics."
        }

        return "Choose a library from the sidebar."
    }
}

private struct LibraryStatusNote {
    let text: String
    let systemImage: String
    let tint: Color
}

private extension LibraryListItem {
    var kindTint: Color {
        switch descriptor.kind {
        case .appManaged:
            return .indigo
        case .importedComics:
            return .teal
        case .linkedFolder:
            return .blue
        }
    }

    var removalActionTitle: String {
        descriptor.kind.isManagedByApp ? "Delete" : "Remove"
    }

    var libraryScaleSummary: String {
        let database = accessSnapshot.database

        if database.exists {
            let comicText = database.comicCount == 1 ? "1 comic" : "\(database.comicCount) comics"
            let folderText = database.folderCount == 1 ? "1 folder" : "\(database.folderCount) folders"
            return "\(comicText) · \(folderText)"
        }

        if accessSnapshot.sourceExists {
            return "Local state has not been indexed yet."
        }

        return "Library is currently unavailable on this device."
    }

    func homeMetadataItems() -> [InlineMetadataItem] {
        var items = [availabilityMetadataItem]

        if accessSnapshot.sourceReadable {
            items.append(writeAccessMetadataItem)
        }

        items.append(storageMetadataItem)
        return items
    }

    func sidebarMetadataItems() -> [InlineMetadataItem] {
        homeMetadataItems()
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

    private var storageMetadataItem: InlineMetadataItem {
        return InlineMetadataItem(
            systemImage: "books.vertical.fill",
            text: descriptor.kind.title,
            tint: kindTint
        )
    }

    func homeRowStatusNote() -> LibraryStatusNote? {
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

        return nil
    }

    func sidebarStatusNote() -> LibraryStatusNote? {
        if let maintenanceRecord {
            return LibraryStatusNote(
                text: maintenanceRecord.summaryLine,
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
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
