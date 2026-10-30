import SwiftUI
import UIKit

/// Remote home, built twice by the tab's split view: the iPhone list and the
/// sidebar beside the content.
struct BrowseHomeView: View {
    @Environment(\.appNavigator) private var appNavigator
    @Environment(SplitLayoutState.self) private var splitLayout: SplitLayoutState?
    @AppStorage(AppNavigationStorageKeys.browseHomeSelection) private var storedSelectionRawValue = ""
    @AppStorage(AppNavigationStorageKeys.pendingAddRemoteServer) private var pendingAddServer = false

    let dependencies: AppDependencies
    let isSidebar: Bool

    @ObservedObject private var viewModel: RemoteServerListViewModel
    @Binding private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var splitSelection: BrowseHomeSplitSelection?

    init(
        dependencies: AppDependencies,
        viewModel: RemoteServerListViewModel,
        editorDraft: Binding<RemoteServerEditorDraft?>,
        isSidebar: Bool = false
    ) {
        self.dependencies = dependencies
        self.isSidebar = isSidebar
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _editorDraft = editorDraft
    }

    var body: some View {
        content
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // An empty home has one action: the Add Server button in its empty state.
            if !showsEmptyState || usesPersistentSelection {
                addServerToolbarItem
            }
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
            presentPendingAddServerIfNeeded()
        }
        .onChange(of: pendingAddServer) { _, _ in
            presentPendingAddServerIfNeeded()
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
            if showsEmptyState {
                BrowseHomeEmptyState(
                    showsGuidance: !usesPersistentSelection,
                    onAddServer: presentCreateServerSheet
                )
            } else if usesPersistentSelection {
                // The sidebar lists servers, then the all-server pages.
                List {
                    serversSection
                    quickAccessSection
                }
                .adaptiveRootListStyle(usesSidebarStyle: true)
            } else {
                // Offline Shelf and Saved Folders first: they are what works offline.
                List {
                    entryCardsSection
                    serversSection
                }
                .adaptiveRootListStyle(usesSidebarStyle: false)
            }
        }
    }

    private var showsEmptyState: Bool {
        displayedProfiles.isEmpty && totalSavedFolderCount == 0 && totalOfflineCopyCount == 0
    }

    // MARK: - Entry Cards

    private var entryCardsSection: some View {
        Section {
            BrowseHomeEntryCards(items: quickAccessItems) { item in
                open(item.splitSelection)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
                    .tint(.appJam)

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

    private var usesPersistentSelection: Bool {
        isSidebar
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

    /// Offline Shelf and Saved Folders for all servers; shown even when empty
    /// so where they live is learned before they are needed.
    private var quickAccessItems: [BrowseHomeShortcutItem] {
        let offlineSubtitle: String = switch totalOfflineCopyCount {
        case 0: String(localized: "No offline copies yet")
        case 1: String(localized: "1 comic · Readable offline")
        default: String(localized: "\(totalOfflineCopyCount) comics · Readable offline")
        }
        let savedSubtitle: String = switch totalSavedFolderCount {
        case 0: String(localized: "No saved folders yet")
        case 1: String(localized: "1 shortcut")
        default: String(localized: "\(totalSavedFolderCount) shortcuts")
        }

        return [
            BrowseHomeShortcutItem(
                id: "offline-shelf",
                title: String(localized: "Offline Shelf"),
                subtitle: offlineSubtitle,
                systemImage: "arrow.down.circle.fill",
                tint: .appOffline,
                splitSelection: .offlineShelf
            ),
            BrowseHomeShortcutItem(
                id: "saved-folders",
                title: String(localized: "Saved Folders"),
                subtitle: savedSubtitle,
                systemImage: "pin.fill",
                tint: .appAccent,
                splitSelection: .savedFolders
            )
        ]
    }

    @ToolbarContentBuilder
    private var addServerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: presentCreateServerSheet) {
                Label("Add Server", systemImage: "plus")
            }
        }
    }

    private func presentCreateServerSheet() {
        requestEditorPresentation(viewModel.makeCreateDraft())
    }

    private func presentPendingAddServerIfNeeded() {
        // Both home instances see the flag; only the one on screen opens the sheet.
        guard pendingAddServer,
              splitLayout.map({ $0.isSidebarVisible == isSidebar }) ?? true else {
            return
        }
        pendingAddServer = false
        presentCreateServerSheet()
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Large text moves the protocol tag under the address so the name keeps the width.
        let isLarge = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: profile.providerKind.systemImage,
                tint: profile.providerKind.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(profile.displayTitle)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(isLarge ? 3 : 1)

                Text(profile.addressSummary)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(isLarge ? 2 : 1)

                if isLarge {
                    RemoteProtocolTag(kind: profile.providerKind)
                }
            }

            Spacer(minLength: Spacing.xs)

            if !isLarge {
                RemoteProtocolTag(kind: profile.providerKind)
            }

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
}

// MARK: - Entry Cards

/// Two cards on top of the iPhone remote home (`ScreenRemoteHome`).
private struct BrowseHomeEntryCards: View {
    let items: [BrowseHomeShortcutItem]
    let onOpen: (BrowseHomeShortcutItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.sm))
        layout {
            ForEach(items) { item in
                Button {
                    onOpen(item)
                } label: {
                    card(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(_ item: BrowseHomeShortcutItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: item.systemImage)
                .font(AppFont.subheadline(.semibold))
                .foregroundStyle(item.tint)
                .frame(width: 32, height: 32)
                .background(item.tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceGroupedSecondary, in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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
            title: String(localized: "Connect Your NAS"),
            description: showsGuidance
                ? String(localized: "Add an SMB or WebDAV server to read online or save comics to this device.")
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
                .tint(.appJam)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceGrouped)
    }
}
