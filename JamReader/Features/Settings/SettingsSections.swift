import SwiftUI

struct SettingsPaneSections: View {
    let pane: SettingsHomePane
    let snapshot: SettingsSnapshot
    let onSetAppLaunchDestination: (AppLaunchDestination) -> Void
    let onSetKeepsScreenAwake: (Bool) -> Void
    let onOpenReaderDefaults: () -> Void
    let onSetRecentWindow: (LibraryRecentWindowOption) -> Void
    let onSetDefaultFolderImportScope: (RemoteDirectoryImportScope) -> Void

    @ViewBuilder
    var body: some View {
        switch pane {
        case .general:
            GeneralSettingsSection(
                snapshot: snapshot,
                onSetAppLaunchDestination: onSetAppLaunchDestination
            )
        case .reading:
            ReadingBehaviorSettingsSection(
                snapshot: snapshot,
                onSetKeepsScreenAwake: onSetKeepsScreenAwake
            )
            ReadingDefaultsSettingsSection(
                snapshot: snapshot,
                onOpenReaderDefaults: onOpenReaderDefaults
            )
        case .library:
            LibraryPreferencesSettingsSection(
                snapshot: snapshot,
                onSetRecentWindow: onSetRecentWindow
            )
            RemoteImportPreferencesSettingsSection(
                snapshot: snapshot,
                onSetDefaultFolderImportScope: onSetDefaultFolderImportScope
            )
        case .storage:
            EmptyView()
        }
    }
}

private struct GeneralSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onSetAppLaunchDestination: (AppLaunchDestination) -> Void

    private var launchDestinationBinding: Binding<AppLaunchDestination> {
        Binding(
            get: { snapshot.appLaunchDestination },
            set: onSetAppLaunchDestination
        )
    }

    var body: some View {
        Section("Startup") {
            Picker("Open at Launch", selection: launchDestinationBinding) {
                ForEach(AppLaunchDestination.allCases) { destination in
                    Text(destination.settingsLocalizedTitle).tag(destination)
                }
            }
        }

        AboutSettingsSection(snapshot: snapshot)
    }
}

private struct ReadingBehaviorSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onSetKeepsScreenAwake: (Bool) -> Void

    private var keepsScreenAwakeBinding: Binding<Bool> {
        Binding(
            get: { snapshot.keepsScreenAwake },
            set: onSetKeepsScreenAwake
        )
    }

    var body: some View {
        Section {
            Toggle("Keep Screen Awake", isOn: keepsScreenAwakeBinding)
        } header: {
            Text("Display")
        } footer: {
            Text("Prevents automatic locking only while a comic is open and visible.")
        }
    }
}

private struct ReadingDefaultsSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onOpenReaderDefaults: () -> Void

    var body: some View {
        Section {
            Button(action: onOpenReaderDefaults) {
                SettingsNavigationRow(
                    systemImage: "book.closed.fill",
                    tint: .blue,
                    title: String(localized: "Reading Defaults"),
                    detail: snapshot.readerLayout.settingsSummary
                )
            }
            .buttonStyle(.plain)
            .pointerHoverEffect()
            .accessibilityHint("Opens reading defaults")
        } header: {
            Text("Reader")
        } footer: {
            Text("These defaults apply to every comic opened in the reader.")
        }
    }
}

private struct RemoteImportPreferencesSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onSetDefaultFolderImportScope: (RemoteDirectoryImportScope) -> Void

    private var importScopeBinding: Binding<RemoteDirectoryImportScope> {
        Binding(
            get: { snapshot.defaultFolderImportScope },
            set: onSetDefaultFolderImportScope
        )
    }

    var body: some View {
        Section {
            Picker("Default Folder Import Scope", selection: importScopeBinding) {
                Text(RemoteDirectoryImportScope.currentFolderOnly.title)
                    .tag(RemoteDirectoryImportScope.currentFolderOnly)
                Text(RemoteDirectoryImportScope.includeSubfolders.title)
                    .tag(RemoteDirectoryImportScope.includeSubfolders)
            }
        } header: {
            Text("Remote Import")
        } footer: {
            Text("Preselected when importing a remote folder. You can still change it before importing.")
        }
    }
}

private struct LibraryPreferencesSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onSetRecentWindow: (LibraryRecentWindowOption) -> Void

    private var recentWindowBinding: Binding<LibraryRecentWindowOption> {
        Binding(
            get: { snapshot.recentWindow },
            set: onSetRecentWindow
        )
    }

    var body: some View {
        Section {
            Picker("Recent Items", selection: recentWindowBinding) {
                ForEach(LibraryRecentWindowOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            LabeledContent("Local Libraries") {
                Text("\(snapshot.localLibraryCount)")
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text("Library")
        }
    }
}

private struct AboutSettingsSection: View {
    let snapshot: SettingsSnapshot

    var body: some View {
        Section("About") {
            LabeledContent {
                Text(snapshot.appVersion)
                    .foregroundStyle(Color.textSecondary)
            } label: {
                Label {
                    Text("Version")
                } icon: {
                    SettingsIcon(
                        systemName: "info.circle.fill",
                        color: .gray
                    )
                }
            }
        }
    }
}
