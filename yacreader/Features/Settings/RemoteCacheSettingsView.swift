import SwiftUI

struct RemoteCacheSettingsView: View {
    let dependencies: AppDependencies

    @State private var remoteServerCount = 0
    @State private var remoteSessionCount = 0
    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .balanced
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var isShowingClearRemoteDownloadsConfirmation = false
    @State private var isShowingClearRemoteThumbnailsConfirmation = false
    @State private var alert: SettingsAlertState?

    var body: some View {
        Form {
            Section {
                RemoteCacheSummaryCard(
                    summaryMetrics: summaryMetrics,
                    metadataItems: summaryMetadataItems,
                    description: summaryDescription
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: 12,
                        bottom: 6,
                        trailing: 12
                    )
                )
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Retention")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("Cache Preset", selection: $remoteCachePolicyPreset) {
                        ForEach(RemoteComicCachePolicyPreset.allCases) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)

                LabeledContent("Current Limit") {
                    Text(remoteCachePolicyPreset.subtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("On This Device") {
                    Text(remoteCacheSummary.isEmpty ? "None" : remoteCacheSummary.summaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if remoteCacheSummary.isEmpty {
                    Label(
                        "Downloaded remote comics will appear here after you save them for offline reading.",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive) {
                        isShowingClearRemoteDownloadsConfirmation = true
                    } label: {
                        Label("Clear Downloaded Copies", systemImage: "trash")
                    }
                }
            } header: {
                Text("Downloaded Copies")
            } footer: {
                Text("Clearing downloaded copies also removes remote browsing history and remembered server folder positions.")
            }

            Section {
                LabeledContent("On This Device") {
                    Text(remoteThumbnailCacheSummary.isEmpty ? "None" : remoteThumbnailCacheSummary.summaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if remoteThumbnailCacheSummary.isEmpty {
                    Label(
                        "Remote covers are generated on demand and only saved locally after you browse them.",
                        systemImage: "photo.stack"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive) {
                        isShowingClearRemoteThumbnailsConfirmation = true
                    } label: {
                        Label("Clear Thumbnail Cache", systemImage: "photo.stack")
                    }
                }
            } header: {
                Text("Cover Thumbnails")
            } footer: {
                Text("Thumbnail cache only affects generated remote covers. Downloaded copies and reading progress stay intact.")
            }
        }
        .navigationTitle("Remote Cache")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
        }
        .refreshable {
            refresh()
        }
        .onChange(of: remoteCachePolicyPreset) { _, newValue in
            applyRemoteCachePolicyPreset(newValue)
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
            Text("Saved remote servers stay intact. Downloaded remote copies, browsing history, and remembered remote folder positions are removed.")
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

    private var summaryMetrics: [SummaryMetricItem] {
        [
            SummaryMetricItem(
                title: "Servers",
                value: "\(remoteServerCount)",
                tint: .blue
            ),
            SummaryMetricItem(
                title: "Downloads",
                value: "\(remoteCacheSummary.fileCount)",
                tint: .green
            ),
            SummaryMetricItem(
                title: "Covers",
                value: "\(remoteThumbnailCacheSummary.fileCount)",
                tint: .orange
            )
        ]
    }

    private var summaryMetadataItems: [RemoteInlineMetadataItem] {
        [
            RemoteInlineMetadataItem(
                systemImage: "slider.horizontal.3",
                text: "\(remoteCachePolicyPreset.title) retention",
                tint: .teal
            ),
            RemoteInlineMetadataItem(
                systemImage: "clock.arrow.circlepath",
                text: "\(remoteSessionCount) recent sessions",
                tint: .orange
            ),
            RemoteInlineMetadataItem(
                systemImage: "internaldrive",
                text: localStorageFootprintText,
                tint: .blue
            )
        ]
    }

    private var localStorageFootprintText: String {
        let totalBytes = remoteCacheSummary.totalBytes + remoteThumbnailCacheSummary.totalBytes
        guard totalBytes > 0 else {
            return "No local cache yet"
        }

        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) + " on device"
    }

    private var summaryDescription: String {
        if remoteCacheSummary.isEmpty, remoteThumbnailCacheSummary.isEmpty {
            return "Remote content is fetched on demand until you save comics or generate covers again."
        }

        if remoteCacheSummary.isEmpty {
            return "Generated covers are cached locally, while full remote comics are not currently stored on this device."
        }

        return "Downloaded comics and generated covers are kept locally so remote browsing and reading stay responsive."
    }

    private func refresh() {
        remoteServerCount = ((try? dependencies.remoteServerProfileStore.load()) ?? []).count
        remoteSessionCount = ((try? dependencies.remoteReadingProgressStore.loadSessions()) ?? []).count
        remoteCacheSummary = dependencies.remoteServerBrowsingService.cacheSummary()
        remoteCachePolicyPreset = dependencies.remoteServerBrowsingService.cachePolicyPreset()
        remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()
    }

    private func clearRemoteDownloads() {
        do {
            try dependencies.remoteServerBrowsingService.clearCachedComics()
            try dependencies.remoteReadingProgressStore.clearAllSessions()
            let profiles = (try? dependencies.remoteServerProfileStore.load()) ?? []
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

private struct RemoteCacheSummaryCard: View {
    let summaryMetrics: [SummaryMetricItem]
    let metadataItems: [RemoteInlineMetadataItem]
    let description: String

    var body: some View {
        InsetCard(
            cornerRadius: 20,
            contentPadding: 14,
            backgroundColor: Color(.systemBackground),
            strokeOpacity: 0.04
        ) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.18),
                                    Color.teal.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "internaldrive.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Remote Storage")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Manage downloaded remote comics and generated covers kept on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            SummaryMetricGroup(
                metrics: summaryMetrics,
                style: .compactValue,
                horizontalSpacing: 8,
                verticalSpacing: 8
            )

            RemoteInlineMetadataLine(
                items: metadataItems,
                horizontalSpacing: 8,
                verticalSpacing: 4
            )

            Label(description, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
