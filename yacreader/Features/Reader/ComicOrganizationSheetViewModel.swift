import Combine
import Foundation

@MainActor
final class ComicOrganizationSheetViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var snapshot: LibraryOrganizationSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var alert: LibraryAlertState?

    let comic: LibraryComic

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let databaseURL: URL
    private var hasLoaded = false

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager
    ) {
        self.comic = comic
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.databaseURL = storageManager.databaseURL(for: descriptor)
    }

    var labels: [LibraryOrganizationCollection] {
        snapshot.labels
    }

    var readingLists: [LibraryOrganizationCollection] {
        snapshot.readingLists
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        load()
    }

    func load() {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            snapshot = try databaseReader.loadComicOrganizationSnapshot(
                databaseURL: databaseURL,
                comicID: comic.id
            )
        } catch {
            snapshot = .empty
            alert = LibraryAlertState(
                title: "Failed to Load Organization",
                message: error.localizedDescription
            )
        }
    }

    func toggleMembership(for collection: LibraryOrganizationCollection) {
        let updatedMembership = !collection.isAssigned

        do {
            switch collection.type {
            case .label:
                try databaseWriter.setLabelMembership(
                    updatedMembership,
                    comicID: comic.id,
                    labelID: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.setReadingListMembership(
                    updatedMembership,
                    comicID: comic.id,
                    readingListID: collection.id,
                    in: databaseURL
                )
            }

            snapshot.update(collection.updatingAssignment(updatedMembership))
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Organization",
                message: error.localizedDescription
            )
        }
    }
}
