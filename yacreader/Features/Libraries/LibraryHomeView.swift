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
            List {
                overviewSection
                compactLibrariesSection
            }
            .navigationTitle("Library")
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
                    ContentUnavailableView(
                        "Library Unavailable",
                        systemImage: "books.vertical",
                        description: Text("This library is no longer available on this device.")
                    )
                }
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView {
            List(selection: $selectedLibraryID) {
                sidebarOverviewSection
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
              viewModel.items.contains(where: { $0.id == libraryID }) else {
            return
        }

        focusedLibraryIDOverride = libraryID
        focusedFolderIDOverride = Int64(pendingFocusedFolderID).map { max(1, $0) }

        selectedLibraryID = libraryID

        if usesSplitViewLayout {
            compactNavigationPath = []
        } else {
            compactNavigationPath = [libraryID]
        }

        pendingFocusedLibraryID = ""
        pendingFocusedFolderID = ""
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

    private var overviewSection: some View {
        Section {
            InsetCard(cornerRadius: 24, contentPadding: 18, strokeOpacity: 0.04) {
                Text("Continue Where You Left Off")
                    .font(.headline)

                if let resumeLibraryItem {
                    NavigationLink(value: resumeLibraryItem.id) {
                        let compatibilityPresentation = LibraryCompatibilityPresentation.resolve(
                            descriptor: resumeLibraryItem.descriptor,
                            accessSnapshot: resumeLibraryItem.accessSnapshot
                        )
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Label {
                                    Text(resumeLibraryItem.descriptor.name)
                                        .font(.subheadline.weight(.semibold))
                                } icon: {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .frame(width: 30, height: 30)
                                }
                                .labelStyle(.titleAndIcon)

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }

                            AdaptiveStatusBadgeGroup(
                                badges: libraryOverviewBadges(
                                    item: resumeLibraryItem,
                                    compatibilityBadgeTitle: compatibilityPresentation.badgeTitle
                                )
                            )

                            FormOverviewContent(
                                items: libraryResumeOverviewItems(for: resumeLibraryItem)
                            ) {
                                if let maintenanceRecord = resumeLibraryItem.maintenanceRecord {
                                    Label(maintenanceRecord.summaryLine, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let compatibilityNote = compatibilityPresentation.rowHint,
                                   let iconName = compatibilityPresentation.iconName {
                                    Label(compatibilityNote, systemImage: iconName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Add a library or import comics.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        presentLibraryFolderImporter()
                    } label: {
                        Label("Add Library Folder", systemImage: "folder.badge.plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Menu {
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
                        Label("Import Comics", systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func libraryResumeOverviewItems(
        for item: LibraryListItem
    ) -> [FormOverviewItem] {
        [
            FormOverviewItem(
                title: "Database",
                value: item.accessSnapshot.database.summaryLine
            )
        ]
    }

    private var compactLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                LibraryListEmptyState(
                    description: "Add a library folder or import comics."
                )
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: item.id) {
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

    private var sidebarOverviewSection: some View {
        Section {
            SectionSummaryCard(
                title: "Library",
                badges: sidebarOverviewBadges,
                titleFont: .headline,
                cornerRadius: 20,
                contentPadding: 16,
                strokeOpacity: 0.04
            )
        }
    }

    private var sidebarOverviewBadges: [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(title: "\(viewModel.items.count) libraries", tint: .blue)
        ]

        if let resumeLibraryItem {
            badges.append(
                StatusBadgeItem(
                    title: resumeLibraryItem.descriptor.storageMode.title,
                    tint: resumeLibraryItem.descriptor.storageMode.tintColor
                )
            )
        }

        return badges
    }

    private func libraryOverviewBadges(
        item: LibraryListItem,
        compatibilityBadgeTitle: String?
    ) -> [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: item.descriptor.storageMode.title,
                tint: item.descriptor.storageMode.tintColor
            )
        ]

        if let compatibilityBadgeTitle {
            badges.append(StatusBadgeItem(title: compatibilityBadgeTitle, tint: .orange))
        }

        return badges
    }

    private var splitLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                LibraryListEmptyState(
                    description: "Add a library folder or import comics."
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

    private var compactLibraryActionReservedWidth: CGFloat {
        44
    }

    private func libraryQuickActionButton(for item: LibraryListItem) -> some View {
        LibraryHomeQuickActionButton {
            libraryActionsItem = item
        }
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

private struct LibraryListEmptyState: View {
    let description: String

    var body: some View {
        ContentUnavailableView(
            "No Libraries Yet",
            systemImage: "books.vertical",
            description: Text(description)
        )
    }
}

private struct LibraryRowView: View {
    let item: LibraryListItem
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        let compatibilityPresentation = LibraryCompatibilityPresentation.resolve(
            descriptor: item.descriptor,
            accessSnapshot: item.accessSnapshot
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(item.descriptor.storageMode.tintColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.descriptor.name)
                        .font(.headline)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    title: item.descriptor.storageMode.title,
                    tint: item.descriptor.storageMode.tintColor
                )
            }

            AdaptiveStatusBadgeGroup(
                badges: item.homeRowBadges(compatibilityBadgeTitle: compatibilityPresentation.badgeTitle)
            )

            Text(item.accessSnapshot.database.summaryLine)
                .font(.subheadline)
                .foregroundStyle(item.accessSnapshot.database.exists ? .primary : .secondary)
                .lineLimit(1)

            if let statusNote = item.homeRowStatusNote(compatibilityPresentation: compatibilityPresentation) {
                Label(statusNote.text, systemImage: statusNote.systemImage)
                    .font(.caption)
                    .foregroundStyle(statusNote.tint)
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
        let compatibilityPresentation = LibraryCompatibilityPresentation.resolve(
            descriptor: item.descriptor,
            accessSnapshot: item.accessSnapshot
        )

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
                    .lineLimit(1)

                if let statusNote = item.sidebarStatusNote(compatibilityPresentation: compatibilityPresentation) {
                    Label(statusNote.text, systemImage: statusNote.systemImage)
                        .font(.caption2)
                        .foregroundStyle(statusNote.tint)
                        .lineLimit(1)
                }

                AdaptiveStatusBadgeGroup(
                    badges: item.sidebarRowBadges(compatibilityBadgeTitle: compatibilityPresentation.badgeTitle),
                    horizontalSpacing: 6,
                    verticalSpacing: 6
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }
}

private func makeLibraryAlert(for alert: LibraryAlertState) -> Alert {
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
    func homeRowBadges(compatibilityBadgeTitle: String?) -> [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: accessSnapshot.sourceExists ? "Ready" : "Needs Access",
                tint: accessSnapshot.sourceExists ? .green : .orange
            ),
            StatusBadgeItem(
                title: accessSnapshot.metadataExists ? "Metadata" : "No Metadata",
                tint: accessSnapshot.metadataExists ? .blue : .gray
            )
        ]

        if let compatibilityBadgeTitle {
            badges.append(StatusBadgeItem(title: compatibilityBadgeTitle, tint: .orange))
        }

        return badges
    }

    func sidebarRowBadges(compatibilityBadgeTitle: String?) -> [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: descriptor.storageMode.title,
                tint: descriptor.storageMode.tintColor
            ),
            StatusBadgeItem(
                title: accessSnapshot.sourceExists ? "Ready" : "Needs Access",
                tint: accessSnapshot.sourceExists ? .green : .orange
            )
        ]

        if let compatibilityBadgeTitle {
            badges.append(StatusBadgeItem(title: compatibilityBadgeTitle, tint: .orange))
        }

        return badges
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
