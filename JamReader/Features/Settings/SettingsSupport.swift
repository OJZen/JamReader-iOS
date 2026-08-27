import Combine
import SwiftUI

extension ReaderDisplayLayout {
    var settingsSummary: String {
        if pagingMode == .verticalContinuous {
            return [
                pagingMode.settingsLocalizedTitle,
                fitMode.settingsLocalizedTitle
            ]
                .joined(separator: " · ")
        }

        var parts = [
            pagingMode.settingsLocalizedTitle,
            spreadMode.settingsLocalizedTitle,
            readingDirection.settingsLocalizedTitle,
            fitMode.settingsLocalizedTitle
        ]
        if spreadMode == .doublePage {
            let pairing = coverAsSinglePage
                ? "1 / 2–3 / 4–5"
                : "1–2 / 3–4"
            parts.append("\(String(localized: "Page Pairing")): \(pairing)")
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

extension AppLaunchDestination {
    var settingsLocalizedTitle: String {
        switch self {
        case .lastUsedTab:
            return String(localized: "Last Used Tab")
        case .library:
            return String(localized: "Library")
        case .browse:
            return String(localized: "Browse")
        }
    }
}

enum SettingsHomePane: String, CaseIterable, Identifiable, Hashable {
    case general
    case reading
    case library
    case storage

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:
            return "General"
        case .reading:
            return "Reading"
        case .library:
            return "Library"
        case .storage:
            return "Storage"
        }
    }

    var titleString: String {
        switch self {
        case .general:
            return String(localized: "General")
        case .reading:
            return String(localized: "Reading")
        case .library:
            return String(localized: "Library")
        case .storage:
            return String(localized: "Storage")
        }
    }

    var navigationRoute: SettingsNavigationRoute {
        switch self {
        case .general:
            return .general
        case .reading:
            return .reading
        case .library:
            return .library
        case .storage:
            return .storage
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .reading:
            return "book.closed.fill"
        case .library:
            return "books.vertical.fill"
        case .storage:
            return "internaldrive.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general:
            return .gray
        case .reading:
            return .blue
        case .library:
            return .purple
        case .storage:
            return .orange
        }
    }

    static func restored(from rawValue: String?) -> SettingsHomePane {
        if rawValue == "remote" {
            return .storage
        }
        if rawValue == "about" || rawValue == "overview" {
            return .general
        }
        return rawValue.flatMap(SettingsHomePane.init(rawValue:)) ?? .general
    }
}

@MainActor
final class SettingsSelectionState: ObservableObject {
    @Published private(set) var selectedPane: SettingsHomePane

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let rawValue = userDefaults.string(
            forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
        )
        let selectedPane = SettingsHomePane.restored(from: rawValue)
        self.selectedPane = selectedPane

        if rawValue != selectedPane.rawValue {
            userDefaults.set(
                selectedPane.rawValue,
                forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
            )
        }
    }

    func select(_ pane: SettingsHomePane) {
        guard selectedPane != pane else {
            return
        }

        selectedPane = pane
        userDefaults.set(
            pane.rawValue,
            forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
        )
    }
}

extension SettingsNavigationRoute {
    var settingsPane: SettingsHomePane {
        switch self {
        case .overview:
            return .general
        case .general:
            return .general
        case .reading, .readerDefaults:
            return .reading
        case .library:
            return .library
        case .storage, .remoteCache:
            return .storage
        }
    }

    var storageValue: String {
        settingsPane.rawValue
    }
}

struct SettingsSnapshot {
    var appLaunchDestination: AppLaunchDestination
    var keepsScreenAwake: Bool
    var readerLayout: ReaderDisplayLayout
    var recentWindow: LibraryRecentWindowOption
    var defaultFolderImportScope: RemoteDirectoryImportScope
    var remoteCachePolicyPreset: RemoteComicCachePolicyPreset
    var localLibraryCount: Int
    var appVersion: String

    static var empty: SettingsSnapshot {
        return SettingsSnapshot(
            appLaunchDestination: .defaultValue,
            keepsScreenAwake: true,
            readerLayout: ReaderDisplayLayout(),
            recentWindow: .defaultOption,
            defaultFolderImportScope: .includeSubfolders,
            remoteCachePolicyPreset: .oneGigabyte,
            localLibraryCount: 0,
            appVersion: appVersionText()
        )
    }

    static func load(
        libraryCount: Int,
        dependencies: AppDependencies
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            appLaunchDestination: dependencies.appLaunchPreferencesStore.loadDestination(),
            keepsScreenAwake: dependencies.readerBehaviorPreferencesStore.loadKeepsScreenAwake(),
            readerLayout: dependencies.readerLayoutPreferencesStore.loadLayout(),
            recentWindow: dependencies.libraryPreferencesStore.loadRecentWindow(),
            defaultFolderImportScope: dependencies.remoteBrowserPreferencesStore.loadDefaultFolderImportScope(),
            remoteCachePolicyPreset: dependencies.remoteCachePolicyStore.loadPreset(),
            localLibraryCount: libraryCount,
            appVersion: appVersionText()
        )
    }

    mutating func reloadAppLaunchPreference(
        preferencesStore: AppLaunchPreferencesStore
    ) {
        appLaunchDestination = preferencesStore.loadDestination()
    }

    mutating func reloadReaderBehaviorPreference(
        preferencesStore: ReaderBehaviorPreferencesStore
    ) {
        keepsScreenAwake = preferencesStore.loadKeepsScreenAwake()
    }

    mutating func reloadReaderPreferences(
        preferencesStore: ReaderLayoutPreferencesStore
    ) {
        readerLayout = preferencesStore.loadLayout()
    }

    mutating func reloadLibraryPreferences(
        preferencesStore: LibraryPreferencesStore
    ) {
        recentWindow = preferencesStore.loadRecentWindow()
    }

    mutating func reloadRemoteBrowserPreferences(
        preferencesStore: RemoteBrowserPreferencesStore
    ) {
        defaultFolderImportScope = preferencesStore.loadDefaultFolderImportScope()
    }

    mutating func reloadRemoteCachePolicy(
        policyStore: RemoteCachePolicyStore
    ) {
        remoteCachePolicyPreset = policyStore.loadPreset()
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

struct SettingsNavigationRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

                if dynamicTypeSize.isAccessibilitySize,
                   let value {
                    valueText(value)
                }
            }

            Spacer(minLength: Spacing.xs)

            if !dynamicTypeSize.isAccessibilitySize,
               let value {
                valueText(value)
            }

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(AppFont.subheadline())
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(
                dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsPaneRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let pane: SettingsHomePane
    let detail: String?
    var showsDisclosureIndicator = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SettingsIcon(systemName: pane.systemImage, color: pane.tint)
                        textContent
                    }
                    Spacer(minLength: 0)
                    disclosureIndicator
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: pane.systemImage, color: pane.tint)
                    textContent
                    Spacer(minLength: 0)
                    disclosureIndicator
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(pane.title)
                .font(AppFont.body(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail,
               !detail.isEmpty {
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var disclosureIndicator: some View {
        if showsDisclosureIndicator {
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
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
