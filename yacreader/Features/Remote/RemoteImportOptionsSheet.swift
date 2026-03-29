import SwiftUI

enum RemoteDirectoryImportScope: String, CaseIterable, Hashable, Identifiable {
    case visibleResults
    case currentFolderOnly
    case includeSubfolders

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .visibleResults:
            return "Visible Comics Only"
        case .currentFolderOnly:
            return "This Folder Only"
        case .includeSubfolders:
            return "Include Subfolders"
        }
    }

    var summaryText: String {
        switch self {
        case .visibleResults:
            return "Import only the comic files currently visible in this remote browser, including search results."
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
    let supplementaryNotice: String?
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
        supplementaryNotice: String? = nil,
        confirmLabel: String = "Import",
        availableScopes: [RemoteDirectoryImportScope] = RemoteDirectoryImportScope.allCases,
        defaultScope: RemoteDirectoryImportScope = .includeSubfolders,
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil,
        onConfirm: @escaping (LibraryImportDestinationSelection, RemoteDirectoryImportScope) -> Void
    ) {
        self.title = title
        self.message = message
        self.supplementaryNotice = supplementaryNotice
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
                    .disabled(!isSelectedDestinationSelectable)
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
            ImportSheetContextRow(title: title)
        } footer: {
            Text(introductionFooterText)
        }
    }

    private var scopeSection: some View {
        Section {
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
        } header: {
            Text("Choose Scope")
        } footer: {
            Text(selectedScope.summaryText)
        }
    }

    private var destinationSection: some View {
        Section {
            ForEach(destinationViewModel.options) { option in
                Button {
                    guard option.isSelectable else {
                        return
                    }
                    selectedDestination = option.selection
                } label: {
                    LibraryImportDestinationOptionRow(
                        option: option,
                        isSuggested: option.selection == destinationViewModel.suggestedSelection,
                        isSelected: selectedDestination == option.selection,
                        showsSelectionIndicator: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(!option.isSelectable)
            }
        } header: {
            Text("Choose Destination")
        } footer: {
            Text(ImportDestinationSheetCopy.destinationFooter)
        }
    }

    private func applySuggestedDestinationIfNeeded() {
        guard !hasAppliedSuggestedDestination else {
            return
        }

        hasAppliedSuggestedDestination = true
        selectedDestination = destinationViewModel.suggestedSelection
    }

    private var isSelectedDestinationSelectable: Bool {
        destinationViewModel.options.contains {
            $0.selection == selectedDestination && $0.isSelectable
        }
    }

    private var introductionFooterText: String {
        [message, supplementaryNotice]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n\n")
    }
}

private struct RemoteImportScopeRow: View {
    let scope: RemoteDirectoryImportScope
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(scope.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
