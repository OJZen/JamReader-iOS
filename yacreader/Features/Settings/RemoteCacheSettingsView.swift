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
                FormOverviewContent(
                    message: "Keep downloaded SMB comics and generated thumbnails under control here, while Browse stays focused on discovery and reading.",
                    items: [
                        FormOverviewItem(title: "Saved SMB Servers", value: "\(remoteServerCount)"),
                        FormOverviewItem(title: "Recent Remote Sessions", value: "\(remoteSessionCount)")
                    ]
                )
            }

            Section("Downloaded Copies") {
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
            }

            Section("Thumbnails") {
                if !remoteThumbnailCacheSummary.isEmpty {
                    LabeledContent("Thumbnail Cache", value: remoteThumbnailCacheSummary.summaryText)
                }

                if remoteThumbnailCacheSummary.isEmpty {
                    Text("Remote comic thumbnails are generated on demand and currently do not have any saved disk cache on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive) {
                        isShowingClearRemoteThumbnailsConfirmation = true
                    } label: {
                        Label("Clear Thumbnail Cache", systemImage: "photo.stack")
                    }
                }
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
