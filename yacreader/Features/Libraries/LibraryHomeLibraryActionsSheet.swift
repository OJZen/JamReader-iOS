import SwiftUI

struct LibraryHomeLibraryActionsSheet: View {
    let item: LibraryListItem
    let onDone: () -> Void
    let onRename: () -> Void
    let onViewInfo: () -> Void
    let onRemove: () -> Void

    private var compatibilityPresentation: LibraryCompatibilityPresentation {
        LibraryCompatibilityPresentation.resolve(
            descriptor: item.descriptor,
            accessSnapshot: item.accessSnapshot
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.descriptor.name)
                        .font(.headline)

                    AdaptiveStatusBadgeGroup(badges: actionSummaryBadges)

                    FormOverviewContent(items: actionSummaryItems)
                }

                Section("Manage") {
                    Button(action: onRename) {
                        Label("Rename Library", systemImage: "pencil")
                    }

                    Button(action: onViewInfo) {
                        Label("Library Info", systemImage: "info.circle")
                    }
                }

                Section {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove from App", systemImage: "trash")
                    }
                } footer: {
                    Text("Removing a library only removes it from the app. Files and metadata stay on disk.")
                }
            }
            .navigationTitle("Library Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct LibraryRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: LibraryListItem
    let onSave: (String) -> Bool

    @State private var proposedName: String
    @FocusState private var isFocused: Bool

    init(item: LibraryListItem, onSave: @escaping (String) -> Bool) {
        self.item = item
        self.onSave = onSave
        _proposedName = State(initialValue: item.descriptor.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Library name", text: $proposedName)
                        .focused($isFocused)
                } header: {
                    Text("Name")
                } footer: {
                    Text("This only changes the display name used in the app.")
                }
            }
            .navigationTitle("Rename Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(proposedName) {
                            dismiss()
                        }
                    }
                    .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }
}

struct LibraryInfoSheet: View {
    let item: LibraryListItem

    private var compatibilityPresentation: LibraryCompatibilityPresentation {
        LibraryCompatibilityPresentation.resolve(
            descriptor: item.descriptor,
            accessSnapshot: item.accessSnapshot
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.descriptor.name)
                        .font(.headline)

                    AdaptiveStatusBadgeGroup(badges: infoSummaryBadges)

                    FormOverviewContent(items: libraryOverviewItems)
                }

                Section("Access") {
                    LabeledContent("Source", value: item.accessSnapshot.sourceStatus)
                    LabeledContent("Write Access", value: item.accessSnapshot.writeStatus)
                    LabeledContent("Metadata", value: item.accessSnapshot.metadataExists ? "Ready" : "Missing")
                    LabeledContent("Database", value: item.accessSnapshot.database.summaryLine)
                }

                if let maintenanceRecord = item.maintenanceRecord {
                    Section {
                        LabeledContent("Last Action", value: maintenanceRecord.title)
                        LabeledContent("Summary", value: maintenanceRecord.summary.summaryLine)
                        LabeledContent("When", value: maintenanceRecord.formattedTimestampLine)
                    } header: {
                        Text("Maintenance")
                    } footer: {
                        if let detailLine = maintenanceRecord.detailLine {
                            Text(detailLine)
                        }
                    }
                }

                if compatibilityPresentation.directImportsTitle != "Allowed"
                    || compatibilityPresentation.infoDetail != nil
                    || compatibilityPresentation.badgeTitle != nil {
                    Section {
                        LabeledContent("Direct Imports", value: compatibilityPresentation.directImportsTitle)

                        if let badgeTitle = compatibilityPresentation.badgeTitle {
                            LabeledContent("Mode", value: badgeTitle)
                        }
                    } header: {
                        Text("Compatibility")
                    } footer: {
                        if let libraryImportCompatibilityDetail = compatibilityPresentation.infoDetail {
                            Text(libraryImportCompatibilityDetail)
                        }
                    }
                }

                Section {
                    FormOverviewContent(items: pathOverviewItems)
                } header: {
                    Text("Paths")
                } footer: {
                    Text("Paths are shown for inspection only. Removing a library does not delete them.")
                }
            }
            .navigationTitle("Library Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct LibraryHomeQuickActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library Actions")
    }
}

private extension LibraryHomeLibraryActionsSheet {
    var actionSummaryBadges: [StatusBadgeItem] {
        item.libraryActionBadges(compatibilityPresentation: compatibilityPresentation)
    }

    var actionSummaryItems: [FormOverviewItem] {
        item.libraryActionOverviewItems
    }
}

private extension LibraryInfoSheet {
    var infoSummaryBadges: [StatusBadgeItem] {
        item.libraryActionBadges(compatibilityPresentation: compatibilityPresentation)
    }

    var libraryOverviewItems: [FormOverviewItem] {
        [
            FormOverviewItem(title: "Storage", value: item.descriptor.storageMode.title),
            FormOverviewItem(
                title: "Created",
                value: item.descriptor.createdAt.formatted(date: .abbreviated, time: .shortened)
            ),
            FormOverviewItem(
                title: "Updated",
                value: item.descriptor.updatedAt.formatted(date: .abbreviated, time: .shortened)
            )
        ]
    }

    var pathOverviewItems: [FormOverviewItem] {
        [
            FormOverviewItem(title: "Source", value: item.descriptor.sourcePath),
            FormOverviewItem(title: "Metadata", value: item.metadataPath),
            FormOverviewItem(title: "Database", value: item.databasePath)
        ]
    }
}

private extension LibraryListItem {
    func libraryActionBadges(
        compatibilityPresentation: LibraryCompatibilityPresentation
    ) -> [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: descriptor.storageMode.title,
                tint: descriptor.storageMode.tintColor
            ),
            StatusBadgeItem(
                title: accessSnapshot.sourceExists ? "Ready" : "Needs Access",
                tint: accessSnapshot.sourceExists ? .green : .orange
            )
        ]

        if let compatibilityBadgeTitle = compatibilityPresentation.badgeTitle,
           let tint = compatibilityPresentation.tint {
            badges.append(StatusBadgeItem(title: compatibilityBadgeTitle, tint: tint))
        } else if compatibilityPresentation.directImportsTitle != "Allowed",
                  let tint = compatibilityPresentation.tint {
            badges.append(
                StatusBadgeItem(
                    title: compatibilityPresentation.directImportsTitle,
                    tint: tint
                )
            )
        }

        return badges
    }

    var libraryActionOverviewItems: [FormOverviewItem] {
        var items = [
            FormOverviewItem(title: "Location", value: descriptor.sourcePath),
            FormOverviewItem(title: "Database", value: accessSnapshot.database.summaryLine)
        ]

        if let maintenanceRecord {
            items.append(
                FormOverviewItem(
                    title: "Last Action",
                    value: maintenanceRecord.formattedTimestampLine
                )
            )
        }

        return items
    }
}
