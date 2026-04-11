import SwiftUI

struct ComicOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ComicOrganizationSheetViewModel

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        dependencies: AppDependencies
    ) {
        _viewModel = StateObject(
            wrappedValue: ComicOrganizationSheetViewModel(
                descriptor: descriptor,
                comic: comic,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading Organization")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.comic.displayTitle)
                                    .font(.headline)

                                Text("Add or remove this comic from tags and reading lists.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }

                        Section("Tags") {
                            if viewModel.labels.isEmpty {
                                Text("No tags yet. Create one from the library root.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.labels) { collection in
                                    Button {
                                        viewModel.toggleMembership(for: collection)
                                    } label: {
                                        LibraryOrganizationCollectionRow(
                                            collection: collection,
                                            showsAssignmentIndicator: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Section("Reading Lists") {
                            if viewModel.readingLists.isEmpty {
                                Text("No reading lists yet. Create one from the library root.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.readingLists) { collection in
                                    Button {
                                        viewModel.toggleMembership(for: collection)
                                    } label: {
                                        LibraryOrganizationCollectionRow(
                                            collection: collection,
                                            showsAssignmentIndicator: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .adaptiveFormSheet(720)
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
}
