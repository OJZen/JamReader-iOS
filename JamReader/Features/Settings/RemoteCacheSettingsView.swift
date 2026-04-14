import SwiftUI

struct RemoteCacheSettingsView: View {
    private struct CacheSettingsSnapshot {
        let remoteCacheSummary: RemoteComicCacheSummary
        let remoteCachePolicyPreset: RemoteComicCachePolicyPreset
        let remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary
        let importedComicsLibrarySummary: LibraryStorageFootprintSummary
    }

    private enum CacheMaintenanceAction: Identifiable {
        case clearingDownloads
        case clearingOtherCache
        case clearingThumbnails
        case clearingImported

        var id: String {
            switch self {
            case .clearingDownloads:
                return "downloads"
            case .clearingOtherCache:
                return "other-cache"
            case .clearingThumbnails:
                return "thumbnails"
            case .clearingImported:
                return "imported"
            }
        }

        var title: String {
            switch self {
            case .clearingDownloads:
                return "Clearing Downloads"
            case .clearingOtherCache:
                return "Clearing Other Cache Data"
            case .clearingThumbnails:
                return "Clearing Thumbnails"
            case .clearingImported:
                return "Clearing Imported Comics"
            }
        }

        var message: String {
            switch self {
            case .clearingDownloads:
                return "Removing remote downloads and cleaning browsing history."
            case .clearingOtherCache:
                return "Removing unfinished downloads and leftover remote cache files."
            case .clearingThumbnails:
                return "Deleting generated remote cover images."
            case .clearingImported:
                return "Removing imported files and rebuilding the local library."
            }
        }
    }

    let dependencies: AppDependencies

    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .oneGigabyte
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var importedComicsLibrarySummary: LibraryStorageFootprintSummary = .empty
    @State private var isShowingClearRemoteDownloadsConfirmation = false
    @State private var isShowingClearOtherCacheConfirmation = false
    @State private var isShowingClearRemoteThumbnailsConfirmation = false
    @State private var isShowingClearImportedComicsConfirmation = false
    @State private var maintenanceAction: CacheMaintenanceAction?
    @State private var alert: AppAlertState?

    var body: some View {
        Form {
            Section {
                Picker("Storage Limit", selection: $remoteCachePolicyPreset) {
                    ForEach(RemoteComicCachePolicyPreset.allCases) { preset in
                        Text(preset.title)
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("On Device") {
                    Text(remoteCacheSummary.hasCachedComics ? remoteCacheSummary.summaryText : "None")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if remoteCacheSummary.hasCachedComics {
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
                    Text(remoteCacheSummary.hasOtherCacheData ? remoteCacheSummary.otherCacheSizeText : "None")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if remoteCacheSummary.hasOtherCacheData {
                    Button(role: .destructive) {
                        isShowingClearOtherCacheConfirmation = true
                    } label: {
                        Label("Clear Other Cache Data", systemImage: "trash.slash")
                    }
                }
            } header: {
                Text("Other Cache Data")
            } footer: {
                Text(otherCacheFooter)
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
        .disabled(isPerformingMaintenance)
        .overlay {
            if let maintenanceAction {
                cacheMaintenanceOverlay(for: maintenanceAction)
            }
        }
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
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
            "Clear other cache data?",
            isPresented: $isShowingClearOtherCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Other Cache Data", role: .destructive) {
                clearOtherCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes unfinished downloads and leftover remote cache files without touching completed offline copies.")
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
        if !remoteCacheSummary.hasCachedComics {
            return "Downloaded comics appear here. Current limit: \(remoteCachePolicyPreset.title)."
        }

        return "Current limit: \(remoteCachePolicyPreset.title). Clearing downloads also clears remote history."
    }

    private var otherCacheFooter: String {
        if !remoteCacheSummary.hasOtherCacheData {
            return "Unfinished downloads and leftover remote cache files appear here."
        }

        return "This is usually partially downloaded comics or leftover cache artifacts."
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

    private var isPerformingMaintenance: Bool {
        maintenanceAction != nil
    }

    @ViewBuilder
    private func cacheMaintenanceOverlay(for action: CacheMaintenanceAction) -> some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(action.title)
                    .font(.headline)
                Text(action.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    private func refresh() async {
        let snapshot = await loadSnapshot()
        remoteCacheSummary = snapshot.remoteCacheSummary
        remoteCachePolicyPreset = snapshot.remoteCachePolicyPreset
        remoteThumbnailCacheSummary = snapshot.remoteThumbnailCacheSummary
        importedComicsLibrarySummary = snapshot.importedComicsLibrarySummary
    }

    private func loadSnapshot() async -> CacheSettingsSnapshot {
        let remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let snapshot = CacheSettingsSnapshot(
                    remoteCacheSummary: dependencies.remoteServerBrowsingService.cacheSummary(),
                    remoteCachePolicyPreset: dependencies.remoteServerBrowsingService.cachePolicyPreset(),
                    remoteThumbnailCacheSummary: remoteThumbnailCacheSummary,
                    importedComicsLibrarySummary: dependencies.libraryStorageManager.importedComicsLibraryStorageSummary()
                )
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func clearRemoteDownloads() {
        Task {
            await performMaintenance(
                .clearingDownloads,
                failureTitle: "Failed to Clear Downloads"
            ) {
                try dependencies.remoteServerBrowsingService.clearCachedComics()
                try dependencies.remoteReadingProgressStore.clearAllSessions()
                dependencies.remoteOfflineLibrarySnapshotStore.invalidate()
                let profiles = (try? dependencies.remoteServerProfileStore.load()) ?? []
                for profile in profiles {
                    RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
                }
            }
        }
    }

    private func clearOtherCache() {
        Task {
            await performMaintenance(
                .clearingOtherCache,
                failureTitle: "Failed to Clear Other Cache Data"
            ) {
                try dependencies.remoteServerBrowsingService.clearOtherCachedData()
            }
        }
    }

    private func clearRemoteThumbnails() {
        Task {
            await performMaintenance(
                .clearingThumbnails,
                failureTitle: "Failed to Clear Thumbnails"
            ) {
                try RemoteComicThumbnailPipeline.shared.clearCache()
            }
        }
    }

    private func clearImportedComicsLibrary() {
        Task {
            await performMaintenance(
                .clearingImported,
                failureTitle: "Failed to Clear Imported Comics"
            ) {
                try dependencies.importedComicsImportService.clearImportedComicsLibrary()
            }
        }
    }

    private func performMaintenance(
        _ action: CacheMaintenanceAction,
        failureTitle: String,
        work: @escaping () throws -> Void
    ) async {
        maintenanceAction = action
        await Task.yield()

        do {
            try await runMaintenanceWork(work)
            await refresh()
        } catch {
            alert = AppAlertState(
                title: failureTitle,
                message: error.userFacingMessage
            )
        }

        maintenanceAction = nil
    }

    private func runMaintenanceWork(
        _ work: @escaping () throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyRemoteCachePolicyPreset(_ preset: RemoteComicCachePolicyPreset) {
        do {
            try dependencies.remoteServerBrowsingService.applyCachePolicyPreset(preset)
            Task {
                await refresh()
            }
        } catch {
            alert = AppAlertState(
                title: "Failed to Update Cache Policy",
                message: error.userFacingMessage
            )
        }
    }
}
