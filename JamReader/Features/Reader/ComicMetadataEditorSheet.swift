import SwiftUI

/// One form for editing a comic's details: common fields first, the rest in
/// three groups. Changes stay in the app; the file is not renamed.
/// See docs/design-system/components/ScreenComicActions.
struct ComicMetadataEditorSheet: View {
    private enum Group: Hashable {
        case publication
        case creators
        case notes
    }

    @Environment(\.dismiss) private var dismiss

    private let onSave: (LibraryComic) -> Void
    private let coverURL: URL?
    private let coverSource: LocalComicCoverSource?

    @StateObject private var viewModel: ComicMetadataEditorSheetViewModel
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingComicInfoOptions = false

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        dependencies: AppDependencies,
        coverURL: URL? = nil,
        coverSource: LocalComicCoverSource? = nil,
        onSave: @escaping (LibraryComic) -> Void
    ) {
        self.onSave = onSave
        self.coverURL = coverURL
        self.coverSource = coverSource
        _viewModel = StateObject(
            wrappedValue: ComicMetadataEditorSheetViewModel(
                descriptor: descriptor,
                comic: comic,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                comicInfoImportService: dependencies.comicInfoImportService,
                storageManager: dependencies.libraryStorageManager
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Edit Metadata")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Group.self) { group in
                    groupForm(group)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            requestDismissal()
                        }
                        .disabled(viewModel.isSaving || viewModel.isImportingComicInfo)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let updatedComic = viewModel.save() {
                                onSave(updatedComic)
                                dismiss()
                            }
                        }
                        .disabled(viewModel.isLoading || viewModel.isSaving || viewModel.isImportingComicInfo || !viewModel.hasChanges || viewModel.loadFailed)
                    }
                }
        }
        .adaptiveSheetWidth(760)
        .presentationDetents([.large])
        .sheetDismissGuard(
            isBlocked: viewModel.hasChanges || viewModel.isSaving || viewModel.isImportingComicInfo
        ) {
            requestDismissal()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your metadata changes have not been saved.")
        }
        .confirmationDialog(
            "Read ComicInfo.xml from the File",
            isPresented: $isShowingComicInfoOptions,
            titleVisibility: .visible
        ) {
            ForEach(ComicInfoImportPolicy.allCases) { policy in
                Button(policy.title) {
                    viewModel.importEmbeddedComicInfo(using: policy)
                }
            }
        } message: {
            Text("Only this comic is updated. Review the result before saving.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading Metadata")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.loadFailed {
            ContentUnavailableView(
                "Failed to Load Metadata",
                systemImage: "exclamationmark.triangle",
                description: Text("Metadata couldn't be loaded. Close and try again.")
            )
        } else {
            Form {
                Section {
                    fileHeader
                }

                Section("Common") {
                    TextField("Title", text: binding(for: \.title))
                    TextField("Series", text: binding(for: \.series))
                    LabeledContent("Volume / Issue") {
                        HStack(spacing: Spacing.xs) {
                            TextField("Volume", text: binding(for: \.volume))
                            Text(verbatim: "/")
                                .foregroundStyle(Color.textTertiary)
                            TextField("Issue", text: binding(for: \.issueNumber))
                        }
                        .multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: binding(for: \.type)) {
                        ForEach(LibraryFileType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                Section("More Details") {
                    groupLink(.publication)
                    groupLink(.creators)
                    groupLink(.notes)
                }

                Section {
                    Button {
                        isShowingComicInfoOptions = true
                    } label: {
                        HStack {
                            Text("Read ComicInfo.xml from the File…")
                            Spacer()
                            if viewModel.isImportingComicInfo {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving || viewModel.isImportingComicInfo)
                } footer: {
                    Text("Fill only empty fields, or overwrite existing ones.")
                }
            }
        }
    }

    private var fileHeader: some View {
        HStack(spacing: Spacing.sm) {
            if coverURL != nil || coverSource != nil {
                LocalCoverThumbnailView(
                    url: coverURL,
                    fallbackSource: coverSource,
                    placeholderSystemName: "book.closed",
                    width: 48,
                    height: 72
                )
            }

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text("File")
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                Text(viewModel.metadata.fileName)
                    .font(AppFont.body())
                    .textSelection(.enabled)
                Text("Only changes details in the app, not the file name.")
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, Spacing.xxxs)
    }

    private func groupLink(_ group: Group) -> some View {
        NavigationLink(value: group) {
            LabeledContent(title(for: group), value: filledSummary(for: group))
        }
    }

    @ViewBuilder
    private func groupForm(_ group: Group) -> some View {
        Form {
            switch group {
            case .publication:
                Section {
                    TextField("Story Arc", text: binding(for: \.storyArc))
                    TextField("Publication Date", text: binding(for: \.publicationDate))
                    TextField("Publisher", text: binding(for: \.publisher))
                    TextField("Imprint", text: binding(for: \.imprint))
                    TextField("Format", text: binding(for: \.format))
                    TextField("Language ISO", text: binding(for: \.languageISO))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            case .creators:
                Section("Credits") {
                    TextField("Writer", text: binding(for: \.writer))
                    TextField("Penciller", text: binding(for: \.penciller))
                    TextField("Inker", text: binding(for: \.inker))
                    TextField("Colorist", text: binding(for: \.colorist))
                    TextField("Letterer", text: binding(for: \.letterer))
                    TextField("Cover Artist", text: binding(for: \.coverArtist))
                    TextField("Editor", text: binding(for: \.editor))
                }
                Section("Cast & Tags") {
                    TextField("Characters", text: binding(for: \.characters), axis: .vertical)
                    TextField("Teams", text: binding(for: \.teams), axis: .vertical)
                    TextField("Locations", text: binding(for: \.locations), axis: .vertical)
                    TextField("Tags", text: binding(for: \.tags), axis: .vertical)
                }
            case .notes:
                Section {
                    MetadataTextEditor(title: String(localized: "Synopsis"), text: binding(for: \.synopsis))
                    MetadataTextEditor(title: String(localized: "Notes"), text: binding(for: \.notes))
                    MetadataTextEditor(title: String(localized: "Review"), text: binding(for: \.review))
                }
            }
        }
        .navigationTitle(title(for: group))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func title(for group: Group) -> String {
        switch group {
        case .publication:
            return String(localized: "Publication")
        case .creators:
            return String(localized: "Creators & Characters")
        case .notes:
            return String(localized: "Summary & Notes")
        }
    }

    private func fields(for group: Group) -> [String] {
        let metadata = viewModel.metadata
        switch group {
        case .publication:
            return [metadata.storyArc, metadata.publicationDate, metadata.publisher, metadata.imprint, metadata.format, metadata.languageISO]
        case .creators:
            return [metadata.writer, metadata.penciller, metadata.inker, metadata.colorist, metadata.letterer, metadata.coverArtist, metadata.editor, metadata.characters, metadata.teams, metadata.locations, metadata.tags]
        case .notes:
            return [metadata.synopsis, metadata.notes, metadata.review]
        }
    }

    /// "2 items" or "Not set", so a group can be judged before opening it.
    private func filledSummary(for group: Group) -> String {
        let count = fields(for: group)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        switch count {
        case 0:
            return String(localized: "Not Set")
        case 1:
            return String(localized: "1 item")
        default:
            return String(localized: "\(count) items")
        }
    }

    private func binding<Value>(
        for keyPath: WritableKeyPath<LibraryComicMetadata, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                viewModel.metadata[keyPath: keyPath]
            },
            set: { newValue in
                viewModel.metadata[keyPath: keyPath] = newValue
            }
        )
    }

    private func requestDismissal() {
        guard !viewModel.isSaving, !viewModel.isImportingComicInfo else {
            return
        }

        if viewModel.hasChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

private struct MetadataTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.subheadline())
                .foregroundStyle(Color.textSecondary)

            TextEditor(text: $text)
                .frame(minHeight: 120)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
