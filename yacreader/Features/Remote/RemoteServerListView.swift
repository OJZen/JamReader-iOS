import Combine
import SwiftUI

struct RemoteServerListView: View {
    private enum LayoutMetrics {
        static let horizontalInset: CGFloat = 12
        static let rowAccessoryReservedWidth: CGFloat = 36
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var navigationRequest: RemoteServerListNavigationRequest?

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
                        "No Remote Servers",
                        systemImage: "server.rack",
                        description: Text("Add a remote server to manage browsing access for comics stored on your network.")
                    )
                    .padding(.vertical, 24)
                }
            } else {
                Section("Configured Servers") {
                    ForEach(viewModel.profiles) { profile in
                        Button {
                            navigationRequest = .detail(profile)
                        } label: {
                            RemoteServerRow(
                                profile: profile,
                                recentHistoryCount: viewModel.recentSessions(for: profile).count,
                                savedFolderCount: viewModel.shortcutCount(for: profile),
                                offlineCopyCount: viewModel.cacheSummary(for: profile).fileCount,
                                trailingAccessoryReservedWidth: persistentRowActionReservedWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                        .overlay(alignment: .trailing) {
                            if showsPersistentRowActions {
                                persistentActionMenu(for: profile)
                                    .padding(.trailing, 8)
                            }
                        }
                        .contextMenu {
                            remoteServerActionMenuContent(for: profile)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            remoteServerSwipeActions(for: profile)
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
                .accessibilityLabel("Add Server")
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            viewModel.load()
        }
        .refreshable {
            viewModel.load()
        }
        .sheet(isPresented: serverEditorPresented) {
            if let draft = editorDraft {
                remoteServerEditor(for: draft)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .navigationDestination(item: $navigationRequest) { request in
            switch request {
            case .detail(let profile):
                RemoteServerDetailView(
                    profile: profile,
                    dependencies: dependencies
                )
            case .savedFolders(let profile):
                SavedRemoteFoldersView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            case .offlineShelf(let profile):
                RemoteOfflineShelfView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            }
        }
    }

    private var showsPersistentRowActions: Bool {
        horizontalSizeClass == .regular
    }

    private var persistentRowActionReservedWidth: CGFloat {
        showsPersistentRowActions ? LayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var summarySection: some View {
        Section {
            InsetCard(
                cornerRadius: 18,
                contentPadding: 14,
                backgroundColor: Color(.systemBackground),
                strokeOpacity: 0.04
            ) {
                SummaryMetricGroup(
                    metrics: summaryMetrics,
                    style: .compactValue,
                    horizontalSpacing: 8,
                    verticalSpacing: 8
                )

                Label(
                    "Edit connection settings, review authentication, and clear server-specific history or downloaded cache when paths change.",
                    systemImage: "slider.horizontal.3"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
            .insetCardListRow(
                horizontalInset: LayoutMetrics.horizontalInset,
                top: 14,
                bottom: 10
            )
        }
    }

    private var serverEditorPresented: Binding<Bool> {
        Binding(
            get: { editorDraft != nil },
            set: { if !$0 { editorDraft = nil } }
        )
    }

    private func remoteServerEditor(
        for draft: RemoteServerEditorDraft
    ) -> some View {
        RemoteServerEditorSheet(draft: draft) { updatedDraft in
            let alertState = viewModel.save(draft: updatedDraft)
            if alertState == nil {
                editorDraft = nil
            }
            return alertState
        }
        .id(draft.id)
    }

    private var totalOfflineCopyCount: Int {
        viewModel.profiles.reduce(0) { partialResult, profile in
            partialResult + viewModel.cacheSummary(for: profile).fileCount
        }
    }

    private var summaryMetrics: [SummaryMetricItem] {
        [
            SummaryMetricItem(
                title: "Servers",
                value: viewModel.serverCountText,
                tint: .blue
            ),
            SummaryMetricItem(
                title: "Saved",
                value: viewModel.shortcutCountText,
                tint: .teal
            ),
            SummaryMetricItem(
                title: "Cached",
                value: "\(totalOfflineCopyCount)",
                tint: .green
            )
        ]
    }

    @ViewBuilder
    private func remoteServerActionMenuContent(
        for profile: RemoteServerProfile
    ) -> some View {
        let savedFolderCount = viewModel.shortcutCount(for: profile)
        let offlineCopyCount = viewModel.cacheSummary(for: profile).fileCount
        let recentHistoryCount = viewModel.recentSessions(for: profile).count
        let cacheSummary = viewModel.cacheSummary(for: profile)

        Button {
            editorDraft = viewModel.makeEditDraft(for: profile)
        } label: {
            Label("Edit Server", systemImage: "square.and.pencil")
        }

        if savedFolderCount > 0 {
            Button {
                navigationRequest = .savedFolders(profile)
            } label: {
                Label(
                    savedFolderCount == 1 ? "Open Saved Folder" : "Open Saved Folders",
                    systemImage: "star"
                )
            }
        }

        if offlineCopyCount > 0 {
            Button {
                navigationRequest = .offlineShelf(profile)
            } label: {
                Label(
                    offlineCopyCount == 1 ? "Open Offline Copy" : "Open Offline Shelf",
                    systemImage: "arrow.down.circle"
                )
            }
        }

        if recentHistoryCount > 0 {
            Button(role: .destructive) {
                viewModel.clearRecentHistory(for: profile)
            } label: {
                Label("Clear Browsing History", systemImage: "clock.arrow.circlepath")
            }
        }

        if !cacheSummary.isEmpty {
            Button(role: .destructive) {
                viewModel.clearCache(for: profile)
            } label: {
                Label("Clear Download Cache", systemImage: "trash")
            }
        }

        Button(role: .destructive) {
            viewModel.delete(profile)
        } label: {
            Label("Delete Server", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func remoteServerSwipeActions(
        for profile: RemoteServerProfile
    ) -> some View {
        Button {
            editorDraft = viewModel.makeEditDraft(for: profile)
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        .tint(.blue)

        Button(role: .destructive) {
            viewModel.delete(profile)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func persistentActionMenu(for profile: RemoteServerProfile) -> some View {
        Menu {
            remoteServerActionMenuContent(for: profile)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(profile.displayTitle)")
    }
}

struct RemoteServerRow: View {
    let profile: RemoteServerProfile
    let recentHistoryCount: Int
    let savedFolderCount: Int
    let offlineCopyCount: Int
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        InsetListRowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    RemoteServerGlyph(profile: profile, size: 42, cornerRadius: 12, iconFont: .title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(profile.providerDisplayTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(profile.providerKind.tintColor)
                            .lineLimit(1)
                    }
                }

                RemoteInlineMetadataLine(
                    items: connectionMetadataItems,
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                )

                if !managementMetadataItems.isEmpty {
                    RemoteInlineMetadataLine(
                        items: managementMetadataItems,
                        horizontalSpacing: 8,
                        verticalSpacing: 4
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.trailing, trailingAccessoryReservedWidth)
        }
    }

    private var connectionMetadataItems: [RemoteInlineMetadataItem] {
        var items = [
            RemoteInlineMetadataItem(
                systemImage: "folder.fill",
                text: profile.endpointDisplaySummary,
                tint: .blue
            ),
            RemoteInlineMetadataItem(
                systemImage: "point.3.connected.trianglepath.dotted",
                text: profile.shareDisplaySummary,
                tint: .teal
            )
        ]

        if !profile.username.isEmpty, profile.authenticationMode.requiresUsername {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "person.text.rectangle",
                    text: profile.username,
                    tint: .secondary
                )
            )
        }

        return items
    }

    private var managementMetadataItems: [RemoteInlineMetadataItem] {
        var items = [RemoteInlineMetadataItem]()

        if savedFolderCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "star",
                    text: "\(savedFolderCount) saved",
                    tint: .teal
                )
            )
        }

        if offlineCopyCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "arrow.down.circle",
                    text: "\(offlineCopyCount) cached",
                    tint: .green
                )
            )
        }

        if recentHistoryCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "clock.arrow.circlepath",
                    text: "\(recentHistoryCount) recent",
                    tint: .orange
                )
            )
        }

        return items
    }
}

struct RemoteServerGlyph: View {
    let profile: RemoteServerProfile
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 16
    var iconFont: Font = .title2

    private var authenticationTint: Color {
        profile.authenticationMode == .guest ? .orange : .green
    }

    private var authenticationSystemImage: String {
        profile.authenticationMode == .guest ? "person.fill" : "lock.fill"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        profile.providerKind.tintColor.opacity(0.22),
                        profile.providerKind.tintColor.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: profile.providerKind.systemImage)
                    .font(iconFont.weight(.semibold))
                    .foregroundStyle(profile.providerKind.tintColor)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: authenticationSystemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(authenticationTint, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color(.secondarySystemBackground), lineWidth: 2)
                    }
                    .offset(x: size >= 50 ? 6 : 4, y: size >= 50 ? 6 : 4)
            }
    }
}

private struct RemoteServerInfoLine: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary
    var lineLimit = 1

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}

extension RemoteServerProfile {
    var endpointDisplaySummary: String {
        endpointDisplayHost
    }

    var shareDisplaySummary: String {
        providerRootDisplayPath
    }
}


private enum RemoteServerListNavigationRequest: Identifiable, Hashable {
    case detail(RemoteServerProfile)
    case savedFolders(RemoteServerProfile)
    case offlineShelf(RemoteServerProfile)

    var id: String {
        switch self {
        case .detail(let profile):
            return "detail:\(profile.id.uuidString)"
        case .savedFolders(let profile):
            return "saved:\(profile.id.uuidString)"
        case .offlineShelf(let profile):
            return "offline:\(profile.id.uuidString)"
        }
    }
}
