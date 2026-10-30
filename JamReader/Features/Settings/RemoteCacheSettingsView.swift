import SwiftUI
import UIKit
import os

extension Notification.Name {
    static let remoteCacheSettingsDidChange = Notification.Name(
        "JamReader.remoteCacheSettingsDidChange"
    )
}

struct RemoteCacheSettingsView: View {
    private struct CacheSettingsSnapshot {
        let remoteCacheSummary: RemoteComicCacheSummary
        let remoteCachePolicyPreset: RemoteComicCachePolicyPreset
        let remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary
        let importedComicsLibrarySummary: LibraryStorageFootprintSummary
    }

    fileprivate enum CacheMaintenanceAction: String, Identifiable {
        case downloads
        case temporaryCache
        case thumbnails
        case imported

        var id: String { rawValue }

        var buttonTitle: String {
            switch self {
            case .downloads:
                return String(localized: "Clear Downloaded Copies")
            case .temporaryCache:
                return String(localized: "Clear Temporary Cache")
            case .thumbnails:
                return String(localized: "Clear Cover Thumbnails")
            case .imported:
                return String(localized: "Clear Imported Comics")
            }
        }

        var confirmationTitle: String {
            switch self {
            case .downloads:
                return String(localized: "Clear downloaded copies?")
            case .temporaryCache:
                return String(localized: "Clear temporary cache?")
            case .thumbnails:
                return String(localized: "Clear cover thumbnails?")
            case .imported:
                return String(localized: "Clear imported comics?")
            }
        }

        var confirmationMessage: String {
            switch self {
            case .downloads:
                return String(localized: "Every downloaded copy, including offline copies, is removed from this device. Servers, reading history, and progress stay.")
            case .temporaryCache:
                return String(localized: "Unfinished downloads and leftover remote cache files are removed.")
            case .thumbnails:
                return String(localized: "Generated remote cover images are removed and recreated as needed.")
            case .imported:
                return String(localized: "Imported files are removed. The Imported Comics library remains available.")
            }
        }

        var progressTitle: String {
            switch self {
            case .downloads:
                return String(localized: "Clearing Downloads")
            case .temporaryCache:
                return String(localized: "Clearing Temporary Cache")
            case .thumbnails:
                return String(localized: "Clearing Thumbnails")
            case .imported:
                return String(localized: "Clearing Imported Comics")
            }
        }

        var progressMessage: String {
            switch self {
            case .downloads:
                return String(localized: "Removing downloaded remote files.")
            case .temporaryCache:
                return String(localized: "Removing incomplete and leftover cache data.")
            case .thumbnails:
                return String(localized: "Removing generated remote cover images.")
            case .imported:
                return String(localized: "Removing imported files and refreshing the library.")
            }
        }

        var failureTitle: String {
            switch self {
            case .downloads:
                return String(localized: "Failed to Clear Downloads")
            case .temporaryCache:
                return String(localized: "Failed to Clear Temporary Cache")
            case .thumbnails:
                return String(localized: "Failed to Clear Thumbnails")
            case .imported:
                return String(localized: "Failed to Clear Imported Comics")
            }
        }

        var completionAnnouncement: String {
            switch self {
            case .downloads:
                return String(localized: "Downloaded copies cleared.")
            case .temporaryCache:
                return String(localized: "Temporary cache cleared.")
            case .thumbnails:
                return String(localized: "Cover thumbnails cleared.")
            case .imported:
                return String(localized: "Imported comics cleared.")
            }
        }

        var conflictsWithRemoteImport: Bool {
            self != .thumbnails
        }
    }

    let dependencies: AppDependencies

    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .oneGigabyte
    @State private var downloadsFullCopyWhileReading = true
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var importedComicsLibrarySummary: LibraryStorageFootprintSummary = .empty
    @State private var pendingConfirmation: CacheMaintenanceAction?
    @State private var maintenanceAction: CacheMaintenanceAction?
    @State private var isApplyingPolicy = false
    @State private var alert: AppAlertState?
    @State private var refreshGeneration: UInt64 = 0
    @AccessibilityFocusState private var maintenanceOverlayIsFocused: Bool

    private let logger = AppLog.remoteCache

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _remoteCachePolicyPreset = State(
            initialValue: dependencies.remoteCachePolicyStore.loadPreset()
        )
        _downloadsFullCopyWhileReading = State(
            initialValue: dependencies.remoteCachePolicyStore.loadDownloadsFullCopyWhileReading()
        )
    }

    private var cachePolicyBinding: Binding<RemoteComicCachePolicyPreset> {
        Binding(
            get: { remoteCachePolicyPreset },
            set: setRemoteCachePolicyPreset
        )
    }

    private var downloadsFullCopyWhileReadingBinding: Binding<Bool> {
        Binding(
            get: { downloadsFullCopyWhileReading },
            set: setDownloadsFullCopyWhileReading
        )
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingConfirmation = nil
                }
            }
        )
    }

    private var isBusy: Bool {
        maintenanceAction != nil || isApplyingPolicy
    }

    var body: some View {
        Form {
            Section {
                StorageUsageSummary(segments: usageSegments)
            }

            Section {
                Picker("Download Limit", selection: cachePolicyBinding) {
                    ForEach(RemoteComicCachePolicyPreset.allCases) { preset in
                        Text(preset.settingsLocalizedTitle).tag(preset)
                    }
                }
                .settingsPickerStyle()

                Toggle(
                    "Download Full Copy While Reading",
                    isOn: downloadsFullCopyWhileReadingBinding
                )

                if isApplyingPolicy {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Applying download limit")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                StorageItemRow(
                    title: String(localized: "Downloaded"),
                    bytes: remoteCacheSummary.hasCachedComics ? remoteCacheSummary.cachedComicBytes : 0,
                    actionTitle: String(localized: "Clean Up")
                ) {
                    pendingConfirmation = .downloads
                }
            } header: {
                Text("Remote Downloads")
            } footer: {
                Text("Downloaded includes offline copies. The limit and full-copy setting apply to comics streamed while reading; offline copies you save are unchanged.")
            }

            Section("Rebuildable Data") {
                StorageItemRow(
                    title: String(localized: "Temporary Data"),
                    bytes: remoteCacheSummary.otherCacheBytes,
                    actionTitle: String(localized: "Clean Up")
                ) {
                    pendingConfirmation = .temporaryCache
                }

                StorageItemRow(
                    title: String(localized: "Remote Cover Thumbnails"),
                    bytes: remoteThumbnailCacheSummary.isEmpty ? 0 : remoteThumbnailCacheSummary.totalBytes,
                    actionTitle: String(localized: "Clean Up")
                ) {
                    pendingConfirmation = .thumbnails
                }
            }

            Section("Your Files") {
                StorageItemRow(
                    title: String(localized: "“Imported Comics” Library"),
                    bytes: importedComicsLibrarySummary.isEmpty ? 0 : importedComicsLibrarySummary.totalBytes,
                    actionTitle: String(localized: "Empty Library")
                ) {
                    pendingConfirmation = .imported
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .accessibilityHidden(maintenanceAction != nil)
        .overlay {
            if let maintenanceAction {
                CacheMaintenanceOverlay(action: maintenanceAction)
                    .accessibilityFocused($maintenanceOverlayIsFocused)
            }
        }
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .confirmationDialog(
            pendingConfirmation?.confirmationTitle ?? "Clear stored data?",
            isPresented: confirmationIsPresented,
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { action in
            Button(action.buttonTitle, role: .destructive) {
                pendingConfirmation = nil
                startMaintenance(action)
            }
            Button("Cancel", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    /// Only what this screen measures; other App libraries are not counted.
    private var usageSegments: [StorageUsageSummary.Segment] {
        [
            StorageUsageSummary.Segment(
                title: String(localized: "Imported Comics"),
                bytes: importedComicsLibrarySummary.isEmpty ? 0 : importedComicsLibrarySummary.totalBytes,
                color: .appJam
            ),
            StorageUsageSummary.Segment(
                title: String(localized: "Remote Downloads"),
                bytes: remoteCacheSummary.hasCachedComics ? remoteCacheSummary.cachedComicBytes : 0,
                color: .appChartDownloads
            ),
            StorageUsageSummary.Segment(
                title: String(localized: "Temporary Data"),
                bytes: remoteCacheSummary.otherCacheBytes,
                color: .appChartTemp
            ),
            StorageUsageSummary.Segment(
                title: String(localized: "Remote Covers"),
                bytes: remoteThumbnailCacheSummary.isEmpty ? 0 : remoteThumbnailCacheSummary.totalBytes,
                color: .appChartThumbs
            )
        ]
    }

    private func setDownloadsFullCopyWhileReading(_ isEnabled: Bool) {
        downloadsFullCopyWhileReading = isEnabled
        dependencies.remoteCachePolicyStore.saveDownloadsFullCopyWhileReading(isEnabled)
    }

    private func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let snapshot = await loadSnapshot()
        guard generation == refreshGeneration else {
            return
        }
        remoteCacheSummary = snapshot.remoteCacheSummary
        remoteCachePolicyPreset = snapshot.remoteCachePolicyPreset
        remoteThumbnailCacheSummary = snapshot.remoteThumbnailCacheSummary
        importedComicsLibrarySummary = snapshot.importedComicsLibrarySummary
    }

    private func loadSnapshot() async -> CacheSettingsSnapshot {
        async let remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummaryAsync()

        let diskSnapshot = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: (
                        dependencies.remoteServerBrowsingService.cacheSummary(),
                        dependencies.remoteServerBrowsingService.cachePolicyPreset(),
                        dependencies.libraryStorageManager.importedComicsLibraryStorageSummary()
                    )
                )
            }
        }

        return CacheSettingsSnapshot(
            remoteCacheSummary: diskSnapshot.0,
            remoteCachePolicyPreset: diskSnapshot.1,
            remoteThumbnailCacheSummary: await remoteThumbnailCacheSummary,
            importedComicsLibrarySummary: diskSnapshot.2
        )
    }

    private func setRemoteCachePolicyPreset(
        _ preset: RemoteComicCachePolicyPreset
    ) {
        guard preset != remoteCachePolicyPreset else {
            return
        }
        guard dependencies.remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            alert = AppAlertState(
                title: String(localized: "Import in Progress"),
                message: String(localized: "Finish or cancel the current remote import before changing the download limit.")
            )
            return
        }

        refreshGeneration &+= 1
        let previousPreset = remoteCachePolicyPreset
        remoteCachePolicyPreset = preset
        isApplyingPolicy = true
        logger.notice(
            "Remote cache settings policy change requested preset=\(preset.rawValue, privacy: .public)"
        )

        Task {
            await applyRemoteCachePolicyPreset(
                preset,
                previousPreset: previousPreset
            )
        }
    }

    private func applyRemoteCachePolicyPreset(
        _ preset: RemoteComicCachePolicyPreset,
        previousPreset: RemoteComicCachePolicyPreset
    ) async {
        defer {
            dependencies.remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }
        do {
            try await runMaintenanceWork {
                dependencies.remoteOfflineLibrarySnapshotStore.invalidate()
                try dependencies.remoteServerBrowsingService.applyCachePolicyPreset(preset)
            }
            await refresh()
            logger.notice(
                "Remote cache settings policy change completed preset=\(preset.rawValue, privacy: .public)"
            )
            notifySettingsChanged()
        } catch {
            dependencies.remoteCachePolicyStore.savePreset(previousPreset)
            remoteCachePolicyPreset = previousPreset
            await refresh()
            logger.error(
                "Remote cache settings policy change failed preset=\(preset.rawValue, privacy: .public) rollback=\(previousPreset.rawValue, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: String(localized: "Failed to Update Download Limit"),
                message: error.userFacingMessage
            )
        }

        isApplyingPolicy = false
    }

    private func startMaintenance(_ action: CacheMaintenanceAction) {
        let ownsStorageMaintenance = action.conflictsWithRemoteImport
            && dependencies.remoteBackgroundImportController.beginExclusiveStorageMaintenance()
        if action.conflictsWithRemoteImport, !ownsStorageMaintenance {
            logger.notice(
                "Remote cache settings maintenance blocked action=\(action.id, privacy: .public) reason=remoteImportRunning"
            )
            alert = AppAlertState(
                title: String(localized: "Import in Progress"),
                message: String(localized: "Finish or cancel the current remote import before clearing this stored data.")
            )
            return
        }

        Task {
            await performMaintenance(
                action,
                ownsStorageMaintenance: ownsStorageMaintenance
            )
        }
    }

    private func performMaintenance(
        _ action: CacheMaintenanceAction,
        ownsStorageMaintenance: Bool
    ) async {
        defer {
            if ownsStorageMaintenance {
                dependencies.remoteBackgroundImportController.endExclusiveStorageMaintenance()
            }
        }
        logger.notice(
            "Remote cache settings maintenance requested action=\(action.id, privacy: .public)"
        )
        maintenanceAction = action
        await Task.yield()
        maintenanceOverlayIsFocused = true
        announceForAccessibility(
            [action.progressTitle, action.progressMessage].joined(separator: ". ")
        )

        let completionAnnouncement: String
        do {
            try await runMaintenanceWork(for: action)
            await refresh()
            notifySettingsChanged()
            logger.notice(
                "Remote cache settings maintenance completed action=\(action.id, privacy: .public)"
            )
            completionAnnouncement = action.completionAnnouncement
        } catch {
            let failureMessage = error.userFacingMessage
            logger.error(
                "Remote cache settings maintenance failed action=\(action.id, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: action.failureTitle,
                message: failureMessage
            )
            completionAnnouncement = [action.failureTitle, failureMessage]
                .joined(separator: ". ")
        }

        maintenanceAction = nil
        maintenanceOverlayIsFocused = false
        await Task.yield()
        announceForAccessibility(completionAnnouncement)
    }

    private func runMaintenanceWork(
        for action: CacheMaintenanceAction
    ) async throws {
        switch action {
        case .downloads:
            try await runMaintenanceWork {
                dependencies.remoteOfflineLibrarySnapshotStore.invalidate()
                try dependencies.remoteServerBrowsingService.clearCachedComics()
                try dependencies.remoteOfflineCopyStore.clearAll()
            }
        case .temporaryCache:
            try await runMaintenanceWork {
                try dependencies.remoteServerBrowsingService.clearOtherCachedData()
            }
        case .thumbnails:
            try await RemoteComicThumbnailPipeline.shared.clearCacheAsync()
        case .imported:
            try await runMaintenanceWork {
                try dependencies.importedComicsImportService.clearImportedComicsLibrary()
            }
        }
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

    private func notifySettingsChanged() {
        NotificationCenter.default.post(
            name: .remoteCacheSettingsDidChange,
            object: dependencies.remoteCachePolicyStore
        )
    }

    private func announceForAccessibility(_ message: String) {
        guard !message.isEmpty else {
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// "Used by JamReader" with a segmented bar and a legend of what each part is.
private struct StorageUsageSummary: View {
    struct Segment: Identifiable {
        let title: String
        let bytes: Int64
        let color: Color

        var id: String { title }
    }

    let segments: [Segment]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Used by JamReader")
                    .font(AppFont.headline())
                Spacer(minLength: Spacing.sm)
                Text(Self.sizeText(totalBytes))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }

            bar
                .frame(height: 10)
                .accessibilityHidden(true)

            WrappingHStack(horizontalSpacing: Spacing.md, verticalSpacing: Spacing.xxs) {
                ForEach(segments) { segment in
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text(segment.title + " " + Self.sizeText(segment.bytes))
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var totalBytes: Int64 {
        segments.reduce(0) { $0 + max($1.bytes, 0) }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.bytes > 0 }
            let spacing: CGFloat = 2
            let available = max(proxy.size.width - spacing * CGFloat(max(visible.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(visible) { segment in
                    segment.color
                        .frame(width: max(available * CGFloat(segment.bytes) / CGFloat(max(totalBytes, 1)), 3))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}

/// A stored item: its size and the button that clears it. What clearing
/// removes is written in the confirmation, not here.
private struct StorageItemRow: View {
    let title: String
    let bytes: Int64
    let actionTitle: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
        layout {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.sm) {
                Text(bytes > 0 ? StorageUsageSummary.sizeText(bytes) : String(localized: "None"))
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()

                Button(action: action) {
                    Text(actionTitle)
                        .font(AppFont.subheadline(.semibold))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.appAccentSoft, in: Capsule())
                        .foregroundStyle(Color.appAccentOnSoft)
                }
                .buttonStyle(.borderless)
                .disabled(bytes <= 0)
                .opacity(bytes > 0 ? 1 : 0.45)
                .accessibilityLabel(Text("\(actionTitle) \(title)"))
            }
        }
    }
}

private struct CacheMaintenanceOverlay: View {
    let action: RemoteCacheSettingsView.CacheMaintenanceAction

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                ProgressView()
                    .controlSize(.large)
                Text(action.progressTitle)
                    .font(AppFont.headline())
                Text(action.progressMessage)
                    .font(AppFont.subheadline())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 320)
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: CornerRadius.lg,
                    style: .continuous
                )
            )
            .appShadow(AppShadow.lg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.progressTitle)
        .accessibilityValue(action.progressMessage)
    }
}
