import Combine
import Foundation
import os
import UIKit

@MainActor
final class LibraryOrganizationCollectionDetailViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var collection: LibraryOrganizationCollection
    @Published private(set) var comics: [LibraryComic] = []
    @Published private(set) var isLoading = false
    @Published var alert: AppAlertState?

    let descriptor: LibraryDescriptor

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let coverLocator: LibraryCoverLocator
    private let comicRemovalService: LibraryComicRemovalService
    private let remoteBackgroundImportController: RemoteBackgroundImportController
    private let databaseURL: URL
    private let metadataRootURL: URL
    private var hasLoaded = false
    private var accessSession: LibraryAccessSession?
    private var hasLoggedSourceRootResolutionFailure = false
    private let logger = AppLog.library

    init(
        descriptor: LibraryDescriptor,
        collection: LibraryOrganizationCollection,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager,
        coverLocator: LibraryCoverLocator,
        comicRemovalService: LibraryComicRemovalService,
        remoteBackgroundImportController: RemoteBackgroundImportController
    ) {
        self.descriptor = descriptor
        self.collection = collection
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.coverLocator = coverLocator
        self.comicRemovalService = comicRemovalService
        self.remoteBackgroundImportController = remoteBackgroundImportController
        self.databaseURL = storageManager.databaseURL(for: descriptor)
        self.metadataRootURL = storageManager.metadataRootURL(for: descriptor)
    }

    var navigationTitle: String {
        collection.displayTitle
    }

    var summaryText: String {
        collection.countText
    }

    var canRemoveComics: Bool {
        comicRemovalService.canRemoveComics(from: descriptor)
    }

    func updateCollection(
        name: String,
        labelColor: LibraryLabelColor?
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = AppAlertState(
                title: "Name Required",
                message: "Enter a name before saving this \(collection.type == .label ? "tag" : "reading list")."
            )
            return false
        }

        logger.info(
            "Library collection detail update requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public)"
        )

        do {
            switch collection.type {
            case .label:
                try databaseWriter.updateLabel(
                    id: collection.id,
                    named: trimmedName,
                    color: labelColor ?? collection.labelColor ?? .blue,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.updateReadingList(
                    id: collection.id,
                    named: trimmedName,
                    in: databaseURL
                )
            }

            collection = collection.updatingDetails(
                name: trimmedName,
                labelColor: labelColor
            )
            logger.info(
                "Library collection detail update completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public)"
            )
            return true
        } catch {
            logger.error(
                "Library collection detail update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.userFacingMessage
            )
            return false
        }
    }

    func deleteCollection() -> Bool {
        logger.info(
            "Library collection detail delete requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) name=\(AppLogSanitizer.truncated(self.collection.displayTitle), privacy: .public)"
        )

        do {
            switch collection.type {
            case .label:
                try databaseWriter.deleteLabel(
                    id: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.deleteReadingList(
                    id: collection.id,
                    in: databaseURL
                )
            }
            logger.info(
                "Library collection detail delete completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public)"
            )
            return true
        } catch {
            logger.error(
                "Library collection detail delete failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Delete \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.userFacingMessage
            )
            return false
        }
    }

    func applyUpdatedComic(_ updatedComic: LibraryComic) {
        comics = comics.map { comic in
            comic.id == updatedComic.id ? updatedComic : comic
        }
    }

    func toggleFavorite(for comic: LibraryComic) {
        let updatedValue = !comic.isFavorite
        AppHaptics.medium()

        do {
            try databaseWriter.setFavorite(
                updatedValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingFavorite(updatedValue))
            logger.info(
                "Library collection detail favorite updated libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) value=\(updatedValue)"
            )
        } catch {
            logger.error(
                "Library collection detail favorite update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) value=\(updatedValue) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Favorites",
                message: error.userFacingMessage
            )
        }
    }

    func setFavorite(_ isFavorite: Bool, for comicIDs: [Int64]) -> Bool {
        let selectedComicIDs = Set(comicIDs)
        guard !selectedComicIDs.isEmpty else {
            return true
        }

        AppHaptics.medium()

        do {
            try databaseWriter.setFavorite(
                isFavorite,
                for: Array(selectedComicIDs),
                in: databaseURL
            )

            comics = comics.map { comic in
                selectedComicIDs.contains(comic.id) ? comic.updatingFavorite(isFavorite) : comic
            }

            logger.info(
                "Library collection detail favorite batch updated libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) count=\(selectedComicIDs.count) value=\(isFavorite)"
            )
            return true
        } catch {
            logger.error(
                "Library collection detail favorite batch update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) count=\(selectedComicIDs.count) value=\(isFavorite) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Favorites",
                message: error.userFacingMessage
            )
            return false
        }
    }

    func toggleReadStatus(for comic: LibraryComic) {
        let updatedValue = !comic.read
        AppHaptics.light()

        do {
            try databaseWriter.setReadStatus(
                updatedValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingReadState(updatedValue))
            logger.info(
                "Library collection detail read status updated libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) value=\(updatedValue)"
            )
        } catch {
            logger.error(
                "Library collection detail read status update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) value=\(updatedValue) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Read Status",
                message: error.userFacingMessage
            )
        }
    }

    func setRating(_ rating: Int, for comic: LibraryComic) {
        let normalizedRating = min(max(rating, 0), 5)
        let ratingValue = normalizedRating > 0 ? Double(normalizedRating) : nil
        let currentRating = min(max(Int((comic.rating ?? 0).rounded()), 0), 5)
        guard currentRating != normalizedRating else {
            return
        }

        AppHaptics.selection()

        do {
            try databaseWriter.setRating(
                ratingValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingRating(ratingValue))
            logger.info(
                "Library collection detail rating updated libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) rating=\(normalizedRating)"
            )
        } catch {
            logger.error(
                "Library collection detail rating update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) comicID=\(comic.id) rating=\(normalizedRating) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Rating",
                message: error.userFacingMessage
            )
        }
    }

    func setReadStatus(_ isRead: Bool, for comicIDs: [Int64]) -> Bool {
        let selectedComicIDs = Set(comicIDs)
        guard !selectedComicIDs.isEmpty else {
            return true
        }

        AppHaptics.light()

        do {
            try databaseWriter.setReadStatus(
                isRead,
                for: Array(selectedComicIDs),
                in: databaseURL
            )

            let now = Date()
            comics = comics.map { comic in
                selectedComicIDs.contains(comic.id)
                    ? comic.updatingReadState(isRead, lastOpenedAt: now)
                    : comic
            }

            logger.info(
                "Library collection detail read status batch updated libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) count=\(selectedComicIDs.count) value=\(isRead)"
            )
            return true
        } catch {
            logger.error(
                "Library collection detail read status batch update failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) count=\(selectedComicIDs.count) value=\(isRead) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Read Status",
                message: error.userFacingMessage
            )
            return false
        }
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
            comics = try databaseReader.loadOrganizationComics(
                databaseURL: databaseURL,
                collection: collection
            )
            collection = LibraryOrganizationCollection(
                id: collection.id,
                name: collection.name,
                type: collection.type,
                comicCount: comics.count,
                isAssigned: collection.isAssigned,
                labelColor: collection.labelColor
            )
            logger.info(
                "Library collection detail loaded libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) count=\(self.comics.count)"
            )
        } catch {
            comics = []
            logger.error(
                "Library collection detail load failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Load Collection",
                message: error.userFacingMessage
            )
        }
    }

    func remove(_ comic: LibraryComic) {
        logger.info(
            "Library collection membership remove requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) comicID=\(comic.id)"
        )

        do {
            switch collection.type {
            case .label:
                try databaseWriter.setLabelMembership(
                    false,
                    comicID: comic.id,
                    labelID: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.setReadingListMembership(
                    false,
                    comicID: comic.id,
                    readingListID: collection.id,
                    in: databaseURL
                )
            }

            comics.removeAll { $0.id == comic.id }
            collection = LibraryOrganizationCollection(
                id: collection.id,
                name: collection.name,
                type: collection.type,
                comicCount: comics.count,
                isAssigned: collection.isAssigned,
                labelColor: collection.labelColor
            )
            logger.info(
                "Library collection membership remove completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) comicID=\(comic.id)"
            )
        } catch {
            logger.error(
                "Library collection membership remove failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) comicID=\(comic.id) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Collection",
                message: error.userFacingMessage
            )
        }
    }

    func removeComics(withIDs comicIDs: [Int64]) -> Bool {
        let uniqueComicIDs = Array(Set(comicIDs))
        guard !uniqueComicIDs.isEmpty else {
            return true
        }

        logger.info(
            "Library collection membership batch remove requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) count=\(uniqueComicIDs.count)"
        )

        do {
            switch collection.type {
            case .label:
                try databaseWriter.setLabelMembership(
                    false,
                    comicIDs: uniqueComicIDs,
                    labelID: collection.id,
                    in: databaseURL
                )
            case .readingList:
                try databaseWriter.setReadingListMembership(
                    false,
                    comicIDs: uniqueComicIDs,
                    readingListID: collection.id,
                    in: databaseURL
                )
            }

            let removedComicIDs = Set(uniqueComicIDs)
            comics.removeAll { removedComicIDs.contains($0.id) }
            collection = LibraryOrganizationCollection(
                id: collection.id,
                name: collection.name,
                type: collection.type,
                comicCount: comics.count,
                isAssigned: collection.isAssigned,
                labelColor: collection.labelColor
            )
            logger.info(
                "Library collection membership batch remove completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) count=\(uniqueComicIDs.count)"
            )
            return true
        } catch {
            logger.error(
                "Library collection membership batch remove failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) count=\(uniqueComicIDs.count) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Update Collection",
                message: error.userFacingMessage
            )
            return false
        }
    }

    func removeComicFromLibrary(_ comic: LibraryComic) -> Bool {
        guard beginExclusiveLibraryStorageOperation() else {
            return false
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        do {
            try comicRemovalService.removeComic(comic, from: descriptor)
            AppHaptics.warning()
            load()
            return true
        } catch {
            alert = AppAlertState(
                title: "Failed to Remove Comic",
                message: error.userFacingMessage
            )
            return false
        }
    }

    private func beginExclusiveLibraryStorageOperation() -> Bool {
        guard remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            alert = AppAlertState(
                title: "Library Busy",
                message: "Finish the current import or storage task, then try again."
            )
            return false
        }

        return true
    }

    func coverURL(for comic: LibraryComic) -> URL? {
        coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL)
    }

    func coverSource(for comic: LibraryComic) -> LocalComicCoverSource? {
        guard let sourceRootURL = resolvedSourceRootURLIfAvailable() else {
            return nil
        }

        return LocalComicCoverSource(
            fileURL: resolveComicFileURL(for: comic, sourceRootURL: sourceRootURL),
            cacheURL: coverLocator.plannedCoverURL(for: comic, metadataRootURL: metadataRootURL)
        )
    }

    func heroSourceID(for comic: LibraryComic) -> String {
        "library-organization-comic-\(descriptor.id.uuidString)-\(collection.id)-\(comic.id)"
    }

    func cachedTransitionImage(for comic: LibraryComic) -> UIImage? {
        LocalCoverTransitionCache.shared.image(for: heroSourceID(for: comic))
    }

    private func resolveComicFileURL(
        for comic: LibraryComic,
        sourceRootURL: URL
    ) -> URL {
        let relativePath = {
            let rawPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawPath.isEmpty {
                return comic.fileName
            }

            return rawPath
        }()

        if relativePath.hasPrefix("/") {
            return sourceRootURL.appendingPathComponent(String(relativePath.dropFirst()))
        }

        return sourceRootURL.appendingPathComponent(relativePath)
    }

    private func resolvedSourceRootURLIfAvailable() -> URL? {
        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }

            if let sourceURL = accessSession?.sourceURL {
                return sourceURL
            }

            return try storageManager.restoreSourceURL(for: descriptor)
        } catch {
            logSourceRootResolutionFailureOnce(error: error)
            return nil
        }
    }

    private func logSourceRootResolutionFailureOnce(error: Error) {
        guard !hasLoggedSourceRootResolutionFailure else {
            return
        }

        hasLoggedSourceRootResolutionFailure = true
        logger.warning(
            "Library collection source root resolution failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) collectionID=\(self.collection.id) type=\(self.collection.type.rawValue, privacy: .public) kind=\(self.descriptor.kind.rawValue, privacy: .public) root=\(AppLogSanitizer.path(self.descriptor.rootPath), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
        )
    }
}
