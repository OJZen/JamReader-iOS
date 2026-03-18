import SwiftUI

struct LibraryOrganizationCollectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let collection: LibraryOrganizationCollection
    let onSave: (String, LibraryLabelColor?) -> Bool

    @State private var proposedName: String
    @State private var selectedLabelColor: LibraryLabelColor
    @FocusState private var isNameFieldFocused: Bool

    init(
        collection: LibraryOrganizationCollection,
        onSave: @escaping (String, LibraryLabelColor?) -> Bool
    ) {
        self.collection = collection
        self.onSave = onSave
        _proposedName = State(initialValue: collection.displayTitle)
        _selectedLabelColor = State(initialValue: collection.labelColor ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(namePrompt, text: $proposedName)
                        .focused($isNameFieldFocused)
                }

                if collection.type == .label {
                    Section("Color") {
                        Picker("Color", selection: $selectedLabelColor) {
                            ForEach(LibraryLabelColor.allCases) { color in
                                HStack {
                                    Circle()
                                        .fill(color.swiftUIColor)
                                        .frame(width: 12, height: 12)
                                    Text(color.displayName)
                                }
                                .tag(color)
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(
                            proposedName,
                            collection.type == .label ? selectedLabelColor : nil
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private var navigationTitle: String {
        switch collection.type {
        case .label:
            return "Edit Tag"
        case .readingList:
            return "Edit Reading List"
        }
    }

    private var namePrompt: String {
        switch collection.type {
        case .label:
            return "Tag name"
        case .readingList:
            return "Reading list name"
        }
    }
}
