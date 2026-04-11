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
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .readContainerWidth(into: $containerWidth)
        .task { refresh() }
    }

    private var usesSplitViewLayout: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularNavigationSplitMinWidth)
    }

    private var selectedPane: Binding<SettingsHomePane?> {
        Binding(
            get: { SettingsHomePane(rawValue: selectedPaneRawValue) ?? .overview },
            set: { selectedPaneRawValue = ($0 ?? .overview).rawValue }
        )
    }

    private var compactLayout: some View {
        NavigationStack {
            settingsList(title: "Settings", displayMode: .large) {
                readingSection
                remoteSection
                storageSection
                aboutSection
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
            Text("Default reader layout for each type.")
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
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text("Manage Cache")
                            .font(AppFont.body())
                            .foregroundStyle(Color.textPrimary)

                        Text(storageFooter)
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
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
                        Text("Imported Comics")
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
                Text("Manage Cache for cleanup.")
            }
        }
    }

    private var storageFooter: String {
        let total = remoteCacheSummary.totalBytes
            + remoteThumbnailCacheSummary.totalBytes
            + importedComicsLibrarySummary.totalBytes
        guard total > 0 else { return "No remote data." }
        let size = ByteCountFormatter.string(
            fromByteCount: total, countStyle: .file
        )
        return "\(size) on this device."
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
            settingsList(title: "Settings", displayMode: .inline) {
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
        title: LocalizedStringKey,
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

    private func detailText(for pane: SettingsHomePane) -> String {
        switch pane {
        case .overview:
            return "Reading, remote, storage, and app info"
        case .reading:
            return "Reader defaults by content type"
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

    var title: LocalizedStringKey {
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
