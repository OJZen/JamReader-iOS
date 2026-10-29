import SwiftUI

/// One tag or reading list, on the shared collection page.
struct LibraryOrganizationCollectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPresenter) private var appPresenter

    private let dependencies: AppDependencies

    @StateObject private var viewModel: LibraryOrganizationCollectionDetailViewModel
    @State private var isConfirmingCollectionDeletion = false

    init(
        descriptor: LibraryDescriptor,
        collection: LibraryOrganizationCollection,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: LibraryOrganizationCollectionDetailViewModel(
                descriptor: descriptor,
                collection: collection,
                databaseReader: dependencies.libraryDatabaseReader,
                databaseWriter: dependencies.libraryDatabaseWriter,
                storageManager: dependencies.libraryStorageManager,
                coverLocator: dependencies.libraryCoverLocator,
                comicRemovalService: dependencies.libraryComicRemovalService,
                remoteBackgroundImportController: dependencies.remoteBackgroundImportController
            )
        )
    }

    var body: some View {
        let collection = viewModel.collection

        LibraryComicCollectionPage(
            model: viewModel,
            dependencies: dependencies,
            title: collection.displayTitle,
            subtitle: LibraryCollectionCopy.subtitle(
                libraryName: viewModel.descriptor.displayName,
                comicCount: viewModel.comics.count
            ),
            emptyStateSystemImage: collection.systemImageName,
            emptyStateTitle: collection.type == .label
                ? String(localized: "No Comics with This Tag")
                : String(localized: "This Reading List Is Empty"),
            emptyStateDescription: String(localized: "Add comics from their More menu with Tags & Lists."),
            sortStorageKey: "libraryOrganizationCollectionSortMode.\(collection.type.rawValue).\(collection.id)",
            displayStorageKey: "libraryOrganizationCollectionDisplayMode.\(collection.type.rawValue).\(collection.id)",
            defaultSortMode: .sourceOrder,
            membershipRemoval: LibraryCollectionMembershipRemoval(
                title: collection.type == .label
                    ? String(localized: "Remove from Tag")
                    : String(localized: "Remove from Reading List"),
                removeOne: { viewModel.remove($0) },
                removeMany: { viewModel.removeComics(withIDs: $0) }
            )
        ) {
            Section {
                Button {
                    presentCollectionEditor()
                } label: {
                    Label(
                        collection.type == .label ? "Edit Tag" : "Edit Reading List",
                        systemImage: "square.and.pencil"
                    )
                }

                Button(role: .destructive) {
                    isConfirmingCollectionDeletion = true
                } label: {
                    Label(LibraryCollectionDeletionCopy.actionTitle(for: collection.type), systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            LibraryCollectionDeletionCopy.title(for: collection),
            isPresented: $isConfirmingCollectionDeletion,
            titleVisibility: .visible
        ) {
            Button(LibraryCollectionDeletionCopy.actionTitle(for: collection.type), role: .destructive) {
                if viewModel.deleteCollection() {
                    dismiss()
                }
            }
        } message: {
            Text(LibraryCollectionDeletionCopy.message(for: collection.type))
        }
    }

    private func presentCollectionEditor() {
        let collection = viewModel.collection
        appPresenter?.presentSheet(
            .content(
                id: "library.collectionDetail.collectionEditor.\(collection.id)",
                content: AnyView(
                    LibraryOrganizationCollectionEditorSheet(collection: collection) { name, color in
                        viewModel.updateCollection(
                            name: name,
                            labelColor: color
                        )
                    }
                )
            )
        )
    }
}

/// Deleting a tag or reading list only removes the grouping; comics stay.
enum LibraryCollectionDeletionCopy {
    static func title(for collection: LibraryOrganizationCollection) -> String {
        switch collection.type {
        case .label:
            return String(localized: "Delete Tag “\(collection.displayTitle)”?")
        case .readingList:
            return String(localized: "Delete Reading List “\(collection.displayTitle)”?")
        }
    }

    static func actionTitle(for type: LibraryOrganizationCollectionType) -> String {
        switch type {
        case .label:
            return String(localized: "Delete Tag")
        case .readingList:
            return String(localized: "Delete Reading List")
        }
    }

    static func message(for type: LibraryOrganizationCollectionType) -> String {
        switch type {
        case .label:
            return String(localized: "The tag is removed from its comics. The comics are not deleted.")
        case .readingList:
            return String(localized: "The reading list is removed. The comics in it are not deleted.")
        }
    }
}
