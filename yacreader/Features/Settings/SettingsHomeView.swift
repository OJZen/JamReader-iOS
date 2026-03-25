import SwiftUI

struct SettingsHomeView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var comicLayout = ReaderDisplayLayout(defaultsFor: .comic)
    @State private var mangaLayout = ReaderDisplayLayout(defaultsFor: .manga)
    @State private var webcomicLayout = ReaderDisplayLayout(defaultsFor: .webComic)
    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .balanced
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var isShowingClearDownloadsConfirmation = false
    @State private var isShowingClearThumbnailsConfirmation = false
    @State private var alert: SettingsAlertState?

    var body: some View {
        NavigationStack {
            List {
                readingSection
                remoteSection
                storageSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .task { refresh() }
            .refreshable { refresh() }
            .confirmationDialog(
                "Clear downloaded remote comics?",
                isPresented: $isShowingClearDownloadsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Downloads", role: .destructive) {
                    clearRemoteDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Downloaded copies, browsing history, and remembered folder positions will be removed. Saved remote servers stay intact.")
            }
            .confirmationDialog(
                "Clear cached remote thumbnails?",
                isPresented: $isShowingClearThumbnailsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Thumbnails", role: .destructive) {
                    clearRemoteThumbnails()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only generated remote cover thumbnails are removed. Downloads and reading progress stay intact.")
            }
            .alert(item: $alert) { alertState in
                Alert(
                    title: Text(alertState.title),
                    message: Text(alertState.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Reading

    private var readingSection: some View {
        Section {
            readerRow(
                icon: "book.fill",
                iconColor: .blue,
                title: "Comics",
                layout: comicLayout
            )
            readerRow(
                icon: "book.closed.fill",
                iconColor: .purple,
                title: "Manga",
                layout: mangaLayout
            )
            readerRow(
                icon: "scroll.fill",
                iconColor: .green,
                title: "Webcomics",
                layout: webcomicLayout
            )
        } header: {
            Text("Reading")
        } footer: {
            Text("Default reader layout applied when opening each content type.")
        }
    }

    private func readerRow(
        icon: String,
        iconColor: Color,
        title: String,
        layout: ReaderDisplayLayout
    ) -> some View {
        LabeledContent {
            Text(layout.pagingMode.title)
                .font(AppFont.body())
                .foregroundStyle(Color.textSecondary)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.body())
                        .foregroundStyle(Color.textPrimary)

                    Text(readerSummary(for: layout))
                        .font(AppFont.caption())
                        .foregroundStyle(Color.textTertiary)
                }
            } icon: {
                SettingsIcon(systemName: icon, color: iconColor)
            }
        }
    }

    private func readerSummary(for layout: ReaderDisplayLayout) -> String {
        [
            layout.readingDirection.title,
            layout.fitMode.title,
            layout.coverAsSinglePage ? "Cover single" : "Cover spread"
        ].joined(separator: " · ")
    }

    // MARK: - Remote

    private var remoteSection: some View {
        Section {
            NavigationLink {
                RemoteCacheSettingsView(dependencies: dependencies)
            } label: {
                Label {
                    Text("Manage Cache")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textPrimary)
                } icon: {
                    SettingsIcon(
                        systemName: "externaldrive.fill",
                        color: .teal
                    )
                }
            }

            LabeledContent {
                Text(remoteCachePolicyPreset.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textSecondary)
            } label: {
                Label {
                    Text("Cache Policy")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textPrimary)
                } icon: {
                    SettingsIcon(
                        systemName: "slider.horizontal.3",
                        color: .indigo
                    )
                }
            }
        } header: {
            Text("Remote")
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Group {
            Section {
                LabeledContent {
                    Text(remoteCacheSummary.isEmpty
                         ? "None"
                         : remoteCacheSummary.summaryText)
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                } label: {
                    Label {
                        Text("Remote Downloads")
                            .font(AppFont.body())
                            .foregroundStyle(Color.textPrimary)
                    } icon: {
                        SettingsIcon(
                            systemName: "arrow.down.circle.fill",
                            color: .blue
                        )
                    }
                }

                LabeledContent {
                    Text(remoteThumbnailCacheSummary.isEmpty
                         ? "None"
                         : remoteThumbnailCacheSummary.summaryText)
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                } label: {
                    Label {
                        Text("Cover Thumbnails")
                            .font(AppFont.body())
                            .foregroundStyle(Color.textPrimary)
                    } icon: {
                        SettingsIcon(
                            systemName: "photo.stack.fill",
                            color: .orange
                        )
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text(storageFooter)
            }

            if !remoteCacheSummary.isEmpty
                || !remoteThumbnailCacheSummary.isEmpty {
                Section {
                    if !remoteCacheSummary.isEmpty {
                        Button {
                            isShowingClearDownloadsConfirmation = true
                        } label: {
                            Label("Clear Remote Downloads",
                                  systemImage: "trash")
                                .font(AppFont.body())
                                .foregroundStyle(Color.appDanger)
                        }
                    }

                    if !remoteThumbnailCacheSummary.isEmpty {
                        Button {
                            isShowingClearThumbnailsConfirmation = true
                        } label: {
                            Label("Clear Cover Thumbnails",
                                  systemImage: "trash")
                                .font(AppFont.body())
                                .foregroundStyle(Color.appDanger)
                        }
                    }
                } footer: {
                    Text("Clearing downloads also removes browsing history and remembered server positions.")
                }
            }
        }
    }

    private var storageFooter: String {
        let total = remoteCacheSummary.totalBytes
            + remoteThumbnailCacheSummary.totalBytes
        guard total > 0 else { return "No cached data on this device." }
        let size = ByteCountFormatter.string(
            fromByteCount: total, countStyle: .file
        )
        return "\(size) used on this device."
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(appVersion)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textSecondary)
            } label: {
                Label {
                    Text("Version")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textPrimary)
                } icon: {
                    SettingsIcon(
                        systemName: "info.circle.fill",
                        color: .gray
                    )
                }
            }

            LabeledContent {
                Text("\(viewModel.items.count)")
                    .font(AppFont.body())
                    .foregroundStyle(Color.textSecondary)
            } label: {
                Label {
                    Text("Local Libraries")
                        .font(AppFont.body())
                        .foregroundStyle(Color.textPrimary)
                } icon: {
                    SettingsIcon(
                        systemName: "books.vertical.fill",
                        color: .appAccent
                    )
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "–"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "–"
        return "\(version) (\(build))"
    }

    private func refresh() {
        comicLayout = dependencies.readerLayoutPreferencesStore
            .loadLayout(for: .comic)
        mangaLayout = dependencies.readerLayoutPreferencesStore
            .loadLayout(for: .manga)
        webcomicLayout = dependencies.readerLayoutPreferencesStore
            .loadLayout(for: .webComic)
        remoteCacheSummary = dependencies.remoteServerBrowsingService
            .cacheSummary()
        remoteCachePolicyPreset = dependencies.remoteServerBrowsingService
            .cachePolicyPreset()
        remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared
            .cacheSummary()
    }

    private func clearRemoteDownloads() {
        do {
            try dependencies.remoteServerBrowsingService.clearCachedComics()
            try dependencies.remoteReadingProgressStore.clearAllSessions()
            let profiles = (try? dependencies.remoteServerProfileStore
                .load()) ?? []
            for profile in profiles {
                RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            }
            refresh()
        } catch {
            alert = SettingsAlertState(
                title: "Failed to Clear Downloads",
                message: error.localizedDescription
            )
        }
    }

    private func clearRemoteThumbnails() {
        do {
            try RemoteComicThumbnailPipeline.shared.clearCache()
            refresh()
        } catch {
            alert = SettingsAlertState(
                title: "Failed to Clear Thumbnails",
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Settings Icon

private struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(
                    cornerRadius: CornerRadius.sm,
                    style: .continuous
                )
                .fill(color)
            )
    }
}
