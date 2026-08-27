import SwiftUI

struct SettingsHomeView: View {
    @Environment(\.appNavigator) private var appNavigator

    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var snapshot = SettingsSnapshot.empty

    var body: some View {
        List {
            ForEach(SettingsHomePane.allCases) { pane in
                Button {
                    appNavigator?.navigate(.settings(pane.navigationRoute))
                } label: {
                    SettingsPaneRow(
                        pane: pane,
                        detail: snapshot.detailText(for: pane),
                        showsDisclosureIndicator: true
                    )
                }
                .buttonStyle(.plain)
                .pointerHoverEffect()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            refresh()
        }
        .onChange(of: viewModel.items.count) { _, count in
            snapshot.localLibraryCount = count
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .appLaunchPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadAppLaunchPreference(
                preferencesStore: dependencies.appLaunchPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerBehaviorPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadReaderBehaviorPreference(
                preferencesStore: dependencies.readerBehaviorPreferencesStore
            )
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
                for: .remoteBrowserPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadRemoteBrowserPreferences(
                preferencesStore: dependencies.remoteBrowserPreferencesStore
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
            snapshot.reloadRemoteCachePolicy(
                policyStore: dependencies.remoteCachePolicyStore
            )
        }
    }

    private func refresh() {
        snapshot = SettingsSnapshot.load(
            libraryCount: viewModel.items.count,
            dependencies: dependencies
        )
    }
}

struct SettingsSidebarView: View {
    @Environment(\.appNavigator) private var appNavigator

    @ObservedObject var selectionState: SettingsSelectionState
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var snapshot = SettingsSnapshot.empty

    var body: some View {
        List {
            ForEach(SettingsHomePane.allCases) { pane in
                Button {
                    appNavigator?.navigate(.settings(pane.navigationRoute))
                } label: {
                    SettingsPaneRow(
                        pane: pane,
                        detail: snapshot.detailText(for: pane)
                    )
                }
                .buttonStyle(.plain)
                .persistentSidebarSelection(
                    isSelected: pane == selectionState.selectedPane
                )
                .accessibilityAddTraits(
                    pane == selectionState.selectedPane ? .isSelected : []
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
        }
        .onChange(of: viewModel.items.count) { _, count in
            snapshot.localLibraryCount = count
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .appLaunchPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadAppLaunchPreference(
                preferencesStore: dependencies.appLaunchPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerBehaviorPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadReaderBehaviorPreference(
                preferencesStore: dependencies.readerBehaviorPreferencesStore
            )
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
                for: .remoteBrowserPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadRemoteBrowserPreferences(
                preferencesStore: dependencies.remoteBrowserPreferencesStore
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
            snapshot.reloadRemoteCachePolicy(
                policyStore: dependencies.remoteCachePolicyStore
            )
        }
    }

    private func refresh() {
        snapshot = SettingsSnapshot.load(
            libraryCount: viewModel.items.count,
            dependencies: dependencies
        )
    }
}

struct SettingsPaneContentView: View {
    let pane: SettingsHomePane
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @ViewBuilder
    var body: some View {
        if pane == .storage {
            RemoteCacheSettingsView(dependencies: dependencies)
        } else {
            SettingsContentView(
                pane: pane,
                title: pane.title,
                viewModel: viewModel,
                dependencies: dependencies
            )
        }
    }
}

private struct SettingsContentView: View {
    @Environment(\.appNavigator) private var appNavigator

    let pane: SettingsHomePane
    let title: LocalizedStringKey
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @State private var snapshot = SettingsSnapshot.empty

    var body: some View {
        List {
            SettingsPaneSections(
                pane: pane,
                snapshot: snapshot,
                onSetAppLaunchDestination: setAppLaunchDestination,
                onSetKeepsScreenAwake: setKeepsScreenAwake,
                onOpenReaderDefaults: openReaderDefaults,
                onSetRecentWindow: setRecentWindow,
                onSetDefaultFolderImportScope: setDefaultFolderImportScope
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refresh()
        }
        .onChange(of: viewModel.items.count) { _, count in
            snapshot.localLibraryCount = count
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .appLaunchPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadAppLaunchPreference(
                preferencesStore: dependencies.appLaunchPreferencesStore
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerBehaviorPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadReaderBehaviorPreference(
                preferencesStore: dependencies.readerBehaviorPreferencesStore
            )
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
                for: .remoteBrowserPreferencesDidChange
            )
        ) { _ in
            snapshot.reloadRemoteBrowserPreferences(
                preferencesStore: dependencies.remoteBrowserPreferencesStore
            )
        }
    }

    private func setAppLaunchDestination(_ destination: AppLaunchDestination) {
        snapshot.appLaunchDestination = destination
        dependencies.appLaunchPreferencesStore.saveDestination(destination)
    }

    private func setKeepsScreenAwake(_ keepsScreenAwake: Bool) {
        snapshot.keepsScreenAwake = keepsScreenAwake
        dependencies.readerBehaviorPreferencesStore.saveKeepsScreenAwake(keepsScreenAwake)
    }

    private func openReaderDefaults() {
        appNavigator?.navigate(.settings(.readerDefaults))
    }

    private func setRecentWindow(_ option: LibraryRecentWindowOption) {
        snapshot.recentWindow = option
        dependencies.libraryPreferencesStore.saveRecentWindow(option)
    }

    private func setDefaultFolderImportScope(_ scope: RemoteDirectoryImportScope) {
        snapshot.defaultFolderImportScope = scope
        dependencies.remoteBrowserPreferencesStore.saveDefaultFolderImportScope(scope)
    }

    private func refresh() {
        snapshot = SettingsSnapshot.load(
            libraryCount: viewModel.items.count,
            dependencies: dependencies
        )
    }
}

private extension SettingsSnapshot {
    func detailText(for pane: SettingsHomePane) -> String {
        switch pane {
        case .general:
            return [
                String(localized: "Open at Launch"),
                appLaunchDestination.settingsLocalizedTitle
            ]
                .joined(separator: " · ")
        case .reading:
            return readerLayout.settingsSummary
        case .library:
            return [
                String(localized: "Recent Items"),
                recentWindow.settingsLocalizedTitle
            ]
                .joined(separator: " · ")
        case .storage:
            return [
                String(localized: "Download Limit"),
                remoteCachePolicyPreset.settingsLocalizedTitle
            ]
                .joined(separator: " · ")
        }
    }
}
