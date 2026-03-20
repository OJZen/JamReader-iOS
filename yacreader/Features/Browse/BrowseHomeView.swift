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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.summaryTitle)
                        .font(.largeTitle.bold())

                    Text(viewModel.summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 8) {
                StatusBadge(title: "SMB", tint: .blue)
                StatusBadge(title: "Direct Read", tint: .green)
                StatusBadge(title: "Import", tint: .orange)
            }

            HStack(spacing: 12) {
                MetricPill(title: "Servers", value: viewModel.serverCountText, tint: .blue)
                MetricPill(title: "Folders", value: viewModel.shortcutCountText, tint: .teal)
                MetricPill(title: "Recent", value: viewModel.sessionCountText, tint: .green)
                MetricPill(title: "Offline", value: viewModel.offlineReadyCountText, tint: .orange)
            }
            .frame(maxWidth: .infinity)

            Label(viewModel.cacheSummaryText, systemImage: "arrow.down.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Label(viewModel.thumbnailCacheSummaryText, systemImage: "photo.stack.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var browseToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Browse Tools", subtitle: "Keep SMB connection setup here, and let reading and folder destinations stay in their own stable sections below.")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                NavigationLink {
                    RemoteServerListView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Manage Servers",
                        subtitle: "Add, edit, or clean up saved SMB connections.",
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
                sectionHeader("Continue Reading", subtitle: "Pick up the last remote comic without re-browsing the folder tree.")

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
            sectionHeaderLink(
                title: "Offline Ready",
                subtitle: "Open downloaded remote comics immediately, even before the SMB server responds.",
                destinationLabel: sessions.isEmpty ? "Open Shelf" : "See All"
            ) {
                RemoteOfflineShelfView(dependencies: dependencies)
            }

            if sessions.isEmpty {
                NavigationLink {
                    RemoteOfflineShelfView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Offline Shelf",
                        subtitle: viewModel.offlineReadySessions.isEmpty
                            ? "No downloaded remote comics yet. Open the shelf to manage offline copies as they appear."
                            : "\(viewModel.offlineReadySessions.count) downloaded remote comics are ready offline.",
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
            sectionHeaderLink(
                title: "Saved Folders",
                subtitle: "Pinned SMB directories stay on the home surface, while rename and cleanup live in the dedicated Saved Folders page.",
                destinationLabel: shortcutEntries.isEmpty ? "Open" : "See All"
            ) {
                SavedRemoteFoldersView(dependencies: dependencies)
            }

            if shortcutEntries.isEmpty {
                NavigationLink {
                    SavedRemoteFoldersView(dependencies: dependencies)
                } label: {
                    ActionCard(
                        title: "Saved Folders",
                        subtitle: "Pin frequently used SMB directories from the remote browser to keep them one tap away here.",
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
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionHeaderLink<Destination: View>(
        title: String,
        subtitle: String,
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
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.7),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var heroBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.28, blue: 0.58),
                Color(red: 0.11, green: 0.53, blue: 0.60),
                Color(red: 0.15, green: 0.68, blue: 0.49)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct ContinueReadingCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text("Last opened \(session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
