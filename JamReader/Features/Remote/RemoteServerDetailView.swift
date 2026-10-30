import SwiftUI
import UIKit

struct RemoteServerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies
    private let sourceProfile: RemoteServerProfile
    // Called instead of local sheet when parent owns the editor (split-view mode).
    var onRequestEdit: ((RemoteServerEditorDraft) -> Void)?

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var profile: RemoteServerProfile
    @State private var recentSessions: [RemoteComicReadingSession] = []
    @State private var offlineCopyReferences: [String: RemoteComicFileReference] = [:]
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?
    @State private var pendingDestructiveAction: RemoteServerDestructiveAction?

    init(
        profile: RemoteServerProfile,
        dependencies: AppDependencies,
        onRequestEdit: ((RemoteServerEditorDraft) -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.sourceProfile = profile
        self.onRequestEdit = onRequestEdit
        _profile = State(initialValue: profile)
        _viewModel = StateObject(
            wrappedValue: RemoteServerListViewModel(
                profileStore: dependencies.remoteServerProfileStore,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore,
                remoteOfflineCopyStore: dependencies.remoteOfflineCopyStore,
                remoteOfflineLibrarySnapshotStore: dependencies.remoteOfflineLibrarySnapshotStore,
                remoteBackgroundImportController: dependencies.remoteBackgroundImportController
            )
        )
    }

    var body: some View {
        content
        .navigationTitle(profile.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            PageOverflowMenu("Server Actions") {
                remoteServerActionMenuContent
            }
        }
        .task {
            viewModel.loadIfNeeded()
            refreshDetailState()
        }
        .onAppear {
            refreshDetailState(forceReload: true)
        }
        .onChange(of: sourceProfile) { _, updated in
            // When the parent (split-view sidebar) passes an updated profile
            // after a save, sync state and reload so the detail stays current.
            profile = updated
            refreshDetailState()
        }
        .refreshable {
            refreshDetailState(forceReload: true)
        }
        .confirmationDialog(
            pendingDestructiveAction?.title ?? String(localized: "Confirm Action"),
            isPresented: pendingDestructiveActionBinding,
            titleVisibility: .visible
        ) {
            if let pendingDestructiveAction {
                Button(pendingDestructiveAction.buttonTitle, role: .destructive) {
                    performDestructiveAction(pendingDestructiveAction)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDestructiveAction = nil
            }
        } message: {
            if let pendingDestructiveAction {
                Text(pendingDestructiveAction.message)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .background(readerPresenter)
    }

    /// `ScreenRemoteServer`: header with one Browse Files button, this
    /// server's reading history, then its saved folders and offline shelf.
    @ViewBuilder
    private var content: some View {
        List {
            headerSection

            if !recentSessions.isEmpty {
                continueReadingSection
            }

            thisServerSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var readerPresenter: some View {
        EmptyView()
    }

    private func remoteServerEditor(
        for draft: RemoteServerEditorDraft
    ) -> some View {
        RemoteServerEditorSheet(
            draft: draft,
            appliesSwiftUIPresentationModifiers: false
        ) { updatedDraft in
            let alertState = viewModel.save(draft: updatedDraft)
            if alertState == nil {
                appPresenter?.dismissSheet()
                refreshDetailState(forceReload: true)
            }
            return alertState
        }
        .id(draft.id)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Large text stacks the icon, name and address so whole words fit.
                let isLarge = dynamicTypeSize.isAccessibilitySize
                let headerLayout = isLarge
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: Spacing.sm))
                headerLayout {
                    ListIconBadge(
                        systemImage: profile.providerKind.systemImage,
                        tint: profile.providerKind.tintColor,
                        size: 52
                    )
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(profile.displayTitle)
                            .font(AppFont.title2(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        let addressLayout = isLarge
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
                            : AnyLayout(HStackLayout(spacing: Spacing.xs))
                        addressLayout {
                            RemoteProtocolTag(kind: profile.providerKind)
                            Text(profile.addressSummary)
                                .font(AppFont.subheadline())
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(isLarge ? 3 : 1)
                                .textSelection(.enabled)
                        }
                    }
                }

                VStack(spacing: Spacing.xs) {
                    Button {
                        navigate(.serverBrowser(profile.id, path: browserEntryRawPath))
                    } label: {
                        Label("Browse Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.appJam)

                    Text(browserEntryCaption)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: Spacing.xs, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    /// This server's reading history as a shelf (`ContinueReading`); long
    /// press removes one entry.
    private var continueReadingSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(recentSessions) { session in
                        HeroTapButton { frame in
                            prepareHeroTransition(for: session, fallbackFrame: frame)
                            presentRecentSession(session)
                        } label: {
                            RemoteContinueReadingShelfCard(
                                session: session,
                                profile: profile,
                                availability: offlineAvailability(for: session),
                                browsingService: dependencies.remoteServerBrowsingService,
                                width: shelfCoverWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            recentSessionActionMenuContent(for: session)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: Spacing.xxs, leading: 0, bottom: Spacing.sm, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            sectionTitle("Continue Reading")
        }
    }

    /// Both sections use the same title style, as in components/ScreenRemoteServer.
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.title2(.bold))
            .foregroundStyle(Color.textPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private var thisServerSection: some View {
        Section {
            Button {
                navigate(.savedFolders(profile.id))
            } label: {
                RemoteServerDetailShortcutRow(
                    title: String(localized: "Saved Folders"),
                    systemImage: "pin.fill",
                    tint: .appAccent,
                    countText: savedFolderCount > 0 ? "\(savedFolderCount)" : nil
                )
            }
            .buttonStyle(.plain)

            Button {
                navigate(.offlineShelf(profile.id))
            } label: {
                RemoteServerDetailShortcutRow(
                    title: String(localized: "Offline Shelf"),
                    systemImage: "arrow.down.circle.fill",
                    tint: .appOffline,
                    countText: offlineCopyCount > 0
                        ? (offlineCopyCount == 1
                            ? String(localized: "1 comic")
                            : String(localized: "\(offlineCopyCount) comics"))
                        : nil
                )
            }
            .buttonStyle(.plain)
        } header: {
            sectionTitle("This Server")
        }
    }

    private var shelfCoverWidth: CGFloat {
        horizontalSizeClass == .regular ? AppLayout.shelfCoverWidthRegular : AppLayout.shelfCoverWidthCompact
    }

    @MainActor
    private func prepareHeroTransition(for session: RemoteComicReadingSession, fallbackFrame: CGRect) {
        let item = session.directoryItem
        let registeredFrame = HeroSourceRegistry.shared.frame(for: item.id)
        heroSourceFrame = registeredFrame == .zero ? fallbackFrame : registeredFrame
        heroPreviewImage = RemoteComicThumbnailPipeline.shared.cachedTransitionImage(
            for: item,
            browsingService: dependencies.remoteServerBrowsingService
        )
    }

    private func presentRecentSession(_ session: RemoteComicReadingSession) {
        appPresenter?.presentReader(
            .remote(
                RemoteReaderPresentation(
                    profile: profile,
                    item: session.directoryItem,
                    openMode: .automatic,
                    referenceOverride: session.resolvedComicFileReference(for: profile),
                    sourceFrame: heroSourceFrame,
                    previewImage: heroPreviewImage,
                    onDismiss: {
                        heroSourceFrame = .zero
                        heroPreviewImage = nil
                        refreshDetailState(refreshRecentActivity: true)
                    }
                )
            )
        )
    }

    private var savedFolderCount: Int {
        viewModel.shortcutCount(for: profile)
    }

    private var offlineCopyCount: Int {
        viewModel.offlineCopyCount(for: profile)
    }

    private var browserEntryRawPath: String {
        RemoteServerBrowserViewModel.lastBrowsedPath(for: profile)
    }

    private var browserEntryIsRoot: Bool {
        browserEntryRawPath == profile.normalizedBaseDirectoryPath
    }

    private var browserEntryCaption: String {
        browserEntryIsRoot
            ? String(localized: "Opens at the start folder")
            : String(localized: "Opens where you left off: \(browserEntryRawPath)")
    }

    /// Server management; the This Server rows are not repeated here.
    @ViewBuilder
    private var remoteServerActionMenuContent: some View {
        Button {
            let draft = viewModel.makeEditDraft(for: profile)
            if let onRequestEdit {
                onRequestEdit(draft)
            } else {
                presentEditor(for: draft)
            }
        } label: {
            Label("Edit Server", systemImage: "square.and.pencil")
        }

        Section {
            Button {
                pendingDestructiveAction = .clearHistory(profile, count: recentSessions.count)
            } label: {
                Text("Clear Reading History")
                Text("Offline copies stay")
                Image(systemName: "clock.arrow.circlepath")
            }
            .disabled(recentSessions.isEmpty)

            Button {
                pendingDestructiveAction = .clearDownloads(
                    profile,
                    count: viewModel.cacheSummary(for: profile).fileCount
                )
            } label: {
                Text("Clear Downloads on This Device")
                Text("History and progress stay")
                Image(systemName: "trash")
            }
            .disabled(!viewModel.cacheSummary(for: profile).hasCachedComics)
        }

        Section {
            Button(role: .destructive) {
                pendingDestructiveAction = .deleteServer(profile)
            } label: {
                Text("Delete Server")
                Text("Files on the server stay")
                Image(systemName: "trash")
            }
        }
    }

    @ViewBuilder
    private func recentSessionActionMenuContent(
        for session: RemoteComicReadingSession
    ) -> some View {
        Button {
            presentInfo(for: session)
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        Button(role: .destructive) {
            deleteRecentSession(session)
        } label: {
            Label("Delete History Entry", systemImage: "trash")
        }
    }

    private func deleteRecentSession(_ session: RemoteComicReadingSession) {
        viewModel.deleteRecentSession(session)
        refreshDetailState(forceReload: true)
    }

    private var pendingDestructiveActionBinding: Binding<Bool> {
        Binding(
            get: { pendingDestructiveAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestructiveAction = nil
                }
            }
        )
    }

    private func performDestructiveAction(_ action: RemoteServerDestructiveAction) {
        pendingDestructiveAction = nil
        AppHaptics.warning()

        switch action {
        case .clearHistory(let profile, _):
            viewModel.clearRecentHistory(for: profile)
            refreshDetailState(forceReload: true)
        case .clearDownloads(let profile, _):
            viewModel.clearCache(for: profile)
            refreshDetailState(forceReload: true)
        case .clearTemporaryCache(let profile):
            viewModel.clearOtherCache(for: profile)
            refreshDetailState(forceReload: true)
        case .deleteServer(let profile):
            if viewModel.delete(profile) {
                dismiss()
            }
        }
    }

    private func presentInfo(for session: RemoteComicReadingSession) {
        appPresenter?.presentSheet(
            .content(
                id: "remote.recent.info.\(session.id)",
                content: AnyView(recentSessionInfoSheet(for: session))
            )
        )
    }

    private func recentSessionInfoSheet(
        for session: RemoteComicReadingSession
    ) -> some View {
        RemoteComicInfoSheet(
            profile: profile,
            item: session.directoryItem,
            readingSession: session,
            cacheAvailability: offlineAvailability(for: session),
            browsingService: dependencies.remoteServerBrowsingService
        )
    }

    private func refreshDetailState(
        forceReload: Bool = false,
        refreshRecentActivity: Bool = false
    ) {
        if forceReload {
            viewModel.load()
        } else if refreshRecentActivity {
            viewModel.refreshRecentActivity()
        }

        if let updatedProfile = viewModel.profile(withID: profile.id) {
            profile = updatedProfile
        }

        recentSessions = viewModel.recentSessions(for: profile)
        offlineCopyReferences = (try? dependencies.remoteOfflineCopyStore.offlineCopyReferences(for: profile)) ?? [:]
    }

    /// A reading cache is not an offline copy, so it shows no offline status.
    private func offlineAvailability(for session: RemoteComicReadingSession) -> RemoteComicCachedAvailability {
        let key = RemoteOfflineCopyStore.contentKey(for: session.resolvedComicFileReference(for: profile))
        guard let copyReference = offlineCopyReferences[key] else {
            return .unavailable
        }
        return dependencies.remoteServerBrowsingService.cachedAvailability(for: copyReference)
    }

    private func presentEditor(for draft: RemoteServerEditorDraft) {
        appPresenter?.presentSheet(
            .content(
                id: draft.id,
                content: AnyView(remoteServerEditor(for: draft))
            )
        )
    }

    private func navigate(_ route: BrowseNavigationRoute) {
        appNavigator?.navigate(.browse(route))
    }
}

private struct RemoteServerDetailShortcutRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let countText: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(AppFont.body())
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.body())
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: Spacing.xs)

            if let countText {
                Text(countText)
                    .font(AppFont.body().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            Image(systemName: "chevron.forward")
                .font(AppFont.caption2(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
    }
}

/// Shelf card for a remote history entry: cover with progress and copy
/// status, title, "Read to 55% · Offline".
private struct RemoteContinueReadingShelfCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability
    let browsingService: RemoteServerBrowsingService
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            RemoteComicThumbnailView(
                profile: profile,
                item: session.directoryItem,
                browsingService: browsingService,
                prefersLocalCache: availability.hasLocalCopy,
                heroSourceID: session.directoryItem.id,
                width: width,
                height: width / AppLayout.coverAspectRatio
            )
            .overlay(alignment: .bottom) {
                if let fraction = session.readingProgressFraction, !session.read {
                    LibraryCoverProgressBar(fraction: fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))

            Text(session.displayName)
                .font(AppFont.footnote(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(statusLine)
                .font(AppFont.caption())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        var parts: [String] = []
        if session.read {
            parts.append(String(localized: "Read"))
        } else if let fraction = session.readingProgressFraction {
            let percent = Int((fraction * 100).rounded())
            parts.append(String(localized: "Read to \(percent)%"))
        }
        if let status = availability.statusBadgeStatus {
            parts.append(status.title)
        }
        return parts.joined(separator: " · ")
    }
}
