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

    var body: some View {
        NavigationStack {
            Form {
                Section("Overview") {
                    LabeledContent("Name", value: item.descriptor.name)
                    LabeledContent("Type", value: item.descriptor.kind.title)
                    LabeledContent(
                        "Updated",
                        value: item.descriptor.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Section("Access") {
                    LabeledContent("Source", value: item.accessSnapshot.sourceStatus)
                    LabeledContent("Source Write", value: item.accessSnapshot.writeStatus)
                    LabeledContent("Local State", value: item.accessSnapshot.database.summaryLine)
                    LabeledContent("Assets", value: item.accessSnapshot.metadataExists ? "Ready" : "Empty")
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

                Section("Files") {
                    LabeledContent("Source Folder", value: item.descriptor.sourcePath)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .adaptiveFormSheet(720)
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
