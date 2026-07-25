import SwiftUI
import UIKit

struct BrowseHomeView: View {
    @Environment(\.appNavigator) private var appNavigator
    @AppStorage(AppNavigationStorageKeys.browseHomeSelection) private var storedSelectionRawValue = ""

    let dependencies: AppDependencies

    @ObservedObject private var viewModel: RemoteServerListViewModel
    @Binding private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var splitSelection: BrowseHomeSplitSelection?

    init(
        dependencies: AppDependencies,
        viewModel: RemoteServerListViewModel,
        editorDraft: Binding<RemoteServerEditorDraft?>
    ) {
        self.dependencies = dependencies
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _editorDraft = editorDraft
    }

    var body: some View {
        content
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            addServerToolbarItem
        }
        .refreshable {
            viewModel.load()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.refreshOfflineCopyCounts(forceRefresh: true)
            restoreSelectionIfNeeded()
        }
        .onChange(of: displayedProfiles.map(\.id)) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: quickAccessItems.map(\.id)) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: storedSelectionRawValue) { _, _ in
            synchronizeSelection(preferStoredSelection: true)
        }
        .onChange(of: splitSelection) { _, newValue in
            persistSelection(newValue)
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .confirmationDialog(
            "Delete Server?",
            isPresented: Binding(
                get: { pendingDeletionProfile != nil },
                set: { if !$0 { pendingDeletionProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletionProfile {
                Button("Delete \(pendingDeletionProfile.name)", role: .destructive) {
                    performServerDeletion(pendingDeletionProfile)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionProfile = nil
            }
        } message: {
            if let pendingDeletionProfile {
                Text("This removes \(pendingDeletionProfile.name) and clears its local offline data on this device.")
            }
        }
    }

    private var content: some View {
        Group {
            if displayedProfiles.isEmpty && !showsQuickAccess {
                BrowseHomeEmptyState(
                    showsGuidance: !usesPersistentSelection,
                    onAddServer: presentCreateServerSheet
                )
            } else {
                List {
                    serversSection

                    if showsQuickAccess {
                        quickAccessSection
                    }
                }
                .adaptiveRootListStyle(usesSidebarStyle: usesPersistentSelection)
            }
        }
    }

    // MARK: - Servers Section

    @ViewBuilder
    private var serversSection: some View {
        Section {
            ForEach(displayedProfiles) { profile in
                Button {
                    open(.server(profile.id))
                } label: {
                    BrowseHomeServerRow(
                        profile: profile,
                        isSelected: usesPersistentSelection && splitSelection == .server(profile.id),
                        showsDisclosureIndicator: !usesPersistentSelection,
                        trailingAccessoryReservedWidth: usesPersistentSelection
                            ? AppLayout.persistentRowActionReservedWidth
                            : 0
                    )
                }
                .buttonStyle(.plain)
                .persistentSidebarSelection(
                    isSelected: splitSelection == .server(profile.id),
                    isEnabled: usesPersistentSelection
                )
                .overlay(alignment: .trailing) {
                    if usesPersistentSelection {
                        Menu {
                            serverActionMenuContent(for: profile)
                        } label: {
                            PersistentRowActionButtonLabel()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Manage \(profile.displayTitle)")
                        .padding(.trailing, Spacing.xs)
                    }
                }
                .contextMenu {
                    serverActionMenuContent(for: profile)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        requestEditorPresentation(viewModel.makeEditDraft(for: profile))
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Servers")
        }
    }

    // MARK: - Quick Access Section

    private var quickAccessSection: some View {
        Section {
            ForEach(quickAccessItems) { item in
                Button {
                    open(item.splitSelection)
                } label: {
                    BrowseHomeQuickAccessRow(
                        item: item,
                        isSelected: usesPersistentSelection && splitSelection == item.splitSelection,
                        showsDisclosureIndicator: !usesPersistentSelection
                    )
                }
                .buttonStyle(.plain)
                .persistentSidebarSelection(
                    isSelected: splitSelection == item.splitSelection,
                    isEnabled: usesPersistentSelection
                )
            }
        } header: {
            Text("Shortcuts")
        }
    }

    // MARK: - Data

    private var displayedProfiles: [RemoteServerProfile] {
        viewModel.profiles.sorted {
            $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }

    private var totalSavedFolderCount: Int {
        viewModel.profiles.reduce(0) { $0 + viewModel.shortcutCount(for: $1) }
    }

    private var totalOfflineCopyCount: Int {
        viewModel.totalOfflineCopyCount
    }

    private var showsQuickAccess: Bool {
        !quickAccessItems.isEmpty
    }

    private var usesPersistentSelection: Bool {
        AppLayout.usesPersistentSplitSelection(
            isPad: UIDevice.current.userInterfaceIdiom == .pad
        )
    }

    @ViewBuilder
    private func serverActionMenuContent(for profile: RemoteServerProfile) -> some View {
        Button {
            requestEditorPresentation(viewModel.makeEditDraft(for: profile))
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }

        Divider()

        Button(role: .destructive) {
            pendingDeletionProfile = profile
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var quickAccessItems: [BrowseHomeShortcutItem] {
        var items = [BrowseHomeShortcutItem]()

        if totalSavedFolderCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "saved-folders",
                    title: String(localized: "Saved Folders"),
                    subtitle: totalSavedFolderCount == 1
                        ? String(localized: "1 saved")
                        : String(localized: "\(totalSavedFolderCount) saved"),
                    systemImage: "star.fill",
                    tint: .teal,
                    splitSelection: .savedFolders
                )
            )
        }

        if totalOfflineCopyCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "offline-shelf",
                    title: String(localized: "Offline Shelf"),
                    subtitle: totalOfflineCopyCount == 1
                        ? String(localized: "1 downloaded")
                        : String(localized: "\(totalOfflineCopyCount) downloaded"),
                    systemImage: "arrow.down.circle.fill",
                    tint: .green,
                    splitSelection: .offlineShelf
                )
            )
        }

        return items
    }

    @ToolbarContentBuilder
    private var addServerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: presentCreateServerSheet) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Remote Server")
        }
    }

    private func presentCreateServerSheet() {
        requestEditorPresentation(viewModel.makeCreateDraft())
    }

    private func requestEditorPresentation(_ draft: RemoteServerEditorDraft) {
        editorDraft = draft
    }

    private func persistSelection(_ selection: BrowseHomeSplitSelection?) {
        storedSelectionRawValue = selection?.storageValue ?? ""
    }

    private func restoreSelectionIfNeeded() {
        synchronizeSelection()
    }

    private func synchronizeSelection(preferStoredSelection: Bool = false) {
        let restoredSelection = BrowseHomeSplitSelection(storageValue: storedSelectionRawValue)
        let validSelections = Set(
            displayedProfiles.map { BrowseHomeSplitSelection.server($0.id) }
            + quickAccessItems.map(\.splitSelection)
        )

        if preferStoredSelection,
           let restoredSelection,
           validSelections.contains(restoredSelection) {
            splitSelection = restoredSelection
        } else if let splitSelection, validSelections.contains(splitSelection) {
            return
        } else if let restoredSelection, validSelections.contains(restoredSelection) {
            splitSelection = restoredSelection
        } else {
            splitSelection = nil
        }
    }

    private func performServerDeletion(_ profile: RemoteServerProfile) {
        pendingDeletionProfile = nil
        let deletedCurrentSelection = splitSelection == .server(profile.id)
        guard viewModel.delete(profile) else {
            return
        }

        guard deletedCurrentSelection else {
            synchronizeSelection()
            return
        }

        if let replacementProfile = displayedProfiles.first {
            open(.server(replacementProfile.id))
        } else if let replacementShortcut = quickAccessItems.first {
            open(replacementShortcut.splitSelection)
        } else {
            splitSelection = nil
            appNavigator?.navigate(.browse(.home))
        }
    }

    private func open(_ selection: BrowseHomeSplitSelection) {
        splitSelection = selection
        switch selection {
        case .server(let profileID):
            appNavigator?.navigate(.browse(.serverDetail(profileID)))
        case .savedFolders:
            appNavigator?.navigate(.browse(.savedFolders(nil)))
        case .offlineShelf:
            appNavigator?.navigate(.browse(.offlineShelf(nil)))
        }
    }
}

// MARK: - Navigation

enum BrowseHomeSplitSelection: Hashable {
    case server(UUID)
    case savedFolders
    case offlineShelf

    init?(storageValue: String) {
        guard let storedSelection = BrowseStoredNavigationSelection(storageValue: storageValue) else {
            return nil
        }

        switch storedSelection {
        case .serverDetail(let serverID), .serverBrowser(let serverID):
            self = .server(serverID)
        case .savedFolders:
            self = .savedFolders
        case .offlineShelf:
            self = .offlineShelf
        }
    }

    var storageValue: String {
        switch self {
        case .server(let serverID):
            return "server:\(serverID.uuidString)"
        case .savedFolders:
            return "saved-folders"
        case .offlineShelf:
            return "offline-shelf"
        }
    }
}

// MARK: - Supporting Types

private struct BrowseHomeShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let splitSelection: BrowseHomeSplitSelection
}

// MARK: - Server Row

private struct BrowseHomeServerRow: View {
    let profile: RemoteServerProfile
    var isSelected = false
    var showsDisclosureIndicator = true
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: protocolSystemImage,
                tint: profile.providerKind.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(profile.displayTitle)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xxs) {
                    Text(profile.endpointDisplaySummary)
                        .lineLimit(1)
                }
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var protocolSystemImage: String {
        switch profile.providerKind {
        case .smb:
            return "externaldrive.connected.to.line.below"
        case .webdav:
            return "globe"
        }
    }
}

// MARK: - Quick Access Row

private struct BrowseHomeQuickAccessRow: View {
    let item: BrowseHomeShortcutItem
    var isSelected = false
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(systemImage: item.systemImage, tint: item.tint)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)

                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BrowseHomeEmptyState: View {
    let showsGuidance: Bool
    let onAddServer: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "server.rack",
            title: String(localized: "No Servers"),
            description: showsGuidance
                ? String(localized: "Add a server to browse comics.")
                : nil,
            actionTitle: showsGuidance ? String(localized: "Add Server") : nil,
            action: showsGuidance ? onAddServer : nil
        )
    }
}

struct BrowseHomeDetailPlaceholder: View {
    let hasServers: Bool
    let onAddServer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                hasServers
                    ? String(localized: "Select a Server")
                    : String(localized: "Add a Server"),
                systemImage: "server.rack"
            )
        } description: {
            Text(
                hasServers
                    ? String(localized: "Choose a server or shortcut.")
                    : String(localized: "Add a server to browse comics.")
            )
        } actions: {
            if !hasServers {
                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceGrouped)
    }
}
