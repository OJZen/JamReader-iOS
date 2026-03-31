import Combine
import Foundation

@MainActor
final class LibraryOrganizationCollectionDetailViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var collection: LibraryOrganizationCollection
    @Published private(set) var comics: [LibraryComic] = []
    @Published private(set) var isLoading = false
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let coverLocator: LibraryCoverLocator
    private let comicRemovalService: LibraryComicRemovalService
    private let databaseURL: URL
    private let metadataRootURL: URL
    private var hasLoaded = false

    init(
        descriptor: LibraryDescriptor,
        collection: LibraryOrganizationCollection,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager,
        coverLocator: LibraryCoverLocator,
        comicRemovalService: LibraryComicRemovalService
    ) {
        self.descriptor = descriptor
        self.collection = collection
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.coverLocator = coverLocator
        self.comicRemovalService = comicRemovalService
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
            alert = LibraryAlertState(
                title: "Name Required",
                message: "Enter a name before saving this \(collection.type == .label ? "tag" : "reading list")."
            )
            return false
        }

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
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.localizedDescription
            )
            return false
        }
    }

    func deleteCollection() -> Bool {
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
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Delete \(collection.type == .label ? "Tag" : "Reading List")",
                message: error.localizedDescription
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
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Favorites",
                message: error.localizedDescription
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

            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Favorites",
                message: error.localizedDescription
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
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Read Status",
                message: error.localizedDescription
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
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Rating",
                message: error.localizedDescription
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

            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Read Status",
                message: error.localizedDescription
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
        } catch {
            comics = []
            alert = LibraryAlertState(
                title: "Failed to Load Collection",
                message: error.localizedDescription
            )
        }
    }

    func remove(_ comic: LibraryComic) {
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
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Collection",
                message: error.localizedDescription
            )
        }
    }

    func removeComics(withIDs comicIDs: [Int64]) -> Bool {
        let uniqueComicIDs = Array(Set(comicIDs))
        guard !uniqueComicIDs.isEmpty else {
            return true
        }

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
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Collection",
                message: error.localizedDescription
            )
            return false
        }
    }

    func removeComicFromLibrary(_ comic: LibraryComic) -> Bool {
        do {
            try comicRemovalService.removeComic(comic, from: descriptor)
            AppHaptics.warning()
            load()
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Remove Comic",
                message: error.localizedDescription
            )
            return false
        }
    }

    func coverURL(for comic: LibraryComic) -> URL? {
        coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL)
    }
}
