import Combine
import Foundation
import os

@MainActor
final class ComicMetadataEditorSheetViewModel: ObservableObject, LoadableViewModel {
    @Published var metadata: LibraryComicMetadata
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isImportingComicInfo = false
    @Published private(set) var loadFailed = false
    @Published var alert: AppAlertState?

    let descriptor: LibraryDescriptor
    let comic: LibraryComic

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let comicInfoImportService: ComicInfoImportService
    private let databaseURL: URL
    private var originalMetadata: LibraryComicMetadata?
    private var hasLoaded = false
    private let logger = AppLog.library

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        comicInfoImportService: ComicInfoImportService,
        storageManager: LibraryStorageManager
    ) {
        self.descriptor = descriptor
        self.comic = comic
        self.metadata = LibraryComicMetadata(comic: comic)
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.comicInfoImportService = comicInfoImportService
        self.databaseURL = storageManager.databaseURL(for: descriptor)
    }

    var hasChanges: Bool {
        guard let originalMetadata else {
            return false
        }

        return metadata != originalMetadata
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
            let loadedMetadata = try databaseReader.loadComicMetadata(
                databaseURL: databaseURL,
                comicID: comic.id
            )
            metadata = loadedMetadata
            originalMetadata = loadedMetadata
            logger.info(
                "Library comic metadata loaded libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id)"
            )
        } catch {
            loadFailed = true
            metadata = LibraryComicMetadata(comic: comic)
            originalMetadata = metadata
            logger.error(
                "Library comic metadata load failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Load Metadata",
                message: error.userFacingMessage
            )
        }
    }

    func save() -> LibraryComic? {
        guard !isSaving else {
            return nil
        }

        isSaving = true
        defer {
            isSaving = false
        }

        logger.info(
            "Library comic metadata save requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id)"
        )

        do {
            try databaseWriter.updateComicMetadata(
                metadata,
                in: databaseURL
            )
            originalMetadata = metadata
            logger.info(
                "Library comic metadata save completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id)"
            )
            return comic.applying(metadata: metadata)
        } catch {
            logger.error(
                "Library comic metadata save failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Save Metadata",
                message: error.userFacingMessage
            )
            return nil
        }
    }

    func importEmbeddedComicInfo(using policy: ComicInfoImportPolicy) {
        guard !isImportingComicInfo, !isSaving else {
            return
        }

        isImportingComicInfo = true

        Task { @MainActor in
            logger.info(
                "Library comic metadata ComicInfo import requested libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) policy=\(policy.rawValue, privacy: .public)"
            )

            defer {
                isImportingComicInfo = false
            }

            do {
                guard let importedComicInfo = try await comicInfoImportService.loadEmbeddedComicInfo(
                    for: descriptor,
                    comic: comic
                ) else {
                    logger.warning(
                        "Library comic metadata ComicInfo import not found libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) policy=\(policy.rawValue, privacy: .public)"
                    )
                    alert = AppAlertState(
                        title: "ComicInfo Not Found",
                        message: "The selected comic does not contain an embedded ComicInfo.xml file."
                    )
                    return
                }

                metadata.applyImportedComicInfo(importedComicInfo, policy: policy)
                logger.info(
                    "Library comic metadata ComicInfo import completed libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) policy=\(policy.rawValue, privacy: .public)"
                )
            } catch {
                logger.error(
                    "Library comic metadata ComicInfo import failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) comicID=\(self.comic.id) policy=\(policy.rawValue, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
                alert = AppAlertState(
                    title: "Failed to Import ComicInfo",
                    message: error.userFacingMessage
                )
            }
        }
    }
}
