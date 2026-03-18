import Combine
import Foundation

@MainActor
final class ComicMetadataEditorSheetViewModel: ObservableObject {
    @Published var metadata: LibraryComicMetadata
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isImportingComicInfo = false
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor
    let comic: LibraryComic

    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let comicInfoImportService: ComicInfoImportService
    private let databaseURL: URL
    private var originalMetadata: LibraryComicMetadata?
    private var hasLoaded = false

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
        } catch {
            metadata = LibraryComicMetadata(comic: comic)
            originalMetadata = metadata
            alert = LibraryAlertState(
                title: "Failed to Load Metadata",
                message: error.localizedDescription
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

        do {
            try databaseWriter.updateComicMetadata(
                metadata,
                in: databaseURL
            )
            originalMetadata = metadata
            return comic.applying(metadata: metadata)
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Save Metadata",
                message: error.localizedDescription
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
            defer {
                isImportingComicInfo = false
            }

            do {
                guard let importedComicInfo = try await comicInfoImportService.loadEmbeddedComicInfo(
                    for: descriptor,
                    comic: comic
                ) else {
                    alert = LibraryAlertState(
                        title: "ComicInfo Not Found",
                        message: "The selected comic does not contain an embedded ComicInfo.xml file."
                    )
                    return
                }

                metadata.applyImportedComicInfo(importedComicInfo, policy: policy)
            } catch {
                alert = LibraryAlertState(
                    title: "Failed to Import ComicInfo",
                    message: error.localizedDescription
                )
            }
        }
    }
}
