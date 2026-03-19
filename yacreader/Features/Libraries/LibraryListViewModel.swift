import Combine
import Foundation

struct LibraryListItem: Identifiable, Equatable {
    let descriptor: LibraryDescriptor
    let accessSnapshot: LibraryAccessSnapshot
    let metadataPath: String
    let databasePath: String

    var id: UUID {
        descriptor.id
    }
}

struct LibraryAlertState: Identifiable {
    enum PrimaryAction {
        case openLibrary(UUID)

        var title: String {
            switch self {
            case .openLibrary:
                return "Open Library"
            }
        }
    }

    let id = UUID()
    let title: String
    let message: String
    let primaryAction: PrimaryAction?

    init(
        title: String,
        message: String,
        primaryAction: PrimaryAction? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
    }
}

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published private(set) var items: [LibraryListItem] = []
    @Published var alert: LibraryAlertState?

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let inspector: SQLiteDatabaseInspector
    private let importedComicsImportService: ImportedComicsImportService

    private var descriptors: [LibraryDescriptor] = []

    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        inspector: SQLiteDatabaseInspector,
        databaseBootstrapper _: LibraryDatabaseBootstrapper,
        libraryScanner _: LibraryScanner,
        importedComicsImportService: ImportedComicsImportService,
        fileManager _: FileManager = .default
    ) {
        self.store = store
        self.storageManager = storageManager
        self.inspector = inspector
        self.importedComicsImportService = importedComicsImportService
        reload()
    }

    func reload() {
        do {
            descriptors = try store.load()
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Load Libraries", message: error.localizedDescription)
        }
    }

    func addLibraryFolders(from urls: [URL]) {
        var addedCount = 0
        var duplicateNames: [String] = []
        var failedItemNames: [String] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            let scopedAccess = standardizedURL.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess {
                    standardizedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else {
                    failedItemNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                if descriptors.contains(where: { $0.sourcePath == standardizedURL.path }) {
                    duplicateNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                let descriptor = try storageManager.registerLibrary(at: standardizedURL)
                descriptors.append(descriptor)
                addedCount += 1
            } catch {
                failedItemNames.append(standardizedURL.lastPathComponent)
            }
        }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Save Libraries", message: error.localizedDescription)
            return
        }

        if addedCount == 0, !duplicateNames.isEmpty, failedItemNames.isEmpty {
            let names = duplicateNames.sorted().joined(separator: ", ")
            alert = LibraryAlertState(title: "Library Already Added", message: names)
            return
        }

        guard addedCount > 0 || !duplicateNames.isEmpty || !failedItemNames.isEmpty else {
            return
        }

        var messageLines: [String] = []

        if addedCount > 0 {
            let libraryWord = addedCount == 1 ? "library" : "libraries"
            messageLines.append("Added \(addedCount) \(libraryWord).")
        }

        if !duplicateNames.isEmpty {
            let folderWord = duplicateNames.count == 1 ? "folder" : "folders"
            messageLines.append("Skipped \(duplicateNames.count) duplicate library \(folderWord).")
        }

        if !failedItemNames.isEmpty {
            messageLines.append("Failed to add \(failedItemNames.count) item(s): \(previewList(from: failedItemNames)).")
        }

        alert = LibraryAlertState(
            title: addedCount > 0 ? "Libraries Updated" : "Add Finished with Warnings",
            message: messageLines.joined(separator: "\n")
        )
    }

    func importComicFiles(
        from urls: [URL],
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) {
        importComicResources(
            from: urls,
            traverseDirectories: false,
            destinationSelection: destinationSelection
        )
    }

    func importComicDirectories(
        from urls: [URL],
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) {
        importComicResources(
            from: urls,
            traverseDirectories: true,
            destinationSelection: destinationSelection
        )
    }

    func removeLibraries(at offsets: IndexSet) {
        let idsToRemove = offsets.map { items[$0].descriptor.id }
        descriptors.removeAll { idsToRemove.contains($0.id) }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Remove Library", message: error.localizedDescription)
        }
    }

    func renameLibrary(id: UUID, to proposedName: String) -> Bool {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = LibraryAlertState(title: "Invalid Library Name", message: "Enter a name for this library.")
            return false
        }

        guard let descriptorIndex = descriptors.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if descriptors.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            alert = LibraryAlertState(title: "Library Name Already Used", message: trimmedName)
            return false
        }

        descriptors[descriptorIndex].name = trimmedName
        descriptors[descriptorIndex].updatedAt = Date()

        do {
            try store.save(descriptors)
            rebuildItems()
            return true
        } catch {
            alert = LibraryAlertState(title: "Failed to Rename Library", message: error.localizedDescription)
            return false
        }
    }

    func removeLibrary(id: UUID) {
        descriptors.removeAll { $0.id == id }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Remove Library", message: error.localizedDescription)
        }
    }

    func presentImportError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return
        }

        alert = LibraryAlertState(title: "Import Failed", message: error.localizedDescription)
    }

    private func importComicResources(
        from urls: [URL],
        traverseDirectories: Bool,
        destinationSelection: LibraryImportDestinationSelection
    ) {
        do {
            let result = try importedComicsImportService.importComicResources(
                from: urls,
                traverseDirectories: traverseDirectories,
                accessSecurityScopedResources: true,
                destinationSelection: destinationSelection
            )
            reload()

            guard result.createdLibrary
                    || result.hasImportedAnyComics
                    || !result.unsupportedItemNames.isEmpty
                    || !result.failedItemNames.isEmpty
            else {
                return
            }

            var messageLines: [String] = []

            if result.createdLibrary {
                messageLines.append("Added \(result.importedDestinationName).")
            }

            if result.importedComicCount > 0 {
                let comicWord = result.importedComicCount == 1 ? "comic file" : "comic files"
                messageLines.append("Imported \(result.importedComicCount) \(comicWord) into \(result.importedDestinationName).")
            }

            if let scanSummary = result.scanSummary {
                messageLines.append(scanSummary.indexedSummaryLine + ".")
            } else if let scanErrorMessage = result.scanErrorMessage {
                messageLines.append("Automatic indexing failed: \(scanErrorMessage)")
                messageLines.append("Open \(result.importedDestinationName) and run Refresh to index the new files.")
            }

            if !result.unsupportedItemNames.isEmpty {
                let itemWord = result.unsupportedItemNames.count == 1 ? "item" : "items"
                messageLines.append("Skipped \(result.unsupportedItemNames.count) unsupported \(itemWord).")
            }

            if !result.failedItemNames.isEmpty {
                messageLines.append("Failed to import \(result.failedItemNames.count) item(s): \(previewList(from: result.failedItemNames)).")
            }

            alert = LibraryAlertState(
                title: result.importedComicCount > 0 ? "Import Completed" : "Import Finished with Warnings",
                message: messageLines.joined(separator: "\n"),
                primaryAction: (result.createdLibrary || result.hasImportedAnyComics)
                    ? .openLibrary(result.importedDestinationID)
                    : nil
            )
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Import Comics",
                message: error.localizedDescription
            )
        }
    }

    private func previewList(from names: [String], limit: Int = 3) -> String {
        let uniqueSortedNames = Array(Set(names)).sorted()
        guard uniqueSortedNames.count > limit else {
            return uniqueSortedNames.joined(separator: ", ")
        }

        let preview = uniqueSortedNames.prefix(limit).joined(separator: ", ")
        return "\(preview), +\(uniqueSortedNames.count - limit) more"
    }

    private func rebuildItems() {
        items = descriptors
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { descriptor in
                LibraryListItem(
                    descriptor: descriptor,
                    accessSnapshot: storageManager.accessSnapshot(for: descriptor, inspector: inspector),
                    metadataPath: storageManager.metadataRootURL(for: descriptor).path,
                    databasePath: storageManager.databaseURL(for: descriptor).path
                )
            }
    }
}
