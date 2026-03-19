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
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.descriptor.name)
                            .font(.headline)

                        Text(item.descriptor.sourcePath)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            StatusBadge(
                                title: item.descriptor.storageMode.title,
                                tint: item.descriptor.storageMode.tintColor
                            )
                            StatusBadge(
                                title: item.accessSnapshot.sourceExists ? "Ready" : "Needs Access",
                                tint: item.accessSnapshot.sourceExists ? .green : .orange
                            )
                        }
                    }
                    .padding(.vertical, 6)
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

                    Text("This only removes the library from the app registry. Source files and metadata stay on disk.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                Section("Name") {
                    TextField("Library name", text: $proposedName)
                        .focused($isFocused)

                    Text("This only changes the display name used inside the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Name", value: item.descriptor.name)
                    LabeledContent("Storage", value: item.descriptor.storageMode.title)
                    LabeledContent("Created", value: item.descriptor.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: item.descriptor.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section("Access") {
                    LabeledContent("Source", value: item.accessSnapshot.sourceStatus)
                    LabeledContent("Write Access", value: item.accessSnapshot.writeStatus)
                    LabeledContent("Direct Imports", value: libraryImportCompatibilityTitle)
                    LabeledContent("Metadata", value: item.accessSnapshot.metadataExists ? "Ready" : "Missing")
                    LabeledContent("Database", value: item.accessSnapshot.database.summaryLine)
                }

                if let libraryImportCompatibilityDetail {
                    Section("Compatibility") {
                        Text(libraryImportCompatibilityDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(item.descriptor.sourcePath)
                        .textSelection(.enabled)

                    Text(item.metadataPath)
                        .textSelection(.enabled)

                    Text(item.databasePath)
                        .textSelection(.enabled)
                } header: {
                    Text("Paths")
                } footer: {
                    Text("Paths are shown for inspection only. Removing a library from the app does not delete these files.")
                }
            }
            .navigationTitle("Library Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var libraryImportCompatibilityTitle: String {
        if item.descriptor.storageMode == .mirrored {
            return "Browse Only"
        }

        return item.accessSnapshot.sourceWritable ? "Allowed" : "Unavailable"
    }

    private var libraryImportCompatibilityDetail: String? {
        if item.descriptor.storageMode == .mirrored {
            return "This library is being kept compatible with a desktop or external source. It remains available for browsing, search, reading, and metadata compatibility, but direct file imports are disabled to avoid writing into a mirrored library."
        }

        if !item.accessSnapshot.sourceWritable {
            return "This library is currently readable but not writable from iOS, so direct file imports are disabled until write access is available again."
        }

        return nil
    }
}

struct LibraryHomeQuickActionButton: View {
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if prominent {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library Actions")
    }
}
