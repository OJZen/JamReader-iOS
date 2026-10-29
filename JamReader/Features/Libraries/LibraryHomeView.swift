import SwiftUI
import UIKit

/// Library home: the list of local libraries (the sidebar on iPad).
/// See docs/design-system/components/ScreenLibraryHome.
struct LibraryHomeView: View {
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter
    @AppStorage(AppNavigationStorageKeys.libraryHomeSelectedLibraryID) private var storedSelectedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedLibraryID) private var pendingFocusedLibraryID = ""
    @AppStorage(AppNavigationStorageKeys.pendingFocusedFolderID) private var pendingFocusedFolderID = ""
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var selectedLibraryID: UUID?
    @State private var focusedLibraryIDOverride: UUID?
    @State private var focusedFolderIDOverride: Int64?
    @State private var pendingLibraryRemoval: LibraryRemovalRequest?

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                // On iPad the detail column shows the empty state and its button.
                if usesPersistentSelection {
                    Color.surfaceGrouped
                } else {
                    LibraryEmptyStateView(onAddComics: presentAddComicsSheet)
                        .background(Color.surfaceGrouped)
                }
            } else {
                content
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .taskBanner {
            if viewModel.isImporting {
                TaskBanner(
                    content: viewModel.importProgress?.taskBannerContent(
                        destinationName: viewModel.importDestinationName
                    ) ?? TaskBannerContent(
                        phase: .running(fraction: nil),
                        title: String(localized: "Preparing Import"),
                        detail: viewModel.importDestinationName.map { String(localized: "To \($0)") }
                    ),
                    onClose: viewModel.cancelComicImport
                )
            }
        }
        .toolbar {
            if !viewModel.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: presentAddComicsSheet) {
                        Label("Add Comics", systemImage: "plus")
                    }
                }
            }
        }
        .refreshable {
            viewModel.reload()
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
        .onChange(of: viewModel.completedImport) { _, completedImport in
            // Imports land in the library root, so open it there with the result bar.
            if let completedImport {
                selectedLibraryID = completedImport.libraryID
                appNavigator?.navigate(.library(.openLibrary(completedImport.libraryID, folderID: 1)))
            }
        }
        .onChange(of: selectedLibraryID) { _, newValue in
            storedSelectedLibraryID = newValue?.uuidString ?? ""
        }
        .onChange(of: storedSelectedLibraryID) { _, _ in
            synchronizeSelection(preferStoredSelection: true)
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
        .confirmationDialog(
            pendingLibraryRemoval?.title ?? String(localized: "Remove Library?"),
            isPresented: pendingLibraryRemovalBinding,
            titleVisibility: .visible
        ) {
            if let pendingLibraryRemoval {
                Button(pendingLibraryRemoval.actionTitle, role: .destructive) {
                    performLibraryRemoval(pendingLibraryRemoval)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingLibraryRemoval = nil
            }
        } message: {
            if let pendingLibraryRemoval {
                Text(pendingLibraryRemoval.message)
            }
        }
    }

    private var content: some View {
        List {
            librariesSection
        }
        .adaptiveRootListStyle(usesSidebarStyle: usesPersistentSelection)
    }

    private var librariesSection: some View {
        Section {
            ForEach(viewModel.items) { item in
                Button {
                    openLibrary(item.id)
                } label: {
                    if usesPersistentSelection {
                        LibrarySidebarRow(
                            item: item,
                            isSelected: selectedLibraryID == item.id
                        )
                    } else {
                        LibraryRowView(item: item)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .persistentSidebarSelection(
                    isSelected: selectedLibraryID == item.id,
                    isEnabled: usesPersistentSelection
                )
                .contextMenu {
                    libraryContextMenuActions(for: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        requestLibraryRemoval([item])
                    } label: {
                        Label(item.removalActionTitle, systemImage: "trash")
                    }
                    Button {
                        presentRenameSheet(for: item)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.appJam)
                }
            }
        } header: {
            Text("My Libraries")
                .font(usesPersistentSelection ? nil : AppFont.title2(.bold))
                .foregroundStyle(usesPersistentSelection ? Color.textSecondary : Color.textPrimary)
                .textCase(nil)
        }
    }

    private var usesPersistentSelection: Bool {
        AppLayout.usesPersistentSplitSelection(
            isPad: UIDevice.current.userInterfaceIdiom == .pad
        )
    }

    private func synchronizeSelection(preferStoredSelection: Bool = false) {
        if viewModel.items.isEmpty {
            selectedLibraryID = nil
        } else if preferStoredSelection,
                  let storedLibraryID = UUID(uuidString: storedSelectedLibraryID),
                  viewModel.items.contains(where: { $0.id == storedLibraryID }) {
            selectedLibraryID = storedLibraryID
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

    private func preferredFolderID(for item: LibraryListItem) -> Int64 {
        if focusedLibraryIDOverride == item.id, let focusedFolderIDOverride {
            return focusedFolderIDOverride
        }

        return LibraryBrowserView.lastOpenedFolderID(for: item.id)
    }

    private var pendingLibraryRemovalBinding: Binding<Bool> {
        Binding(
            get: { pendingLibraryRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingLibraryRemoval = nil
                }
            }
        )
    }

    private func requestLibraryRemoval(_ items: [LibraryListItem]) {
        guard !items.isEmpty else {
            return
        }

        pendingLibraryRemoval = LibraryRemovalRequest(items: items)
    }

    private func performLibraryRemoval(_ request: LibraryRemovalRequest) {
        pendingLibraryRemoval = nil
        AppHaptics.warning()
        let removedIDs = Set(request.items.map(\.id))
        guard viewModel.removeLibraries(ids: Array(removedIDs)) else {
            return
        }
        handleRemovedLibraries(removedIDs)
    }

    private func handleRemovedLibraries(_ removedIDs: Set<UUID>) {
        let removedCurrentSelection = selectedLibraryID.map(removedIDs.contains) ?? false
        guard usesPersistentSelection, removedCurrentSelection else {
            synchronizeSelection()
            return
        }

        if let replacementID = viewModel.items.first?.id {
            selectedLibraryID = replacementID
            appNavigator?.navigate(.library(.openLibrary(replacementID, folderID: nil)))
        } else {
            selectedLibraryID = nil
            appNavigator?.navigate(.library(.home))
        }
    }

    /// The same actions as Library Info, reused by long press.
    @ViewBuilder
    private func libraryContextMenuActions(for item: LibraryListItem) -> some View {
        Button {
            presentRenameSheet(for: item)
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        Button {
            presentInfoSheet(for: item)
        } label: {
            Label("Library Info", systemImage: "info.circle")
        }

        Divider()

        Button(role: .destructive) {
            requestLibraryRemoval([item])
        } label: {
            Label(item.removalButtonTitle, systemImage: "trash")
        }
    }

    private func openLibrary(_ libraryID: UUID) {
        guard let item = libraryItem(for: libraryID) else {
            return
        }

        selectedLibraryID = item.id
        appNavigator?.navigate(
            .library(.openLibrary(item.id, folderID: preferredFolderID(for: item)))
        )
    }

    private func presentAddComicsSheet() {
        appPresenter?.presentSheet(
            Self.addComicsSheetRoute(
                viewModel: viewModel,
                dependencies: dependencies,
                presenter: appPresenter,
                navigator: appNavigator
            )
        )
    }

    /// The Add Comics sheet, shared by the home [+], the empty state and the
    /// iPad detail placeholder.
    static func addComicsSheetRoute(
        viewModel: LibraryListViewModel,
        dependencies: AppDependencies,
        presenter: UIKitPresentationCoordinator?,
        navigator: AppNavigator?
    ) -> AppSheetRoute {
        .content(
            id: "library.addComics",
            content: AnyView(
                LibraryAddComicsSheet(
                    dependencies: dependencies,
                    onImport: { urls, traverseDirectories, destination in
                        presenter?.dismissSheet()
                        if traverseDirectories {
                            viewModel.importComicDirectories(from: urls, destinationSelection: destination)
                        } else {
                            viewModel.importComicFiles(from: urls, destinationSelection: destination)
                        }
                    },
                    onLinkFolders: { urls in
                        presenter?.dismissSheet()
                        let addedIDs = viewModel.addLibraryFolders(from: urls)
                        if addedIDs.count == 1, let libraryID = addedIDs.first {
                            navigator?.navigate(.library(.openLibrary(libraryID, folderID: nil)))
                        }
                    },
                    onCreateLibrary: { proposedName in
                        guard let libraryID = viewModel.createLibrary(named: proposedName) else {
                            return false
                        }
                        presenter?.dismissSheet()
                        navigator?.navigate(.library(.openLibrary(libraryID, folderID: nil)))
                        return true
                    },
                    onPickerError: { error in
                        presenter?.dismissSheet()
                        viewModel.presentImportError(error)
                    }
                )
                .environment(\.appPresenter, presenter)
                .environment(\.appNavigator, navigator)
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
        let libraryID = item.id
        appPresenter?.presentSheet(
            .content(
                id: "library.info.\(libraryID.uuidString)",
                content: AnyView(
                    LibraryInfoSheet(listViewModel: viewModel, libraryID: libraryID) {
                        handleRemovedLibraries([libraryID])
                    }
                )
            )
        )
    }
}

/// Library row: type tile, name, "count · storage", and a status badge when
/// access is read-only or lost.
private struct LibraryRowView: View {
    let item: LibraryListItem
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(
                systemName: item.descriptor.kind.systemImageName,
                color: item.descriptor.kind.tileColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.descriptor.displayName)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                Text(item.storageSummary)
                    .font(AppFont.footnote().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let status = item.accessStatus {
                StatusBadge(status: status)
            }

            if showsDisclosureIndicator {
                Image(systemName: "chevron.forward")
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.xxxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// iPad sidebar row (44pt): type symbol, name, comic count; a status icon
/// replaces the count when access is read-only or lost.
private struct LibrarySidebarRow: View {
    let item: LibraryListItem
    let isSelected: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: item.descriptor.kind.systemImageName)
                .font(AppFont.body())
                .foregroundStyle(Color.appAccent)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Large text moves the count under the name so whole words fit the sidebar.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    name
                    trailingInfo
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                name
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailingInfo
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var name: some View {
        Text(item.descriptor.displayName)
            .font(AppFont.body(isSelected ? .semibold : .regular))
            .foregroundStyle(Color.textPrimary)
    }

    @ViewBuilder
    private var trailingInfo: some View {
        if let status = item.accessStatus, let systemImage = status.systemImage {
            Image(systemName: systemImage)
                .foregroundStyle(status.foregroundColor)
                .accessibilityLabel(status.title)
        } else if item.accessSnapshot.database.exists {
            Text("\(item.accessSnapshot.database.comicCount)")
                .font(AppFont.subheadline().monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
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
    let onAddComics: () -> Void

    var body: some View {
        Group {
            if itemCount == 0 {
                LibraryEmptyStateView(onAddComics: onAddComics)
            } else {
                ContentUnavailableView(
                    "Select a Library",
                    systemImage: "books.vertical",
                    description: Text("Choose a library from the sidebar.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceGrouped)
    }
}

/// First-run empty state: one Add Comics button (the toolbar [+] is hidden
/// meanwhile) and a link to connect a NAS server in Remote.
struct LibraryEmptyStateView: View {
    @Environment(\.appNavigator) private var appNavigator
    @AppStorage(AppNavigationStorageKeys.pendingAddRemoteServer) private var pendingAddRemoteServer = false

    let onAddComics: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Comics Yet", systemImage: "books.vertical")
        } description: {
            Text("Import comic files, or use a comics folder you already have in Files.")
        } actions: {
            Button(action: onAddComics) {
                Label("Add Comics", systemImage: "plus")
                    .font(AppFont.body(.semibold))
                    .padding(.horizontal, Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appJam)
            .controlSize(.large)

            Button("Or Connect a NAS Server") {
                pendingAddRemoteServer = true
                appNavigator?.navigate(.selectTab(.browse))
            }
            .font(AppFont.subheadline(.semibold))
            .foregroundStyle(Color.appAccent)
            .buttonStyle(.borderless)
        }
    }
}
