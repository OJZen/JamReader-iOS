import SwiftUI

struct SettingsHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("settingsHome.selectedPane") private var selectedPaneRawValue = SettingsHomePane.overview.rawValue

    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var comicLayout = ReaderDisplayLayout(defaultsFor: .comic)
    @State private var mangaLayout = ReaderDisplayLayout(defaultsFor: .manga)
    @State private var webcomicLayout = ReaderDisplayLayout(defaultsFor: .webComic)
    @State private var remoteCacheSummary: RemoteComicCacheSummary = .empty
    @State private var remoteCachePolicyPreset: RemoteComicCachePolicyPreset = .balanced
    @State private var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @State private var importedComicsLibrarySummary: LibraryStorageFootprintSummary = .empty
    @State private var isShowingClearDownloadsConfirmation = false
    @State private var isShowingClearThumbnailsConfirmation = false
    @State private var isShowingClearImportedComicsConfirmation = false
    @State private var alert: SettingsAlertState?

    var body: some View {
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .task { refresh() }
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
        .confirmationDialog(
            "Clear imported comics?",
            isPresented: $isShowingClearImportedComicsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Imported Comics", role: .destructive) {
                clearImportedComicsLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All files currently stored in the local Imported Comics library will be removed. The library itself stays in the app as an empty library.")
        }
        .alert(item: $alert) { alertState in
            Alert(
                title: Text(alertState.title),
                message: Text(alertState.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var usesSplitViewLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var selectedPane: Binding<SettingsHomePane?> {
        Binding(
            get: { SettingsHomePane(rawValue: selectedPaneRawValue) ?? .overview },
            set: { selectedPaneRawValue = ($0 ?? .overview).rawValue }
        )
    }

    private var compactLayout: some View {
        NavigationStack {
            settingsList(title: "设置", displayMode: .large) {
                readingSection
                remoteSection
                storageSection
                aboutSection
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView {
            List(selection: selectedPane) {
                ForEach(SettingsHomePane.allCases) { pane in
                    Button {
                        selectedPane.wrappedValue = pane
                    } label: {
                        SettingsPaneRow(
                            pane: pane,
                            detail: detailText(for: pane)
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(pane as SettingsHomePane?)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("设置")
        } detail: {
            NavigationStack {
                splitDetailContent(for: selectedPane.wrappedValue ?? .overview)
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

                LabeledContent {
                    Text(importedComicsLibrarySummary.isEmpty
                         ? "None"
                         : importedComicsLibrarySummary.summaryText)
                        .font(AppFont.body())
                        .foregroundStyle(Color.textSecondary)
                } label: {
                    Label {
                        Text("Imported Comics Library")
                            .font(AppFont.body())
                            .foregroundStyle(Color.textPrimary)
                    } icon: {
                        SettingsIcon(
                            systemName: "books.vertical.fill",
                            color: .purple
                        )
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text(storageFooter)
            }

            if !remoteCacheSummary.isEmpty
                || !remoteThumbnailCacheSummary.isEmpty
                || !importedComicsLibrarySummary.isEmpty {
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

                    if !importedComicsLibrarySummary.isEmpty {
                        Button {
                            isShowingClearImportedComicsConfirmation = true
                        } label: {
                            Label("Clear Imported Comics",
                                  systemImage: "trash")
                                .font(AppFont.body())
                                .foregroundStyle(Color.appDanger)
                        }
                    }
                } footer: {
                    Text("Clearing downloads also removes browsing history and remembered server positions. Clearing imported comics empties the Imported Comics library but keeps the library entry.")
                }
            }
        }
    }

    private var storageFooter: String {
        let total = remoteCacheSummary.totalBytes
            + remoteThumbnailCacheSummary.totalBytes
            + importedComicsLibrarySummary.totalBytes
        guard total > 0 else { return "No local remote data on this device." }
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

    @ViewBuilder
    private func splitDetailContent(for pane: SettingsHomePane) -> some View {
        switch pane {
        case .overview:
            settingsList(title: "设置", displayMode: .inline) {
                readingSection
                remoteSection
                storageSection
                aboutSection
            }
        case .reading:
            settingsList(title: pane.title, displayMode: .inline) {
                readingSection
            }
        case .remote:
            settingsList(title: pane.title, displayMode: .inline) {
                remoteSection
            }
        case .storage:
            settingsList(title: pane.title, displayMode: .inline) {
                storageSection
            }
        case .about:
            settingsList(title: pane.title, displayMode: .inline) {
                aboutSection
            }
        }
    }

    private func settingsList<Content: View>(
        title: String,
        displayMode: NavigationBarItem.TitleDisplayMode,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(displayMode)
        .refreshable {
            refresh()
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
        importedComicsLibrarySummary = dependencies.libraryStorageManager
            .importedComicsLibraryStorageSummary()
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

    private func clearImportedComicsLibrary() {
        do {
            try dependencies.importedComicsImportService.clearImportedComicsLibrary()
            refresh()
        } catch {
            alert = SettingsAlertState(
                title: "Failed to Clear Imported Comics",
                message: error.localizedDescription
            )
        }
    }

    private func detailText(for pane: SettingsHomePane) -> String {
        switch pane {
        case .overview:
            return "Reader defaults, remote access, storage, and app info"
        case .reading:
            return "Comic, manga, and webcomic reader presets"
        case .remote:
            return remoteCachePolicyPreset.title
        case .storage:
            return storageFooter
        case .about:
            return appVersion
        }
    }
}

// MARK: - Settings Icon

private enum SettingsHomePane: String, CaseIterable, Identifiable, Hashable {
    case overview
    case reading
    case remote
    case storage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .reading:
            return "Reading"
        case .remote:
            return "Remote"
        case .storage:
            return "Storage"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "slider.horizontal.3"
        case .reading:
            return "book.closed.fill"
        case .remote:
            return "externaldrive.fill"
        case .storage:
            return "internaldrive.fill"
        case .about:
            return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .appAccent
        case .reading:
            return .blue
        case .remote:
            return .teal
        case .storage:
            return .orange
        case .about:
            return .gray
        }
    }
}

private struct SettingsPaneRow: View {
    let pane: SettingsHomePane
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(systemName: pane.systemImage, color: pane.tint)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(pane.title)
                    .font(AppFont.body(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

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
