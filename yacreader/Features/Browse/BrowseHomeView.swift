import SwiftUI

struct BrowseHomeView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: BrowseHomeViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: BrowseHomeViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    heroSection
                    continueReadingSection
                    browseToolsSection
                    offlineReadySection
                    savedFoldersSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(background)
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadIfNeeded()
            }
            .onAppear {
                Task {
                    await viewModel.refreshIfLoaded()
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var heroSection: some View {
        InsetCard(cornerRadius: 28, contentPadding: 18, strokeOpacity: 0.04) {
            HStack(alignment: .top, spacing: 14) {
                Text(viewModel.summaryTitle)
                    .font(.title2.weight(.semibold))

                Spacer(minLength: 8)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 52, height: 52)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            AdaptiveStatusBadgeGroup(
                badges: [
                    StatusBadgeItem(title: "SMB", tint: .blue),
                    StatusBadgeItem(title: "Direct Read", tint: .green),
                    StatusBadgeItem(title: "Import", tint: .orange)
                ]
            )

            SummaryMetricGroup(
                metrics: [
                    SummaryMetricItem(title: "Servers", value: viewModel.serverCountText, tint: .blue),
                    SummaryMetricItem(title: "Folders", value: viewModel.shortcutCountText, tint: .teal),
                    SummaryMetricItem(title: "Recent", value: viewModel.sessionCountText, tint: .green),
                    SummaryMetricItem(title: "Offline", value: viewModel.offlineReadyCountText, tint: .orange)
                ]
            )

            FormOverviewContent(items: browseOverviewItems)
        }
    }

    private var browseOverviewItems: [FormOverviewItem] {
        [
            FormOverviewItem(title: "Downloads", value: viewModel.cacheSummaryText),
            FormOverviewItem(title: "Thumbnails", value: viewModel.thumbnailCacheSummaryText)
        ]
    }

    private var browseToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Browse Tools")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                NavigationLink {
                    RemoteServerListView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Manage Servers",
                        badges: manageServersBadges,
                        systemImage: "server.rack",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var continueReadingSection: some View {
        if let profile = viewModel.continueReadingProfile,
           let session = viewModel.continueReadingSession {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Continue Reading")

                NavigationLink {
                    RemoteComicLoadingView(
                        profile: profile,
                        item: session.directoryItem,
                        dependencies: dependencies
                    )
                } label: {
                    ContinueReadingCard(
                        session: session,
                        profile: profile
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var offlineReadySection: some View {
        let sessions = viewModel.offlineShelfPreviewSessions

        VStack(alignment: .leading, spacing: 12) {
            if sessions.isEmpty {
                sectionHeader("Offline Ready")
            } else {
                sectionHeaderLink(
                    title: "Offline Ready",
                    destinationLabel: "See All"
                ) {
                    RemoteOfflineShelfView(dependencies: dependencies)
                }
            }

            if sessions.isEmpty {
                NavigationLink {
                    RemoteOfflineShelfView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Offline Shelf",
                        badges: offlineShelfActionBadges,
                        systemImage: "arrow.down.circle.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(sessions.prefix(3))) { session in
                        if let profile = viewModel.profile(for: session.serverID) {
                            NavigationLink {
                                RemoteComicLoadingView(
                                    profile: profile,
                                    item: session.directoryItem,
                                    dependencies: dependencies,
                                    openMode: .preferLocalCache
                                )
                            } label: {
                                RemoteOfflineComicCard(
                                    session: session,
                                    profile: profile,
                                    availability: dependencies.remoteServerBrowsingService.cachedAvailability(
                                        for: session.comicFileReference
                                    ),
                                    showsNavigationIndicator: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var savedFoldersSection: some View {
        let shortcutEntries = viewModel.shortcutEntries

        VStack(alignment: .leading, spacing: 12) {
            if shortcutEntries.isEmpty {
                sectionHeader("Saved Folders")
            } else {
                sectionHeaderLink(
                    title: "Saved Folders",
                    destinationLabel: "See All"
                ) {
                    SavedRemoteFoldersView(dependencies: dependencies)
                }
            }

            if shortcutEntries.isEmpty {
                NavigationLink {
                    SavedRemoteFoldersView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Saved Folders",
                        badges: savedFoldersActionBadges,
                        systemImage: "star.fill",
                        tint: .teal
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(shortcutEntries.prefix(3))) { entry in
                        NavigationLink {
                            RemoteServerBrowserView(
                                profile: entry.profile,
                                currentPath: entry.shortcut.path,
                                dependencies: dependencies
                            )
                        } label: {
                            RemoteSavedFolderCard(
                                shortcut: entry.shortcut,
                                profile: entry.profile
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sectionHeaderLink<Destination: View>(
        title: String,
        subtitle: String? = nil,
        destinationLabel: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        HStack(alignment: .top) {
            sectionHeader(title, subtitle: subtitle)

            Spacer(minLength: 12)

            NavigationLink {
                destination()
            } label: {
                Text(destinationLabel)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var background: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }

    private var manageServersBadges: [StatusBadgeItem] {
        let title = viewModel.profiles.isEmpty
            ? "No Servers"
            : "\(viewModel.profiles.count) servers"
        return [StatusBadgeItem(title: title, tint: .blue)]
    }

    private var offlineShelfActionBadges: [StatusBadgeItem] {
        if viewModel.offlineReadySessions.isEmpty {
            return [StatusBadgeItem(title: "Empty", tint: .gray)]
        }

        let count = viewModel.offlineReadySessions.count
        return [
            StatusBadgeItem(
                title: count == 1 ? "1 comic" : "\(count) comics",
                tint: .green
            )
        ]
    }

    private var savedFoldersActionBadges: [StatusBadgeItem] {
        if viewModel.profiles.isEmpty {
            return [StatusBadgeItem(title: "No Servers", tint: .gray)]
        }

        let title = viewModel.profiles.count == 1
            ? "1 server"
            : "\(viewModel.profiles.count) servers"
        return [StatusBadgeItem(title: title, tint: .teal)]
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String?
    let badges: [StatusBadgeItem]
    let systemImage: String
    let tint: Color

    init(
        title: String,
        subtitle: String? = nil,
        badges: [StatusBadgeItem] = [],
        systemImage: String,
        tint: Color
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        InsetCard(contentPadding: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                AdaptiveStatusBadgeGroup(
                    badges: badges,
                    horizontalSpacing: 6,
                    verticalSpacing: 6
                )
            }

            Spacer(minLength: 0)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil && badges.isEmpty ? 108 : 132,
            alignment: .leading
        )
    }
}

private struct ContinueReadingCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile

    var body: some View {
        InsetCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)

                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                StatusBadge(title: session.progressText, tint: session.read ? .green : .orange)
                StatusBadge(title: profile.providerKind.title, tint: profile.providerKind.tintColor)
            }

            LabeledContent(
                "Opened",
                value: session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened)
            )
            .font(.caption)
        }
    }
}
