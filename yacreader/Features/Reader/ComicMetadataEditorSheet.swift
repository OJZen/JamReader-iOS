import SwiftUI

struct ComicMetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let onSave: (LibraryComic) -> Void

    @StateObject private var viewModel: ComicMetadataEditorSheetViewModel

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        dependencies: AppDependencies,
        onSave: @escaping (LibraryComic) -> Void
    ) {
        self.onSave = onSave
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
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading Metadata")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            ComicMetadataOverviewContent(
                                title: viewModel.metadata.displayTitle,
                                fileName: viewModel.metadata.fileName,
                                badges: metadataHeaderBadges
                            )
                        }

                        Section("Core") {
                            TextField("Title", text: binding(for: \.title))
                            TextField("Series", text: binding(for: \.series))
                            TextField("Issue Number", text: binding(for: \.issueNumber))
                            TextField("Volume", text: binding(for: \.volume))

                            Picker("Type", selection: binding(for: \.type)) {
                                ForEach(LibraryFileType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                        }

                        Section("Publishing") {
                            TextField("Story Arc", text: binding(for: \.storyArc))
                            TextField("Publication Date", text: binding(for: \.publicationDate))
                            TextField("Publisher", text: binding(for: \.publisher))
                            TextField("Imprint", text: binding(for: \.imprint))
                            TextField("Format", text: binding(for: \.format))
                            TextField("Language ISO", text: binding(for: \.languageISO))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }

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

                        Section("Notes") {
                            MetadataTextEditor(title: "Synopsis", text: binding(for: \.synopsis))
                            MetadataTextEditor(title: "Notes", text: binding(for: \.notes))
                            MetadataTextEditor(title: "Review", text: binding(for: \.review))
                        }
                    }
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isImportingComicInfo {
                        ProgressView()
                    } else {
                        Menu {
                            ForEach(ComicInfoImportPolicy.allCases) { policy in
                                Button {
                                    viewModel.importEmbeddedComicInfo(using: policy)
                                } label: {
                                    Text(policy.title)
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(viewModel.isLoading || viewModel.isSaving)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let updatedComic = viewModel.save() {
                            onSave(updatedComic)
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving || viewModel.isImportingComicInfo || !viewModel.hasChanges)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.isImportingComicInfo)
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

    private var metadataHeaderBadges: [StatusBadgeItem] {
        [StatusBadgeItem(title: viewModel.metadata.type.title, tint: .gray)]
    }
}

private struct MetadataTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .frame(minHeight: 120)
        }
        .padding(.vertical, 4)
    }
}
