import SwiftUI

struct LibraryHomeLibraryActionsSheet: View {
    let item: LibraryListItem
    let onDone: () -> Void
    let onRename: () -> Void
    let onViewInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Library", value: item.descriptor.name)
                }

                Section("Manage") {
                    Button(action: onRename) {
                        Label("Rename Library", systemImage: "pencil")
                    }

                    Button(action: onViewInfo) {
                        Label("Details", systemImage: "info.circle")
                    }
                }

                Section {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove from App", systemImage: "trash")
                    }
                } footer: {
                    Text("Removes the library from the app. Files stay on disk.")
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .adaptiveSheetWidth(620)
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
                    Text("Only changes the name in the app.")
                }
            }
            .navigationTitle("Rename")
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
        .adaptiveSheetWidth(520)
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
                Section("Overview") {
                    LabeledContent("Name", value: item.descriptor.name)
                    LabeledContent("Storage", value: item.descriptor.storageMode.title)
                    LabeledContent(
                        "Updated",
                        value: item.descriptor.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Section("Access") {
                    LabeledContent("Source", value: item.accessSnapshot.sourceStatus)
                    LabeledContent("Write", value: item.accessSnapshot.writeStatus)

                    if !item.accessSnapshot.metadataExists {
                        LabeledContent("Metadata", value: "Missing")
                    }

                    LabeledContent("Database", value: item.accessSnapshot.database.summaryLine)
                }

                if let maintenanceRecord = item.maintenanceRecord {
                    Section {
                        LabeledContent("Last Action", value: maintenanceRecord.title)
                        LabeledContent("When", value: maintenanceRecord.formattedTimestampLine)
                    } header: {
                        Text("Maintenance")
                    } footer: {
                        let detailText = maintenanceRecord.detailLine ?? maintenanceRecord.summary.summaryLine
                        if !detailText.isEmpty {
                            Text(detailText)
                        }
                    }
                }

                if compatibilityPresentation.directImportsTitle != "Allowed"
                    || compatibilityPresentation.infoDetail != nil
                    || compatibilityPresentation.badgeTitle != nil {
                    Section {
                        LabeledContent("Status", value: compatibilityPresentation.directImportsTitle)

                        if let badgeTitle = compatibilityPresentation.badgeTitle {
                            LabeledContent("Mode", value: badgeTitle)
                        }
                    } header: {
                        Text("Imports")
                    } footer: {
                        if let libraryImportCompatibilityDetail = compatibilityPresentation.infoDetail {
                            Text(libraryImportCompatibilityDetail)
                        }
                    }
                }

                Section("Files") {
                    LabeledContent("Source", value: item.descriptor.sourcePath)
                    LabeledContent("Metadata", value: item.metadataPath)
                    LabeledContent("Database", value: item.databasePath)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .adaptiveSheetWidth(720)
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
