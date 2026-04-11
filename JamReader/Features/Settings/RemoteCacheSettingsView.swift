import SwiftUI

struct RemoteCacheSettingsView: View {
    let dependencies: AppDependencies

    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .balanced
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var importedComicsLibrarySummary: LibraryStorageFootprintSummary = .empty
    @State private var isShowingClearRemoteDownloadsConfirmation = false
    @State private var isShowingClearRemoteThumbnailsConfirmation = false
    @State private var isShowingClearImportedComicsConfirmation = false
    @State private var alert: AppAlertState?

    var body: some View {
        Form {
            Section {
                Picker("Retention", selection: $remoteCachePolicyPreset) {
                    ForEach(RemoteComicCachePolicyPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("On Device") {
                    Text(remoteCacheSummary.isEmpty ? "None" : remoteCacheSummary.summaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if !remoteCacheSummary.isEmpty {
                    Button(role: .destructive) {
                        isShowingClearRemoteDownloadsConfirmation = true
                    } label: {
                        Label("Clear Downloads", systemImage: "trash")
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text(downloadedCopiesFooter)
            }

            Section {
                LabeledContent("On Device") {
                    Text(remoteThumbnailCacheSummary.isEmpty ? "None" : remoteThumbnailCacheSummary.summaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if !remoteThumbnailCacheSummary.isEmpty {
                    Button(role: .destructive) {
                        isShowingClearRemoteThumbnailsConfirmation = true
                    } label: {
                        Label("Clear Thumbnails", systemImage: "photo.stack")
                    }
                }
            } header: {
                Text("Thumbnails")
            } footer: {
                Text(thumbnailCacheFooter)
            }

            Section {
                LabeledContent("On Device") {
                    Text(importedComicsLibrarySummary.isEmpty ? "None" : importedComicsLibrarySummary.summaryText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if !importedComicsLibrarySummary.isEmpty {
                    Button(role: .destructive) {
                        isShowingClearImportedComicsConfirmation = true
                    } label: {
                        Label("Clear Imported", systemImage: "books.vertical")
                    }
                }
            } header: {
                Text("Imported")
            } footer: {
                Text(importedComicsFooter)
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
            "Clear downloads?",
            isPresented: $isShowingClearRemoteDownloadsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Downloads", role: .destructive) {
                clearRemoteDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Servers stay intact. Downloads and remote history are removed.")
        }
        .confirmationDialog(
            "Clear thumbnails?",
            isPresented: $isShowingClearRemoteThumbnailsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Thumbnails", role: .destructive) {
                clearRemoteThumbnails()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only remote cover thumbnails are removed.")
        }
        .confirmationDialog(
            "Clear imported comics?",
            isPresented: $isShowingClearImportedComicsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Imported", role: .destructive) {
                clearImportedComicsLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Imported files are removed. The library stays in the app.")
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var downloadedCopiesFooter: String {
        if remoteCacheSummary.isEmpty {
            return "\(remoteCachePolicyPreset.subtitle). Downloaded comics appear here."
        }

        return "\(remoteCachePolicyPreset.subtitle). Clearing downloads also clears remote history."
    }

    private var thumbnailCacheFooter: String {
        if remoteThumbnailCacheSummary.isEmpty {
            return "Remote covers appear here as you browse."
        }

        return "Only affects generated remote covers."
    }

    private var importedComicsFooter: String {
        if importedComicsLibrarySummary.isEmpty {
            return "Imported remote comics appear here."
        }

        return "Imported comics stay even if you clear downloads or thumbnails."
    }

    private func refresh() {
        remoteCacheSummary = dependencies.remoteServerBrowsingService.cacheSummary()
        remoteCachePolicyPreset = dependencies.remoteServerBrowsingService.cachePolicyPreset()
        remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()
        importedComicsLibrarySummary = dependencies.libraryStorageManager.importedComicsLibraryStorageSummary()
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
            alert = AppAlertState(
                title: "Failed to Clear Downloads",
                message: error.userFacingMessage
            )
        }
    }

    private func clearRemoteThumbnails() {
        do {
            try RemoteComicThumbnailPipeline.shared.clearCache()
            refresh()
        } catch {
            alert = AppAlertState(
                title: "Failed to Clear Thumbnails",
                message: error.userFacingMessage
            )
        }
    }

    private func clearImportedComicsLibrary() {
        do {
            try dependencies.importedComicsImportService.clearImportedComicsLibrary()
            refresh()
        } catch {
            alert = AppAlertState(
                title: "Failed to Clear Imported Comics",
                message: error.userFacingMessage
            )
        }
    }

    private func applyRemoteCachePolicyPreset(_ preset: RemoteComicCachePolicyPreset) {
        do {
            try dependencies.remoteServerBrowsingService.applyCachePolicyPreset(preset)
            refresh()
        } catch {
            alert = AppAlertState(
                title: "Failed to Update Cache Policy",
                message: error.userFacingMessage
            )
        }
    }
}
