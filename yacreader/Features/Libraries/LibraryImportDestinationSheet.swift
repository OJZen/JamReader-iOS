import Combine
import SwiftUI

@MainActor
final class LibraryImportDestinationSheetViewModel: ObservableObject {
    private static let lastSelectionKey = "libraryImport.lastDestinationSelection"

    @Published private(set) var options: [LibraryImportDestinationOption] = []
    @Published private(set) var suggestedSelection: LibraryImportDestinationSelection
    @Published var alert: LibraryAlertState?

    private let importedComicsImportService: ImportedComicsImportService
    private let preferredSelection: LibraryImportDestinationSelection?
    private var hasLoaded = false

    init(
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil
    ) {
        self.importedComicsImportService = dependencies.importedComicsImportService
        self.preferredSelection = preferredSelection
        self.suggestedSelection = preferredSelection
            ?? Self.storedSelection()
            ?? .importedComics
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        load()
    }

    func load() {
        do {
            let loadedOptions = try importedComicsImportService.availableDestinationOptions()
            let availableSelections = Set(loadedOptions.map(\.selection))
            if !availableSelections.contains(suggestedSelection) {
                suggestedSelection = preferredSelection
                    .flatMap { availableSelections.contains($0) ? $0 : nil }
                    ?? .importedComics
            }

            options = sortOptions(loadedOptions, preferredSelection: suggestedSelection)
            alert = nil
        } catch {
            options = []
            alert = LibraryAlertState(
                title: "Import Destinations Unavailable",
                message: error.localizedDescription
            )
        }
    }

    func rememberSelection(_ selection: LibraryImportDestinationSelection) {
        suggestedSelection = selection
        UserDefaults.standard.set(selection.storageValue, forKey: Self.lastSelectionKey)
    }

    private func sortOptions(
        _ options: [LibraryImportDestinationOption],
        preferredSelection: LibraryImportDestinationSelection
    ) -> [LibraryImportDestinationOption] {
        options.sorted { lhs, rhs in
            if lhs.selection == preferredSelection {
                return true
            }
            if rhs.selection == preferredSelection {
                return false
            }
            if lhs.selection == .importedComics {
                return true
            }
            if rhs.selection == .importedComics {
                return false
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func storedSelection() -> LibraryImportDestinationSelection? {
        guard let rawValue = UserDefaults.standard.string(forKey: lastSelectionKey) else {
            return nil
        }

        return LibraryImportDestinationSelection(storageValue: rawValue)
    }
}

struct LibraryImportDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let confirmLabel: String
    let onSelect: (LibraryImportDestinationSelection) -> Void

    @StateObject private var viewModel: LibraryImportDestinationSheetViewModel

    init(
        title: String,
        message: String,
        confirmLabel: String = "Use This Library",
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil,
        onSelect: @escaping (LibraryImportDestinationSelection) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.onSelect = onSelect
        _viewModel = StateObject(
            wrappedValue: LibraryImportDestinationSheetViewModel(
                dependencies: dependencies,
                preferredSelection: preferredSelection
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
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

                Section {
                    ForEach(viewModel.options) { option in
                        Button {
                            viewModel.rememberSelection(option.selection)
                            dismiss()
                            onSelect(option.selection)
                        } label: {
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
                                    if option.selection == viewModel.suggestedSelection {
                                        Text("Suggested")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.12), in: Capsule())
                                    }

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(confirmLabel)
                    }
                } header: {
                    Text("Choose Destination")
                } footer: {
                    Text("Imported files are copied into the selected library folder and then indexed automatically.")
                }
            }
            .navigationTitle("Import Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadIfNeeded()
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}
