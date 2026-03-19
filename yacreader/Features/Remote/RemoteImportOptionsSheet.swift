import SwiftUI

enum RemoteDirectoryImportScope: String, CaseIterable, Hashable, Identifiable {
    case currentFolderOnly
    case includeSubfolders

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .currentFolderOnly:
            return "This Folder Only"
        case .includeSubfolders:
            return "Include Subfolders"
        }
    }

    var subtitle: String {
        switch self {
        case .currentFolderOnly:
            return "Import only the supported comics that are directly inside this folder."
        case .includeSubfolders:
            return "Recursively import supported comics from this folder and every nested subfolder."
        }
    }
}

struct RemoteImportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let confirmLabel: String
    let availableScopes: [RemoteDirectoryImportScope]
    let defaultScope: RemoteDirectoryImportScope
    let onConfirm: (LibraryImportDestinationSelection, RemoteDirectoryImportScope) -> Void

    @StateObject private var destinationViewModel: LibraryImportDestinationSheetViewModel
    @State private var selectedScope: RemoteDirectoryImportScope
    @State private var selectedDestination: LibraryImportDestinationSelection
    @State private var hasAppliedSuggestedDestination = false

    init(
        title: String,
        message: String,
        confirmLabel: String = "Import",
        availableScopes: [RemoteDirectoryImportScope] = RemoteDirectoryImportScope.allCases,
        defaultScope: RemoteDirectoryImportScope = .includeSubfolders,
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil,
        onConfirm: @escaping (LibraryImportDestinationSelection, RemoteDirectoryImportScope) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.availableScopes = availableScopes
        self.defaultScope = availableScopes.contains(defaultScope)
            ? defaultScope
            : (availableScopes.first ?? .includeSubfolders)
        self.onConfirm = onConfirm
        let initialDestination = preferredSelection ?? .importedComics
        _selectedScope = State(initialValue: availableScopes.contains(defaultScope) ? defaultScope : (availableScopes.first ?? .includeSubfolders))
        _selectedDestination = State(initialValue: initialDestination)
        _destinationViewModel = StateObject(
            wrappedValue: LibraryImportDestinationSheetViewModel(
                dependencies: dependencies,
                preferredSelection: preferredSelection
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                introductionSection
                scopeSection
                destinationSection
            }
            .navigationTitle("Import Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(confirmLabel) {
                        destinationViewModel.rememberSelection(selectedDestination)
                        let selectedScope = selectedScope
                        let selectedDestination = selectedDestination
                        dismiss()
                        onConfirm(selectedDestination, selectedScope)
                    }
                    .fontWeight(.semibold)
                    .disabled(destinationViewModel.options.isEmpty)
                }
            }
            .onAppear {
                destinationViewModel.loadIfNeeded()
                applySuggestedDestinationIfNeeded()
            }
            .onChange(of: destinationViewModel.options) { _, _ in
                applySuggestedDestinationIfNeeded()
            }
            .alert(item: $destinationViewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var introductionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var scopeSection: some View {
        Section("Choose Scope") {
            ForEach(availableScopes) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    RemoteImportScopeRow(
                        scope: scope,
                        isSelected: selectedScope == scope
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var destinationSection: some View {
        Section {
            ForEach(destinationViewModel.options) { option in
                Button {
                    selectedDestination = option.selection
                } label: {
                    RemoteImportDestinationRow(
                        option: option,
                        isSuggested: option.selection == destinationViewModel.suggestedSelection,
                        isSelected: selectedDestination == option.selection
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Choose Destination")
        } footer: {
            Text("Imported files are copied into the selected library folder and then indexed automatically.")
        }
    }

    private func applySuggestedDestinationIfNeeded() {
        guard !hasAppliedSuggestedDestination else {
            return
        }

        hasAppliedSuggestedDestination = true
        selectedDestination = destinationViewModel.suggestedSelection
    }
}

private struct RemoteImportScopeRow: View {
    let scope: RemoteDirectoryImportScope
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scope.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(scope.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RemoteImportDestinationRow: View {
    let option: LibraryImportDestinationOption
    let isSuggested: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(option.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let detail = option.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if isSuggested {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
