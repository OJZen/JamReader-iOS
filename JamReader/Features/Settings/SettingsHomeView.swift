import SwiftUI

struct SettingsHomeView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    var body: some View {
        SettingsContentView(
            pane: .overview,
            title: "Settings",
            titleDisplayMode: .large,
            viewModel: viewModel,
            dependencies: dependencies
        )
    }
}

struct SettingsSidebarView: View {
    @Environment(\.appNavigator) private var appNavigator

    @AppStorage(AppNavigationStorageKeys.settingsHomeSelectedPane) private var selectedPaneRawValue = SettingsHomePane.overview.rawValue
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var snapshot = SettingsSnapshot.empty
    @State private var refreshGeneration: UInt64 = 0

    private var selectedPane: SettingsHomePane {
        SettingsHomePane.restored(from: selectedPaneRawValue)
    }

    var body: some View {
        List {
            ForEach(SettingsHomePane.allCases) { pane in
                Button {
                    select(pane)
                } label: {
                    SettingsPaneRow(
                        pane: pane,
                        detail: detailText(for: pane),
                        isSelected: pane == selectedPane
                    )
                }
                .buttonStyle(.plain)
                .pointerHoverEffect()
                .listRowBackground(
                    pane == selectedPane
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .onChange(of: viewModel.items.count) { _, count in
            snapshot.localLibraryCount = count
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerLayoutPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadReaderPreferences(
                preferencesStore: dependencies.readerLayoutPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .libraryPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadLibraryPreferences(
                preferencesStore: dependencies.libraryPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .remoteCacheSettingsDidChange
            )
        ) { _ in
            Task { await refreshStorage() }
        }
    }

    private func select(_ pane: SettingsHomePane) {
        selectedPaneRawValue = pane.rawValue
        appNavigator?.navigate(.settings(pane.navigationRoute))
    }

    private func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshedSnapshot = await SettingsSnapshot.load(
            libraryCount: viewModel.items.count,
            dependencies: dependencies
        )
        guard generation == refreshGeneration else {
            return
        }
        snapshot = refreshedSnapshot
        snapshot.localLibraryCount = viewModel.items.count
        if selectedPaneRawValue != selectedPane.rawValue {
            selectedPaneRawValue = selectedPane.rawValue
        }
    }

    private func refreshStorage() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let storage = await SettingsSnapshot.loadStorage(dependencies: dependencies)
        guard generation == refreshGeneration else {
            return
        }
        snapshot.applyStorage(storage)
    }

    private func detailText(for pane: SettingsHomePane) -> String? {
        switch pane {
        case .overview:
            return nil
        case .reading:
            return String(localized: "3 Profiles")
        case .library:
            return snapshot.recentWindow.settingsLocalizedTitle
        case .storage:
            return String(
                localized: "\(snapshot.remoteCachePolicyPreset.settingsLocalizedTitle) · \(snapshot.managedStorageText)"
            )
        case .about:
            return snapshot.appVersion
        }
    }
}

struct SettingsPaneContentView: View {
    let pane: SettingsHomePane
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    var body: some View {
        SettingsContentView(
            pane: pane,
            title: pane.title,
            titleDisplayMode: .inline,
            viewModel: viewModel,
            dependencies: dependencies
        )
    }
}

private struct SettingsContentView: View {
    @Environment(\.appNavigator) private var appNavigator

    let pane: SettingsHomePane
    let title: LocalizedStringKey
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var snapshot = SettingsSnapshot.empty
    @State private var refreshGeneration: UInt64 = 0

    var body: some View {
        List {
            SettingsPaneSections(
                pane: pane,
                snapshot: snapshot,
                onOpenReaderDefaults: openReaderDefaults,
                onSetRecentWindow: setRecentWindow,
                onOpenCacheManagement: openCacheManagement
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .onChange(of: viewModel.items.count) { _, count in
            snapshot.localLibraryCount = count
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerLayoutPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadReaderPreferences(
                preferencesStore: dependencies.readerLayoutPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .libraryPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadLibraryPreferences(
                preferencesStore: dependencies.libraryPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .remoteCacheSettingsDidChange
            )
        ) { _ in
            Task { await refreshStorage() }
        }
    }

    private func openReaderDefaults(_ profile: ReaderDefaultProfile) {
        appNavigator?.navigate(.settings(.readerDefaults(profile)))
    }

    private func setRecentWindow(_ option: LibraryRecentWindowOption) {
        snapshot.recentWindow = option
        dependencies.libraryPreferencesStore.saveRecentWindow(option)
    }

    private func openCacheManagement() {
        appNavigator?.navigate(.settings(.remoteCache))
    }

    private func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshedSnapshot = await SettingsSnapshot.load(
            libraryCount: viewModel.items.count,
            dependencies: dependencies
        )
        guard generation == refreshGeneration else {
            return
        }
        snapshot = refreshedSnapshot
        snapshot.localLibraryCount = viewModel.items.count
    }

    private func refreshStorage() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let storage = await SettingsSnapshot.loadStorage(dependencies: dependencies)
        guard generation == refreshGeneration else {
            return
        }
        snapshot.applyStorage(storage)
    }
}
