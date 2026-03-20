import SwiftUI

struct SettingsHomeView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var comicLayout = ReaderDisplayLayout(defaultsFor: .comic)
    @State private var mangaLayout = ReaderDisplayLayout(defaultsFor: .manga)
    @State private var webcomicLayout = ReaderDisplayLayout(defaultsFor: .webComic)
    @State private var remoteServerCount = 0
    @State private var remoteSessionCount = 0
    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .balanced
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var isShowingClearRemoteDownloadsConfirmation = false
    @State private var isShowingClearRemoteThumbnailsConfirmation = false
    @State private var alert: SettingsAlertState?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keep the core flows simple.")
                            .font(.headline)

                        Text("Library stays focused on local collections, Browse handles SMB discovery and online reading, and Settings keeps the quieter maintenance work out of the way.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Reader Defaults") {
                    ReaderDefaultSummaryRow(title: "Comics", layout: comicLayout)
                    ReaderDefaultSummaryRow(title: "Manga", layout: mangaLayout)
                    ReaderDefaultSummaryRow(title: "Webcomics", layout: webcomicLayout)
                }

                Section("Remote Browse Cache") {
                    LabeledContent("Saved SMB Servers", value: "\(remoteServerCount)")
                    LabeledContent("Recent Remote Sessions", value: "\(remoteSessionCount)")

                    Picker("Cache Preset", selection: $remoteCachePolicyPreset) {
                        ForEach(RemoteComicCachePolicyPreset.allCases) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }

                    Text(remoteCachePolicyPreset.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if remoteCacheSummary.isEmpty {
                        Text("No downloaded remote comics are cached on this device right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Downloaded Copies", value: remoteCacheSummary.summaryText)

                        Button(role: .destructive) {
                            isShowingClearRemoteDownloadsConfirmation = true
                        } label: {
                            Label("Clear Remote Downloads", systemImage: "trash")
                        }
                    }

                    if remoteThumbnailCacheSummary.isEmpty {
                        Text("Remote comic thumbnails are generated on demand and currently do not have any saved disk cache on this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Thumbnail Cache", value: remoteThumbnailCacheSummary.summaryText)

                        Button(role: .destructive) {
                            isShowingClearRemoteThumbnailsConfirmation = true
                        } label: {
                            Label("Clear Thumbnail Cache", systemImage: "photo.stack")
                        }
                    }
                }

                Section("Library Workspace") {
                    LabeledContent("Local Libraries", value: "\(viewModel.items.count)")

                    Text("Use the Library tab for local folders and imported comic archives. SMB browsing and online reading stay in Browse unless you explicitly import content later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Project Status") {
                    SettingsStatusRow(
                        title: "Library Shell",
                        detail: "Tab-based structure is live, with local and remote responsibilities separated.",
                        tint: .blue
                    )
                    SettingsStatusRow(
                        title: "Reader Runtime",
                        detail: "Shared reader kernel work is in progress so local and SMB reading can converge on the same behavior.",
                        tint: .green
                    )
                    SettingsStatusRow(
                        title: "SMB Browse",
                        detail: "Core browsing, thumbnail-driven remote directories, direct reading, and recursive folder import are already available.",
                        tint: .orange
                    )
                }
            }
            .navigationTitle("Settings")
            .task {
                refresh()
            }
            .onChange(of: remoteCachePolicyPreset) { _, newValue in
                applyRemoteCachePolicyPreset(newValue)
            }
            .refreshable {
                refresh()
            }
            .confirmationDialog(
                "Clear downloaded remote comics?",
                isPresented: $isShowingClearRemoteDownloadsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Downloads", role: .destructive) {
                    clearRemoteDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved SMB servers and reading progress stay intact. Only downloaded remote copies on this device are removed.")
            }
            .confirmationDialog(
                "Clear cached remote thumbnails?",
                isPresented: $isShowingClearRemoteThumbnailsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Thumbnails", role: .destructive) {
                    clearRemoteThumbnails()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only removes generated remote cover thumbnails. Remote downloads and reading progress stay intact.")
            }
            .alert(item: $alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func refresh() {
        comicLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .comic)
        mangaLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .manga)
        webcomicLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .webComic)
        remoteServerCount = ((try? dependencies.remoteServerProfileStore.load()) ?? []).count
        remoteSessionCount = ((try? dependencies.remoteReadingProgressStore.loadSessions()) ?? []).count
        remoteCacheSummary = dependencies.remoteServerBrowsingService.cacheSummary()
        remoteCachePolicyPreset = dependencies.remoteServerBrowsingService.cachePolicyPreset()
        remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()
    }

    private func clearRemoteDownloads() {
        do {
            try dependencies.remoteServerBrowsingService.clearCachedComics()
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

    private func applyRemoteCachePolicyPreset(_ preset: RemoteComicCachePolicyPreset) {
        do {
            try dependencies.remoteServerBrowsingService.applyCachePolicyPreset(preset)
            refresh()
        } catch {
            alert = SettingsAlertState(
                title: "Failed to Update Cache Policy",
                message: error.localizedDescription
            )
        }
    }
}

private struct ReaderDefaultSummaryRow: View {
    let title: String
    let layout: ReaderDisplayLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Text(layout.pagingMode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var summaryText: String {
        [
            layout.readingDirection.title,
            layout.fitMode.title,
            layout.coverAsSinglePage ? "Cover stays single" : "Cover can spread"
        ].joined(separator: " · ")
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
