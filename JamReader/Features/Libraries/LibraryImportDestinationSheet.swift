import Combine
import SwiftUI

enum ImportDestinationSheetCopy {
    static let destinationFooter = "Imports are copied to the selected library."
    static let remoteImportNotice = "Remote files download to the selected library on this device."
}

struct LibraryImportDestinationOptionRow: View {
    let option: LibraryImportDestinationOption
    var isSelected = false
    var showsSelectionIndicator = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(accentColor.opacity(isSelected ? 0.18 : 0.12))

                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text(option.title)
                        .font(AppFont.body(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: Spacing.xs)

                    if showsSelectionIndicator {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? accentColor : Color.textTertiary)
                            .accessibilityHidden(true)
                    }
                }

                if let detail = option.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Spacing.xs) {
                    if let status = option.status {
                        Label(status.title, systemImage: statusSystemImage)
                            .font(AppFont.caption2(.semibold))
                            .foregroundStyle(accentColor)
                    }

                    if let unavailableReason {
                        Label(unavailableReason, systemImage: "exclamationmark.circle.fill")
                            .font(AppFont.caption2())
                            .foregroundStyle(Color.appWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .opacity(option.isSelectable ? 1 : 0.78)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityStatus)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accentColor: Color {
        option.status?.tintColor ?? .blue
    }

    private var iconSystemName: String {
        switch option.status {
        case .appManaged:
            return "internaldrive.fill"
        case .linkedFolder:
            return "folder.fill"
        case .readOnly:
            return "lock.fill"
        case .none:
            return "square.stack.3d.up.fill"
        }
    }

    private var statusSystemImage: String {
        switch option.status {
        case .appManaged:
            return "checkmark.shield.fill"
        case .linkedFolder:
            return "link"
        case .readOnly:
            return "lock.fill"
        case .none:
            return "square.stack.3d.up.fill"
        }
    }

    private var unavailableReason: String? {
        guard case .unavailable(let reason) = option.availability else {
            return nil
        }

        return reason
    }

    private var accessibilityStatus: String {
        [option.status?.title, unavailableReason]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var cardBackgroundColor: Color {
        if isSelected {
            return accentColor.opacity(0.10)
        }

        return Color.surfaceSecondary
    }

    private var cardBorderColor: Color {
        if isSelected {
            return accentColor.opacity(0.55)
        }

        return Color.black.opacity(0.06)
    }
}

private extension LibraryImportDestinationOption.Status {
    var tintColor: Color {
        switch self {
        case .appManaged:
            return .teal
        case .linkedFolder:
            return .blue
        case .readOnly:
            return .orange
        }
    }

    var sortRank: Int {
        switch self {
        case .appManaged:
            return 0
        case .linkedFolder:
            return 1
        case .readOnly:
            return 2
        }
    }
}

struct ImportSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.headline())
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xxs)
            }
        }
    }
}

@MainActor
final class LibraryImportDestinationSheetViewModel: ObservableObject {
    private static let lastSelectionKey = "libraryImport.lastDestinationSelection"

    @Published private(set) var options: [LibraryImportDestinationOption] = []
    @Published private(set) var suggestedSelection: LibraryImportDestinationSelection
    @Published var alert: AppAlertState?

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
            alert = AppAlertState(
                title: "Import Destinations Unavailable",
                message: error.userFacingMessage
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

            let lhsRank = lhs.status?.sortRank ?? .max
            let rhsRank = rhs.status?.sortRank ?? .max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
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
    let message: String?
    let supplementaryNotice: String?
    let confirmLabel: String
    let onSelect: (LibraryImportDestinationSelection) -> Void

    @StateObject private var viewModel: LibraryImportDestinationSheetViewModel
    @State private var selectedDestination: LibraryImportDestinationSelection
    @State private var hasAppliedSuggestedDestination = false

    init(
        title: String,
        message: String? = nil,
        supplementaryNotice: String? = nil,
        confirmLabel: String = "Use This Library",
        dependencies: AppDependencies,
        preferredSelection: LibraryImportDestinationSelection? = nil,
        onSelect: @escaping (LibraryImportDestinationSelection) -> Void
    ) {
        self.title = title
        self.message = message
        self.supplementaryNotice = supplementaryNotice
        self.confirmLabel = confirmLabel
        self.onSelect = onSelect
        _selectedDestination = State(initialValue: preferredSelection ?? .importedComics)
        _viewModel = StateObject(
            wrappedValue: LibraryImportDestinationSheetViewModel(
                dependencies: dependencies,
                preferredSelection: preferredSelection
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(AppFont.subheadline())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ImportSection(
                        title: "Choose Destination",
                        footer: supplementaryNotice ?? ImportDestinationSheetCopy.destinationFooter
                    ) {
                        ForEach(viewModel.options) { option in
                            Button {
                                guard option.isSelectable else {
                                    return
                                }

                                selectedDestination = option.selection
                            } label: {
                                LibraryImportDestinationOptionRow(
                                    option: option,
                                    isSelected: selectedDestination == option.selection,
                                    showsSelectionIndicator: true
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!option.isSelectable)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(title)
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
                applySuggestedDestinationIfNeeded()
            }
            .onChange(of: viewModel.options) { _, _ in
                applySuggestedDestinationIfNeeded()
            }
            .alert(item: $viewModel.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.sm) {
                    Button {
                        viewModel.rememberSelection(selectedDestination)
                        let selection = selectedDestination
                        dismiss()
                        onSelect(selection)
                    } label: {
                        Text(confirmLabel)
                            .font(AppFont.body(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isSelectedDestinationSelectable)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .background(.regularMaterial)
            }
        }
        .adaptiveFormSheet(760)
        .presentationBackground(Color.surfaceGrouped)
        .presentationDragIndicator(.visible)
    }

    private var isSelectedDestinationSelectable: Bool {
        viewModel.options.contains {
            $0.selection == selectedDestination && $0.isSelectable
        }
    }

    private func applySuggestedDestinationIfNeeded() {
        guard !hasAppliedSuggestedDestination,
              !viewModel.options.isEmpty else {
            return
        }

        hasAppliedSuggestedDestination = true
        selectedDestination = viewModel.suggestedSelection
    }
}
