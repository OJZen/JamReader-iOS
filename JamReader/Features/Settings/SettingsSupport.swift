import SwiftUI

enum ReaderDefaultProfile: String, CaseIterable, Identifiable, Hashable {
    case comics
    case manga
    case webcomics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comics:
            return String(localized: "Comics")
        case .manga:
            return String(localized: "Manga")
        case .webcomics:
            return String(localized: "Webcomics")
        }
    }

    var navigationTitle: String {
        switch self {
        case .comics:
            return String(localized: "Comics Defaults")
        case .manga:
            return String(localized: "Manga Defaults")
        case .webcomics:
            return String(localized: "Webcomics Defaults")
        }
    }

    var systemImage: String {
        switch self {
        case .comics:
            return "book.fill"
        case .manga:
            return "book.closed.fill"
        case .webcomics:
            return "scroll.fill"
        }
    }

    var tint: Color {
        switch self {
        case .comics:
            return .blue
        case .manga:
            return .purple
        case .webcomics:
            return .green
        }
    }

    var fileType: LibraryFileType {
        switch self {
        case .comics:
            return .comic
        case .manga:
            return .manga
        case .webcomics:
            return .webComic
        }
    }

    func summary(for layout: ReaderDisplayLayout) -> String {
        if layout.pagingMode == .verticalContinuous {
            return [
                layout.pagingMode.settingsLocalizedTitle,
                layout.fitMode.settingsLocalizedTitle
            ]
                .joined(separator: " · ")
        }

        var parts = [
            layout.pagingMode.settingsLocalizedTitle,
            layout.spreadMode.settingsLocalizedTitle,
            layout.readingDirection.settingsLocalizedTitle,
            layout.fitMode.settingsLocalizedTitle
        ]
        if layout.spreadMode == .doublePage {
            parts.append(
                layout.coverAsSinglePage
                    ? String(localized: "Cover Single")
                    : String(localized: "Cover Spread")
            )
        }
        return parts.joined(separator: " · ")
    }
}

private extension ReaderPagingMode {
    var settingsLocalizedTitle: String {
        switch self {
        case .paged:
            return String(localized: "Paged")
        case .verticalContinuous:
            return String(localized: "Vertical Scroll")
        }
    }
}

private extension ReaderSpreadMode {
    var settingsLocalizedTitle: String {
        switch self {
        case .singlePage:
            return String(localized: "Single Page")
        case .doublePage:
            return String(localized: "Double Page")
        }
    }
}

private extension ReaderReadingDirection {
    var settingsLocalizedTitle: String {
        switch self {
        case .leftToRight:
            return String(localized: "Left to Right")
        case .rightToLeft:
            return String(localized: "Right to Left")
        }
    }
}

private extension ReaderFitMode {
    var settingsLocalizedTitle: String {
        switch self {
        case .page:
            return String(localized: "Fit Page")
        case .width:
            return String(localized: "Fit Width")
        case .height:
            return String(localized: "Fit Height")
        case .originalSize:
            return String(localized: "Original Size")
        }
    }
}

extension LibraryRecentWindowOption {
    var settingsLocalizedTitle: String {
        String(localized: "\(rawValue) Days")
    }
}

extension RemoteComicCachePolicyPreset {
    var settingsLocalizedTitle: String {
        switch self {
        case .unlimited:
            return String(localized: "Unlimited")
        default:
            return title
        }
    }
}

enum SettingsHomePane: String, CaseIterable, Identifiable, Hashable {
    case overview
    case reading
    case library
    case storage
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    var titleString: String {
        switch self {
        case .overview:
            return "Overview"
        case .reading:
            return "Reading"
        case .library:
            return "Library"
        case .storage:
            return "Storage"
        case .about:
            return "About"
        }
    }

    var navigationRoute: SettingsNavigationRoute {
        switch self {
        case .overview:
            return .overview
        case .reading:
            return .reading
        case .library:
            return .library
        case .storage:
            return .storage
        case .about:
            return .about
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "slider.horizontal.3"
        case .reading:
            return "book.closed.fill"
        case .library:
            return "books.vertical.fill"
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
        case .library:
            return .purple
        case .storage:
            return .orange
        case .about:
            return .gray
        }
    }

    static func restored(from rawValue: String?) -> SettingsHomePane {
        if rawValue == "remote" {
            return .storage
        }
        return rawValue.flatMap(SettingsHomePane.init(rawValue:)) ?? .overview
    }
}

extension SettingsNavigationRoute {
    var settingsPane: SettingsHomePane {
        switch self {
        case .overview:
            return .overview
        case .reading, .readerDefaults:
            return .reading
        case .library:
            return .library
        case .storage, .remoteCache:
            return .storage
        case .about:
            return .about
        }
    }

    var storageValue: String {
        settingsPane.rawValue
    }
}

struct SettingsSnapshot {
    var comicLayout: ReaderDisplayLayout
    var mangaLayout: ReaderDisplayLayout
    var webcomicLayout: ReaderDisplayLayout
    var recentWindow: LibraryRecentWindowOption
    var remoteCacheSummary: RemoteComicCacheSummary
    var remoteCachePolicyPreset: RemoteComicCachePolicyPreset
    var remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary
    var importedComicsLibrarySummary: LibraryStorageFootprintSummary
    var localLibraryCount: Int
    var appVersion: String

    static var empty: SettingsSnapshot {
        return SettingsSnapshot(
            comicLayout: ReaderDisplayLayout(defaultsFor: .comic),
            mangaLayout: ReaderDisplayLayout(defaultsFor: .manga),
            webcomicLayout: ReaderDisplayLayout(defaultsFor: .webComic),
            recentWindow: .defaultOption,
            remoteCacheSummary: .empty,
            remoteCachePolicyPreset: .oneGigabyte,
            remoteThumbnailCacheSummary: .empty,
            importedComicsLibrarySummary: .empty,
            localLibraryCount: 0,
            appVersion: appVersionText()
        )
    }

    static func load(
        libraryCount: Int,
        dependencies: AppDependencies
    ) async -> SettingsSnapshot {
        let storage = await loadStorage(dependencies: dependencies)

        return SettingsSnapshot(
            comicLayout: dependencies.readerLayoutPreferencesStore.loadLayout(for: .comic),
            mangaLayout: dependencies.readerLayoutPreferencesStore.loadLayout(for: .manga),
            webcomicLayout: dependencies.readerLayoutPreferencesStore.loadLayout(for: .webComic),
            recentWindow: dependencies.libraryPreferencesStore.loadRecentWindow(),
            remoteCacheSummary: storage.remoteCacheSummary,
            remoteCachePolicyPreset: storage.remoteCachePolicyPreset,
            remoteThumbnailCacheSummary: storage.remoteThumbnailCacheSummary,
            importedComicsLibrarySummary: storage.importedComicsLibrarySummary,
            localLibraryCount: libraryCount,
            appVersion: appVersionText()
        )
    }

    static func loadStorage(
        dependencies: AppDependencies
    ) async -> SettingsStorageSnapshot {
        async let remoteThumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummaryAsync()
        let diskSummaries = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: (
                        dependencies.remoteServerBrowsingService.cacheSummary(),
                        dependencies.libraryStorageManager.importedComicsLibraryStorageSummary()
                    )
                )
            }
        }

        return SettingsStorageSnapshot(
            remoteCacheSummary: diskSummaries.0,
            remoteCachePolicyPreset: dependencies.remoteCachePolicyStore.loadPreset(),
            remoteThumbnailCacheSummary: await remoteThumbnailCacheSummary,
            importedComicsLibrarySummary: diskSummaries.1
        )
    }

    mutating func reloadReaderPreferences(
        preferencesStore: ReaderLayoutPreferencesStore
    ) {
        comicLayout = preferencesStore.loadLayout(for: .comic)
        mangaLayout = preferencesStore.loadLayout(for: .manga)
        webcomicLayout = preferencesStore.loadLayout(for: .webComic)
    }

    mutating func reloadLibraryPreferences(
        preferencesStore: LibraryPreferencesStore
    ) {
        recentWindow = preferencesStore.loadRecentWindow()
    }

    mutating func applyStorage(_ storage: SettingsStorageSnapshot) {
        remoteCacheSummary = storage.remoteCacheSummary
        remoteCachePolicyPreset = storage.remoteCachePolicyPreset
        remoteThumbnailCacheSummary = storage.remoteThumbnailCacheSummary
        importedComicsLibrarySummary = storage.importedComicsLibrarySummary
    }

    var managedStorageBytes: Int64 {
        remoteCacheSummary.totalBytes
            + remoteThumbnailCacheSummary.totalBytes
            + importedComicsLibrarySummary.totalBytes
    }

    var managedStorageText: String {
        guard managedStorageBytes > 0 else {
            return String(localized: "None")
        }
        return ByteCountFormatter.string(
            fromByteCount: managedStorageBytes,
            countStyle: .file
        )
    }

    func layout(for profile: ReaderDefaultProfile) -> ReaderDisplayLayout {
        switch profile {
        case .comics:
            return comicLayout
        case .manga:
            return mangaLayout
        case .webcomics:
            return webcomicLayout
        }
    }

    private static func appVersionText() -> String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "-"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "-"
        return "\(version) (\(build))"
    }
}

struct SettingsStorageSnapshot {
    let remoteCacheSummary: RemoteComicCacheSummary
    let remoteCachePolicyPreset: RemoteComicCachePolicyPreset
    let remoteThumbnailCacheSummary: RemoteThumbnailCacheSummary
    let importedComicsLibrarySummary: LibraryStorageFootprintSummary
}

struct SettingsSummaryMetric: Identifiable {
    let title: LocalizedStringResource
    let value: String
    let systemImage: String
    let tint: Color

    var id: String { systemImage }
}

struct SettingsSummaryGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: [SettingsSummaryMetric]

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Spacing.md)]
        }
        return [
            GridItem(.flexible(), spacing: Spacing.md),
            GridItem(.flexible(), spacing: Spacing.md)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
            ForEach(metrics) { metric in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(metric.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(metric.title)
                            .font(AppFont.caption())
                            .foregroundStyle(Color.textSecondary)
                        Text(metric.value)
                            .font(AppFont.body(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

struct SettingsNavigationRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String?
    var value: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(systemName: systemImage, color: tint)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.xs)

            if let value {
                Text(value)
                    .font(AppFont.subheadline())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

struct SettingsPaneRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let pane: SettingsHomePane
    let detail: String?
    let isSelected: Bool

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SettingsIcon(systemName: pane.systemImage, color: pane.tint)
                    textContent
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: pane.systemImage, color: pane.tint)
                    textContent
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(pane.title)
                .font(AppFont.body(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !dynamicTypeSize.isAccessibilitySize,
               let detail,
               !detail.isEmpty {
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(
                    cornerRadius: CornerRadius.sm,
                    style: .continuous
                )
                .fill(color)
            )
            .accessibilityHidden(true)
    }
}
