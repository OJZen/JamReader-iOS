import Combine
import Foundation
import os

@MainActor
final class ComicOrganizationSheetViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var snapshot: LibraryOrganizationSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var alert: AppAlertState?

    let comic: LibraryComic

    private let libraryID: String
    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let databaseURL: URL
    private var hasLoaded = false
    private let logger = AppLog.library

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager
    ) {
        self.libraryID = descriptor.id.uuidString
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
            logger.info(
                "Library comic organization loaded libraryID=\(self.libraryID, privacy: .public) comicID=\(self.comic.id) labels=\(self.snapshot.labels.count) readingLists=\(self.snapshot.readingLists.count)"
            )
        } catch {
            snapshot = .empty
            logger.error(
                "Library comic organization load failed libraryID=\(self.libraryID, privacy: .public) comicID=\(self.comic.id) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: String(localized: "Failed to Load Organization"),
                message: error.userFacingMessage
            )
        }
    }

    func toggleMembership(for collection: LibraryOrganizationCollection) {
        let updatedMembership = !collection.isAssigned
        logger.info(
            "Library comic organization membership update requested libraryID=\(self.libraryID, privacy: .public) comicID=\(self.comic.id) collectionID=\(collection.id) type=\(collection.type.rawValue, privacy: .public) value=\(updatedMembership)"
        )

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
            logger.info(
                "Library comic organization membership update completed libraryID=\(self.libraryID, privacy: .public) comicID=\(self.comic.id) collectionID=\(collection.id) type=\(collection.type.rawValue, privacy: .public) value=\(updatedMembership)"
            )
        } catch {
            logger.error(
                "Library comic organization membership update failed libraryID=\(self.libraryID, privacy: .public) comicID=\(self.comic.id) collectionID=\(collection.id) type=\(collection.type.rawValue, privacy: .public) value=\(updatedMembership) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: String(localized: "Failed to Update Organization"),
                message: error.userFacingMessage
            )
        }
    }
}
