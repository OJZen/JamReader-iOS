import SwiftUI
import UniformTypeIdentifiers

/// "Add Comics": the one entry for the home [+] and the empty-state button.
/// Three ways, explained by purpose: import (copy), use an existing folder
/// (no copy), or a new empty library. See docs/design-system/components/ScreenAddComics.
struct LibraryAddComicsSheet: View {
    private enum Step: Hashable {
        case importComics
        case newLibrary
    }

    private enum PickerRoute {
        case comicFiles
        case comicFolder
        case libraryFolder

        var contentTypes: [UTType] {
            switch self {
            case .comicFiles:
                return [.data]
            case .comicFolder, .libraryFolder:
                return [.folder]
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onImport: (_ urls: [URL], _ traverseDirectories: Bool, _ destination: LibraryImportDestinationSelection) -> Void
    let onLinkFolders: ([URL]) -> Void
    let onCreateLibrary: (String) -> Bool
    let onPickerError: (Error) -> Void

    @StateObject private var destinations: LibraryImportDestinationSheetViewModel
    @State private var path: [Step] = []
    @State private var selectedDestination: LibraryImportDestinationSelection = .importedComics
    @State private var hasAppliedSuggestedDestination = false
    @State private var activePicker: PickerRoute?
    /// The picker binding is cleared before its completion runs on iOS 27, so
    /// the route is kept separately for the completion handler.
    @State private var presentedPicker: PickerRoute?

    init(
        dependencies: AppDependencies,
        onImport: @escaping (_ urls: [URL], _ traverseDirectories: Bool, _ destination: LibraryImportDestinationSelection) -> Void,
        onLinkFolders: @escaping ([URL]) -> Void,
        onCreateLibrary: @escaping (String) -> Bool,
        onPickerError: @escaping (Error) -> Void
    ) {
        self.onImport = onImport
        self.onLinkFolders = onLinkFolders
        self.onCreateLibrary = onCreateLibrary
        self.onPickerError = onPickerError
        _destinations = StateObject(
            wrappedValue: LibraryImportDestinationSheetViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        path.append(.importComics)
                    } label: {
                        AddComicsOptionRow(
                            title: String(localized: "Import Comics"),
                            detail: String(localized: "Copies files into JamReader. For downloads, AirDrop or comics on a USB drive."),
                            systemImage: "square.and.arrow.down",
                            tint: .appJam
                        )
                    }
                }

                Section {
                    Button {
                        present(.libraryFolder)
                    } label: {
                        AddComicsOptionRow(
                            title: String(localized: "Use Existing Folder"),
                            detail: String(localized: "Reads a comics folder in Files directly. Nothing is copied, and the files are not changed."),
                            systemImage: LibraryKind.linkedFolder.systemImageName,
                            tint: LibraryKind.linkedFolder.tileColor
                        )
                    }
                }

                Section {
                    Button {
                        path.append(.newLibrary)
                    } label: {
                        AddComicsOptionRow(
                            title: String(localized: "New Empty Library"),
                            detail: String(localized: "Creates a place for comics first. Import into it later."),
                            systemImage: "plus",
                            tint: Color(.systemGray)
                        )
                    }
                }
            }
            .listSectionSpacing(Spacing.sm)
            .navigationTitle("Add Comics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .importComics:
                    importComicsStep
                case .newLibrary:
                    LibraryCreateForm(onCreate: onCreateLibrary)
                }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { activePicker != nil },
                set: { isPresented in
                    if !isPresented {
                        activePicker = nil
                    }
                }
            ),
            allowedContentTypes: presentedPicker?.contentTypes ?? [.data],
            allowsMultipleSelection: true
        ) { result in
            let route = presentedPicker
            presentedPicker = nil
            handlePickerResult(result, route: route)
        }
        .onAppear {
            destinations.loadIfNeeded()
            applySuggestedDestinationIfNeeded()
        }
        .onChange(of: destinations.options) { _, _ in
            applySuggestedDestinationIfNeeded()
        }
        .adaptiveFormSheet(640)
        .presentationDragIndicator(.visible)
    }

    private var importComicsStep: some View {
        List {
            Section {
                ForEach(destinations.options) { option in
                    Button {
                        selectedDestination = option.selection
                    } label: {
                        ImportDestinationListRow(
                            option: option,
                            isSelected: selectedDestination == option.selection
                        )
                    }
                    .disabled(!option.isSelectable)
                }
            } header: {
                Text("Import To")
            } footer: {
                Text("Your choice is remembered for next time.")
            }
        }
        .navigationTitle("Import Comics")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Large text stacks the buttons instead of breaking their titles.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Spacing.sm))
            layout {
                Button {
                    present(.comicFiles)
                } label: {
                    Label("Choose Files", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appJam)

                Button {
                    present(.comicFolder)
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .labelStyle(.titleOnly)
            .font(AppFont.body(.semibold))
            .controlSize(.large)
            .disabled(!isSelectedDestinationSelectable)
            .containerHorizontalMargins()
            .padding(.vertical, Spacing.sm)
            .background(.bar)
        }
        .alert(item: $destinations.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var isSelectedDestinationSelectable: Bool {
        destinations.options.contains {
            $0.selection == selectedDestination && $0.isSelectable
        }
    }

    private func applySuggestedDestinationIfNeeded() {
        guard !hasAppliedSuggestedDestination, !destinations.options.isEmpty else {
            return
        }

        hasAppliedSuggestedDestination = true
        selectedDestination = destinations.suggestedSelection
    }

    private func present(_ route: PickerRoute) {
        presentedPicker = route
        activePicker = route
    }

    private func handlePickerResult(_ result: Result<[URL], Error>, route: PickerRoute?) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty, let route else {
                return
            }

            switch route {
            case .comicFiles, .comicFolder:
                destinations.rememberSelection(selectedDestination)
                onImport(urls, route == .comicFolder, selectedDestination)
            case .libraryFolder:
                onLinkFolders(urls)
            }
        case .failure(let error):
            onPickerError(error)
        }
    }
}

private struct AddComicsOptionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint, in: RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .font(AppFont.body(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(AppFont.footnote(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Destination row: library type tile, name, where it lives, and a check.
/// Read-only libraries stay listed, disabled, with the reason.
struct ImportDestinationListRow: View {
    let option: LibraryImportDestinationOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SettingsIcon(systemName: kind.systemImageName, color: kind.tileColor)
                .opacity(option.isSelectable ? 1 : 0.55)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(option.title)
                    .font(AppFont.body())
                    .foregroundStyle(option.isSelectable ? Color.textPrimary : Color.textTertiary)

                Text(detailText)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !option.isSelectable {
                StatusBadge(status: .readOnly)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(AppFont.body(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var kind: LibraryKind {
        switch option.selection {
        case .importedComics:
            return .importedComics
        case .library:
            return option.status == .appManaged ? .appManaged : .linkedFolder
        }
    }

    private var detailText: String {
        if case .unavailable(let reason) = option.availability {
            return reason
        }
        return kind.storageDescription
    }
}
