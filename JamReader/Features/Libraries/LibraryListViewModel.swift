import Combine
import Foundation

struct LibraryListItem: Identifiable, Equatable {
    let descriptor: LibraryDescriptor
    let accessSnapshot: LibraryAccessSnapshot
    let maintenanceRecord: LibraryMaintenanceRecord?

    var id: UUID {
        descriptor.id
    }

    var rowSubtitle: String {
        let comics = accessSnapshot.database.comicCount
        let folders = accessSnapshot.database.folderCount

        if accessSnapshot.database.exists {
            if comics == 0 && folders == 0 {
                return "Empty library"
            }

            return "\(comics) comics · \(folders) folders"
        }

        return accessSnapshot.sourceStatus
    }
}

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published private(set) var items: [LibraryListItem] = []
    @Published var alert: AppAlertState?

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let inspector: SQLiteDatabaseInspector
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: LibraryScanner
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let importedComicsImportService: ImportedComicsImportService

    private var descriptors: [LibraryDescriptor] = []
    private var cancellables = Set<AnyCancellable>()

    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        inspector: SQLiteDatabaseInspector,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: LibraryScanner,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        importedComicsImportService: ImportedComicsImportService
    ) {
        self.store = store
        self.storageManager = storageManager
        self.inspector = inspector
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.maintenanceStatusStore = maintenanceStatusStore
        self.importedComicsImportService = importedComicsImportService
        configureLiveLibraryUpdates()
        reload()
    }

    func reload() {
        do {
            let loadedDescriptors = try store.load()
            let normalizedDescriptors = storageManager.normalizeDescriptors(loadedDescriptors)
            if normalizedDescriptors != loadedDescriptors {
                try store.save(normalizedDescriptors)
            }
            descriptors = normalizedDescriptors
            rebuildItems()
        } catch {
            alert = AppAlertState(title: "Failed to Load Libraries", message: error.userFacingMessage)
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
            alert = AppAlertState(title: "Failed to Save Libraries", message: error.userFacingMessage)
            return
        }

        if addedCount == 0, !duplicateNames.isEmpty, failedItemNames.isEmpty {
            let names = duplicateNames.sorted().joined(separator: ", ")
            alert = AppAlertState(title: "Library Already Added", message: names)
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

        alert = AppAlertState(
            title: addedCount > 0 ? "Libraries Updated" : "Add Finished with Warnings",
            message: messageLines.joined(separator: "\n")
        )
    }

    func createLibrary(named proposedName: String) -> UUID? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = AppAlertState(title: "Invalid Library Name", message: "Enter a name for the new library.")
            return nil
        }

        if descriptors.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            alert = AppAlertState(title: "Library Name Already Used", message: trimmedName)
            return nil
        }

        if trimmedName.localizedCaseInsensitiveCompare(ImportedComicsImportService.defaultImportedComicsLibraryName) == .orderedSame {
            alert = AppAlertState(
                title: "Library Name Reserved",
                message: "\"\(ImportedComicsImportService.defaultImportedComicsLibraryName)\" is reserved for the built-in imported library."
            )
            return nil
        }

        do {
            let descriptor = try storageManager.createManagedLibrary(named: trimmedName)
            descriptors.append(descriptor)
            try store.save(descriptors)
            do {
                let sourceURL = try storageManager.restoreSourceURL(for: descriptor)
                let databaseURL = storageManager.databaseURL(for: descriptor)
                try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
                _ = try libraryScanner.scanLibrary(
                    sourceRootURL: sourceURL,
                    databaseURL: databaseURL
                )
            } catch {
                descriptors.removeAll { $0.id == descriptor.id }
                try? store.save(descriptors)
                try? storageManager.deleteManagedLibraryFilesIfNeeded(for: descriptor)
                throw error
            }
            rebuildItems()
            return descriptor.id
        } catch {
            alert = AppAlertState(title: "Failed to Create Library", message: error.userFacingMessage)
            return nil
        }
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
        removeLibraries(withIDs: idsToRemove)
    }

    func renameLibrary(id: UUID, to proposedName: String) -> Bool {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alert = AppAlertState(title: "Invalid Library Name", message: "Enter a name for this library.")
            return false
        }

        guard let descriptorIndex = descriptors.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if descriptors.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            alert = AppAlertState(title: "Library Name Already Used", message: trimmedName)
            return false
        }

        descriptors[descriptorIndex].name = trimmedName
        descriptors[descriptorIndex].updatedAt = Date()

        do {
            try store.save(descriptors)
            rebuildItems()
            return true
        } catch {
            alert = AppAlertState(title: "Failed to Rename Library", message: error.userFacingMessage)
            return false
        }
    }

    func removeLibrary(id: UUID) {
        removeLibraries(withIDs: [id])
    }

    func presentImportError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return
        }

        alert = AppAlertState(title: "Import Failed", message: error.userFacingMessage)
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

            if (result.createdLibrary || result.hasImportedAnyComics) {
                let action = AppAlertAction.openLibrary(result.importedDestinationID, 1)
                alert = AppAlertState(
                    title: result.importedComicCount > 0 ? "Import Completed" : "Import Finished with Warnings",
                    message: messageLines.joined(separator: "\n"),
                    actionTitle: action.title,
                    action: action
                )
            } else {
                alert = AppAlertState(
                    title: result.importedComicCount > 0 ? "Import Completed" : "Import Finished with Warnings",
                    message: messageLines.joined(separator: "\n")
                )
            }
        } catch {
            alert = AppAlertState(
                title: "Failed to Import Comics",
                message: error.userFacingMessage
            )
        }
    }

    private func removeLibraries(withIDs idsToRemove: [UUID]) {
        let removedDescriptors = descriptors.filter { idsToRemove.contains($0.id) }
        descriptors.removeAll { idsToRemove.contains($0.id) }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = AppAlertState(title: "Failed to Remove Library", message: error.userFacingMessage)
            return
        }

        var fileCleanupFailures: [String] = []
        for descriptor in removedDescriptors {
            do {
                try storageManager.deleteManagedLibraryFilesIfNeeded(for: descriptor)
            } catch {
                fileCleanupFailures.append(descriptor.name)
            }
        }

        if !fileCleanupFailures.isEmpty {
            alert = AppAlertState(
                title: "Library Removed with Warnings",
                message: "Removed the library from JamReader, but failed to delete local files for: \(previewList(from: fileCleanupFailures))."
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
                    maintenanceRecord: maintenanceStatusStore.loadRecord(for: descriptor.id)
                )
            }
    }

    private func configureLiveLibraryUpdates() {
        NotificationCenter.default.publisher(for: .libraryContentsDidChange)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }
}
