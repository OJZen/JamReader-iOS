import Combine
import Foundation
import UIKit

@MainActor
final class LibrarySpecialCollectionViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var comics: [LibraryComic] = []
    @Published private(set) var isLoading = false
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor
    let kind: LibrarySpecialCollectionKind

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let storageManager: LibraryStorageManager
    private let coverLocator: LibraryCoverLocator

    private let databaseURL: URL
    private let metadataRootURL: URL
    private var hasLoaded = false
    private var recentDays = LibraryRecentWindowOption.defaultOption.dayCount

    init(
        descriptor: LibraryDescriptor,
        kind: LibrarySpecialCollectionKind,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        storageManager: LibraryStorageManager,
        coverLocator: LibraryCoverLocator
    ) {
        self.descriptor = descriptor
        self.kind = kind
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.storageManager = storageManager
        self.coverLocator = coverLocator
        self.databaseURL = storageManager.databaseURL(for: descriptor)
        self.metadataRootURL = storageManager.metadataRootURL(for: descriptor)
    }

    var navigationTitle: String {
        kind.title
    }

    var summaryText: String {
        kind.summaryText(count: comics.count)
    }

    var currentRecentDays: Int {
        recentDays
    }

    func applyUpdatedComic(_ updatedComic: LibraryComic) {
        comics = comics.compactMap { comic in
            let resolvedComic = comic.id == updatedComic.id ? updatedComic : comic
            return resolvedComic.belongs(
                to: kind,
                recentDays: recentDays
            ) ? resolvedComic : nil
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

            let now = Date()
            comics = comics.compactMap { comic in
                let updatedComic = selectedComicIDs.contains(comic.id) ? comic.updatingFavorite(isFavorite) : comic
                return updatedComic.belongs(
                    to: kind,
                    recentDays: recentDays,
                    now: now
                ) ? updatedComic : nil
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
            comics = comics.compactMap { comic in
                let updatedComic = selectedComicIDs.contains(comic.id)
                    ? comic.updatingReadState(isRead, lastOpenedAt: now)
                    : comic

                return updatedComic.belongs(
                    to: kind,
                    recentDays: recentDays,
                    now: now
                ) ? updatedComic : nil
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

    func setRecentDays(_ days: Int) {
        let normalizedDays = max(1, days)
        guard recentDays != normalizedDays else {
            return
        }

        recentDays = normalizedDays

        guard hasLoaded, kind == .recent else {
            return
        }

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
            comics = try databaseReader.loadSpecialListComics(
                databaseURL: databaseURL,
                kind: kind,
                recentDays: recentDays
            )
        } catch {
            comics = []
            alert = LibraryAlertState(title: "Failed to Load Collection", message: error.localizedDescription)
        }
    }

    func coverURL(for comic: LibraryComic) -> URL? {
        coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL)
    }

    func coverSource(for comic: LibraryComic) -> LocalComicCoverSource? {
        let sourceRootURL = URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
        return LocalComicCoverSource(
            fileURL: resolveComicFileURL(for: comic, sourceRootURL: sourceRootURL),
            cacheURL: coverLocator.plannedCoverURL(for: comic, metadataRootURL: metadataRootURL)
        )
    }

    func heroSourceID(for comic: LibraryComic) -> String {
        "library-special-comic-\(descriptor.id.uuidString)-\(comic.id)"
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
}
