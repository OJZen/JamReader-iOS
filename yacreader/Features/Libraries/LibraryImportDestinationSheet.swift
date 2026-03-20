import Combine
import SwiftUI

enum ImportDestinationSheetCopy {
    static let destinationFooter = "Files are copied into the selected library and indexed automatically. Mirrored or read-only libraries stay browse-only."
}

struct ImportSheetContextRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.vertical, 4)
    }
}

struct LibraryImportDestinationOptionRow: View {
    let option: LibraryImportDestinationOption
    var isSuggested = false
    var isSelected = false
    var showsSelectionIndicator = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !badges.isEmpty {
                    AdaptiveStatusBadgeGroup(
                        badges: badges,
                        horizontalSpacing: 6,
                        verticalSpacing: 6
                    )
                }

                if let detail = option.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if case .unavailable(let reason) = option.availability {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if showsSelectionIndicator && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(option.isSelectable ? .blue : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var badges: [StatusBadgeItem] {
        var items: [StatusBadgeItem] = []

        if let status = option.status {
            items.append(StatusBadgeItem(title: status.title, tint: status.tintColor))
        }

        if isSuggested {
            items.append(StatusBadgeItem(title: "Suggested", tint: .blue))
        }

        return items
    }
}

private extension LibraryImportDestinationOption.Status {
    var tintColor: Color {
        switch self {
        case .managed:
            return .blue
        case .browseOnly:
            return .blue
        case .readOnly:
            return .orange
        }
    }
}

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
            let selectableSelections = Set(
                loadedOptions
                    .filter(\.isSelectable)
                    .map(\.selection)
            )
            if !selectableSelections.contains(suggestedSelection) {
                suggestedSelection = preferredSelection
                    .flatMap { selectableSelections.contains($0) ? $0 : nil }
                    ?? loadedOptions.first(where: \.isSelectable)?.selection
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
            if lhs.isSelectable != rhs.isSelectable {
                return lhs.isSelectable
            }
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
                    ImportSheetContextRow(title: title)
                } footer: {
                    Text(message)
                }

                Section {
                    ForEach(viewModel.options) { option in
                        Button {
                            guard option.isSelectable else {
                                return
                            }
                            viewModel.rememberSelection(option.selection)
                            dismiss()
                            onSelect(option.selection)
                        } label: {
                            LibraryImportDestinationOptionRow(
                                option: option,
                                isSuggested: option.selection == viewModel.suggestedSelection
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isSelectable)
                        .accessibilityHint(confirmLabel)
                    }
                } header: {
                    Text("Choose Destination")
                } footer: {
                    Text(ImportDestinationSheetCopy.destinationFooter)
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
