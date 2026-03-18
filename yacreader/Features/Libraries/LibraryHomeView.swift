import SwiftUI
import UniformTypeIdentifiers

struct LibraryHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var isImporterPresented = false
    @State private var selectedLibraryID: UUID?
    @State private var libraryActionsItem: LibraryListItem?
    @State private var renamingLibraryItem: LibraryListItem?
    @State private var libraryInfoItem: LibraryListItem?
    @State private var pendingLibraryAction: PendingLibraryAction?

    var body: some View {
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
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
        .onAppear {
            viewModel.reload()
            synchronizeSelection()
        }
        .onChange(of: viewModel.items) { _, _ in
            synchronizeSelection()
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
                        dependencies: dependencies
                    )
                    .id(selectedItem.id)
                } else {
                    LibraryHomeDetailPlaceholder(
                        itemCount: viewModel.items.count,
                        onAddLibrary: {
                            isImporterPresented = true
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
            Button {
                isImporterPresented = true
            } label: {
                Label("Add Library", systemImage: "plus")
            }
        }
    }

    private var selectedItem: LibraryListItem? {
        guard let selectedLibraryID else {
            return nil
        }

        return viewModel.items.first(where: { $0.id == selectedLibraryID })
    }

    private func synchronizeSelection() {
        if viewModel.items.isEmpty {
            selectedLibraryID = nil
        } else if let selectedLibraryID,
                  viewModel.items.contains(where: { $0.id == selectedLibraryID }) {
            return
        } else {
            selectedLibraryID = viewModel.items.first?.id
        }
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Migration Bootstrap")
                    .font(.headline)

                Text("The app now has a persistent library registry, storage mode detection, metadata path planning, and a live SQLite inspector for existing desktop libraries.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(title: "M0", tint: .blue)
                    StatusBadge(title: "M1", tint: .green)
                    Text("Foundation in progress")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
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
                    description: Text("Choose a folder to register an existing library root or to prepare a new YACReader library.")
                )
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        LibraryBrowserView(
                            descriptor: item.descriptor,
                            dependencies: dependencies
                        )
                    } label: {
                        LibraryRowView(
                            item: item,
                            trailingAccessoryReservedWidth: 40
                        )
                    }
                    .overlay(alignment: .trailing) {
                        libraryQuickActionButton(for: item)
                            .padding(.trailing, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
                .onDelete(perform: viewModel.removeLibraries)
            }
        }
    }

    private var sidebarOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Library Workspace")
                    .font(.headline)

                Text("Use the sidebar to keep libraries in reach while browsing folders and reading on the detail side.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    StatusBadge(title: "\(viewModel.items.count) libraries", tint: .blue)
                    StatusBadge(title: "iPad", tint: .green)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var splitLibrariesSection: some View {
        Section("Libraries") {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No Libraries Yet",
                    systemImage: "books.vertical",
                    description: Text("Add a library folder to start browsing in split view.")
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

private struct LibraryRowView: View {
    let item: LibraryListItem
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.descriptor.name)
                        .font(.headline)

                    Text(item.descriptor.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                StatusBadge(title: item.accessSnapshot.metadataExists ? "Metadata Ready" : "Metadata Missing", tint: item.accessSnapshot.metadataExists ? .blue : .gray)
            }

            Text(item.accessSnapshot.database.summaryLine)
                .font(.subheadline)
                .foregroundStyle(item.accessSnapshot.database.exists ? .primary : .secondary)

            Group {
                Text("Metadata: \(item.metadataPath)")
                Text("Database: \(item.databasePath)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if let error = item.accessSnapshot.lastError ?? item.accessSnapshot.database.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                    Label("Add Library", systemImage: "plus")
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
            return "Import an existing YACReader library root, or register a new folder so the iPad workspace can open it in split view."
        }

        return "Keep your libraries in the sidebar, browse the folder tree on the right, and move into reading without losing navigation context."
    }
}

private enum PendingLibraryAction {
    case rename(LibraryListItem)
    case info(LibraryListItem)
}
