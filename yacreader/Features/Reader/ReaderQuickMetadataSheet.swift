import SwiftUI

struct ReaderQuickMetadataSheet: View {
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
                            TextField("Publisher", text: binding(for: \.publisher))
                        }

                        Section("Tags") {
                            TextField("Tags", text: binding(for: \.tags), axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }
                }
            }
            .navigationTitle("Quick Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let updatedComic = viewModel.save() {
                            onSave(updatedComic)
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving || !viewModel.hasChanges)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isSaving)
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
