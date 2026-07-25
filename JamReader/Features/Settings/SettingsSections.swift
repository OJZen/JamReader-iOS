import SwiftUI

struct SettingsPaneSections: View {
    let pane: SettingsHomePane
    let snapshot: SettingsSnapshot
    let onOpenReaderDefaults: (ReaderDefaultProfile) -> Void
    let onSetRecentWindow: (LibraryRecentWindowOption) -> Void
    let onOpenCacheManagement: () -> Void

    @ViewBuilder
    var body: some View {
        switch pane {
        case .overview:
            SettingsOverviewSummarySection(snapshot: snapshot)
            ReadingDefaultsSettingsSection(
                snapshot: snapshot,
                onOpenReaderDefaults: onOpenReaderDefaults
            )
            LibraryPreferencesSettingsSection(
                snapshot: snapshot,
                onSetRecentWindow: onSetRecentWindow
            )
            StorageSettingsSection(
                snapshot: snapshot,
                showsBreakdown: false,
                onOpenCacheManagement: onOpenCacheManagement
            )
            AboutSettingsSection(snapshot: snapshot)
        case .reading:
            ReadingDefaultsSettingsSection(
                snapshot: snapshot,
                onOpenReaderDefaults: onOpenReaderDefaults
            )
        case .library:
            LibraryPreferencesSettingsSection(
                snapshot: snapshot,
                onSetRecentWindow: onSetRecentWindow
            )
        case .storage:
            StorageSettingsSection(
                snapshot: snapshot,
                showsBreakdown: true,
                onOpenCacheManagement: onOpenCacheManagement
            )
        case .about:
            AboutSettingsSection(snapshot: snapshot)
        }
    }
}

private struct SettingsOverviewSummarySection: View {
    let snapshot: SettingsSnapshot

    var body: some View {
        Section("At a Glance") {
            SettingsSummaryGrid(
                metrics: [
                    SettingsSummaryMetric(
                        title: "Reading Defaults",
                        value: String(localized: "3 Profiles"),
                        systemImage: "book.closed.fill",
                        tint: .blue
                    ),
                    SettingsSummaryMetric(
                        title: "Recent Items",
                        value: snapshot.recentWindow.title,
                        systemImage: "clock.fill",
                        tint: .purple
                    ),
                    SettingsSummaryMetric(
                        title: "Download Limit",
                        value: snapshot.remoteCachePolicyPreset.title,
                        systemImage: "arrow.down.circle.fill",
                        tint: .teal
                    ),
                    SettingsSummaryMetric(
                        title: "On Device",
                        value: snapshot.managedStorageText,
                        systemImage: "internaldrive.fill",
                        tint: .orange
                    )
                ]
            )
        }
    }
}

private struct ReadingDefaultsSettingsSection: View {
    let snapshot: SettingsSnapshot
    let onOpenReaderDefaults: (ReaderDefaultProfile) -> Void

    var body: some View {
        Section {
            ForEach(ReaderDefaultProfile.allCases) { profile in
                Button {
                    onOpenReaderDefaults(profile)
                } label: {
                    SettingsNavigationRow(
                        systemImage: profile.systemImage,
                        tint: profile.tint,
                        title: profile.title,
                        detail: profile.summary(
                            for: snapshot.layout(for: profile)
                        )
                    )
                }
                .buttonStyle(.plain)
                .pointerHoverEffect()
                .accessibilityHint("Opens reading defaults")
            }
        } header: {
            Text("Reading")
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

private struct StorageSettingsSection: View {
    let snapshot: SettingsSnapshot
    let showsBreakdown: Bool
    let onOpenCacheManagement: () -> Void

    var body: some View {
        Section {
            Button(action: onOpenCacheManagement) {
                SettingsNavigationRow(
                    systemImage: "internaldrive.fill",
                    tint: .orange,
                    title: String(localized: "Manage Downloads & Cache"),
                    detail: nil,
                    value: snapshot.managedStorageText
                )
            }
            .buttonStyle(.plain)
            .pointerHoverEffect()

            LabeledContent("Download Limit") {
                Text(snapshot.remoteCachePolicyPreset.title)
                    .foregroundStyle(Color.textSecondary)
            }

            if showsBreakdown {
                storageValueRow(
                    title: String(localized: "Downloaded Copies"),
                    value: snapshot.remoteCacheSummary.hasCachedComics
                        ? snapshot.remoteCacheSummary.summaryText
                        : String(localized: "None")
                )

                if snapshot.remoteCacheSummary.hasOtherCacheData {
                    storageValueRow(
                        title: String(localized: "Temporary Cache"),
                        value: snapshot.remoteCacheSummary.otherCacheSizeText
                    )
                }

                storageValueRow(
                    title: String(localized: "Cover Thumbnails"),
                    value: snapshot.remoteThumbnailCacheSummary.isEmpty
                        ? String(localized: "None")
                        : snapshot.remoteThumbnailCacheSummary.summaryText
                )

                storageValueRow(
                    title: String(localized: "Imported Comics"),
                    value: snapshot.importedComicsLibrarySummary.isEmpty
                        ? String(localized: "None")
                        : snapshot.importedComicsLibrarySummary.summaryText
                )
            }
        } header: {
            Text("Storage")
        }
    }

    private func storageValueRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.trailing)
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

            LabeledContent {
                Text("\(snapshot.localLibraryCount)")
                    .foregroundStyle(Color.textSecondary)
            } label: {
                Label {
                    Text("Local Libraries")
                } icon: {
                    SettingsIcon(
                        systemName: "books.vertical.fill",
                        color: .appAccent
                    )
                }
            }
        }
    }
}
