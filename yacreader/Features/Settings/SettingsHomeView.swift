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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormOverviewContent(
                        message: "Keep reader defaults and maintenance here, while Library and Browse stay focused on active work.",
                        items: [
                            FormOverviewItem(title: "Local Libraries", value: "\(viewModel.items.count)"),
                            FormOverviewItem(title: "Remote Cache Policy", value: remoteCachePolicyPreset.title)
                        ]
                    )
                }

                Section("Reader Defaults") {
                    ReaderDefaultSummaryRow(title: "Comics", layout: comicLayout)
                    ReaderDefaultSummaryRow(title: "Manga", layout: mangaLayout)
                    ReaderDefaultSummaryRow(title: "Webcomics", layout: webcomicLayout)
                }

                Section("Remote Browse Cache") {
                    NavigationLink {
                        RemoteCacheSettingsView(dependencies: dependencies)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Manage Remote Cache")
                                    .font(.headline)

                                Spacer()

                                Text(remoteCachePolicyPreset.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(remoteCacheSummary.isEmpty
                                 ? "No downloaded remote comics are cached on this device right now."
                                 : remoteCacheSummary.summaryText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(remoteThumbnailCacheSummary.isEmpty
                                 ? "No saved thumbnail cache yet."
                                 : remoteThumbnailCacheSummary.summaryText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                refresh()
            }
            .refreshable {
                refresh()
            }
        }
    }

    private func refresh() {
        comicLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .comic)
        mangaLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .manga)
        webcomicLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .webComic)
        remoteCacheSummary = dependencies.remoteServerBrowsingService.cacheSummary()
        remoteCachePolicyPreset = dependencies.remoteServerBrowsingService.cachePolicyPreset()
        remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()
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
