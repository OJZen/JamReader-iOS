import SwiftUI

/// What a remote import copies, as shown at the top of the import sheet.
struct RemoteImportSource {
    let title: String
    /// "Server › Folder › …", ending with the source itself.
    let location: String
    let isFolder: Bool
    /// Comics directly in the source when known. Subfolders are only listed
    /// once the import starts, so their count is never shown up front.
    let directComicCount: Int?
}

/// "Import to Library": the source, whether subfolders come along, the target
/// library, where the comics end up, and a button that names the count.
struct RemoteImportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let source: RemoteImportSource
    let availableScopes: [RemoteDirectoryImportScope]
    let onConfirm: (LibraryImportDestinationSelection, RemoteDirectoryImportScope) -> Void

    @StateObject private var destinationViewModel: LibraryImportDestinationSheetViewModel
    @State private var selectedScope: RemoteDirectoryImportScope
    @State private var selectedDestination: LibraryImportDestinationSelection
    @State private var hasAppliedSuggestedDestination = false

    init(
        source: RemoteImportSource,
        availableScopes: [RemoteDirectoryImportScope],
        defaultScope: RemoteDirectoryImportScope,
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil,
        onConfirm: @escaping (LibraryImportDestinationSelection, RemoteDirectoryImportScope) -> Void
    ) {
        self.source = source
        self.availableScopes = availableScopes
        self.onConfirm = onConfirm
        let resolvedDefaultScope = availableScopes.contains(defaultScope)
            ? defaultScope
            : (availableScopes.first ?? .currentFolderOnly)
        _selectedScope = State(initialValue: resolvedDefaultScope)
        _selectedDestination = State(initialValue: preferredSelection ?? .importedComics)
        _destinationViewModel = StateObject(
            wrappedValue: LibraryImportDestinationSheetViewModel(
                dependencies: dependencies,
                preferredSelection: preferredSelection
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                destinationSection
            }
            .navigationTitle("Import to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
            .safeAreaInset(edge: .bottom) {
                confirmButton
            }
        }
        .adaptiveFormSheet(720)
        .presentationDragIndicator(.visible)
    }

    private var sourceSection: some View {
        Section("Source") {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(source.title)
                        .foregroundStyle(Color.textPrimary)
                    Text(source.location)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                }
            } icon: {
                Image(systemName: source.isFolder ? "folder.fill" : "doc.fill")
                    .foregroundStyle(Color.appAccent)
            }
            .accessibilityElement(children: .combine)

            if offersSubfolderChoice {
                Toggle(isOn: includesSubfoldersBinding) {
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text("Include Subfolders")
                        Text(scopeSummary)
                            .font(AppFont.footnote())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    private var destinationSection: some View {
        Section {
            Picker(selection: $selectedDestination) {
                ForEach(selectableOptions) { option in
                    Text(option.title)
                        .tag(option.selection)
                }
            } label: {
                Label("Library", systemImage: "books.vertical")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Destination")
        } footer: {
            Text(destinationFooter)
        }
    }

    private var confirmButton: some View {
        Button {
            destinationViewModel.rememberSelection(selectedDestination)
            let selectedScope = selectedScope
            let selectedDestination = selectedDestination
            dismiss()
            onConfirm(selectedDestination, selectedScope)
        } label: {
            Text(confirmTitle)
                .font(AppFont.body(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.appJam)
        .disabled(!isSelectedDestinationSelectable)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var offersSubfolderChoice: Bool {
        availableScopes.contains(.currentFolderOnly) && availableScopes.contains(.includeSubfolders)
    }

    private var includesSubfoldersBinding: Binding<Bool> {
        Binding(
            get: { selectedScope == .includeSubfolders },
            set: { selectedScope = $0 ? .includeSubfolders : .currentFolderOnly }
        )
    }

    private var scopeSummary: String {
        if selectedScope == .includeSubfolders {
            return String(localized: "Comics in this folder and all of its subfolders")
        }
        if let count = source.directComicCount {
            return String(localized: "Only the \(count) comics directly in this folder")
        }
        return String(localized: "Only comics directly in this folder")
    }

    /// Subfolders are listed when the import starts, so only a known direct
    /// count is written on the button.
    private var confirmTitle: String {
        guard source.isFolder else {
            return String(localized: "Import Comic")
        }
        guard selectedScope != .includeSubfolders, let count = source.directComicCount, count > 0 else {
            return String(localized: "Start Import")
        }
        return String(localized: "Import \(count) Comics")
    }

    private var destinationFooter: String {
        let libraryName = selectableOptions.first { $0.selection == selectedDestination }?.title
            ?? String(localized: "Imported Comics")
        return String(
            localized: "Comics download first, then are added to “\(libraryName)”. Offline copies and remote reading progress don’t move with them."
        )
    }

    private var selectableOptions: [LibraryImportDestinationOption] {
        destinationViewModel.options.filter(\.isSelectable)
    }

    private var isSelectedDestinationSelectable: Bool {
        selectableOptions.contains { $0.selection == selectedDestination }
    }

    private func applySuggestedDestinationIfNeeded() {
        guard !hasAppliedSuggestedDestination else {
            return
        }

        hasAppliedSuggestedDestination = true
        selectedDestination = destinationViewModel.suggestedSelection
    }
}
