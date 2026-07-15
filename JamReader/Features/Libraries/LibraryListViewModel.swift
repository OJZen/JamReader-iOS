import Combine
import Foundation
import os

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

private enum ManagedLibraryCreationError: LocalizedError {
    case rollbackFailed

    var errorDescription: String? {
        "Library setup failed, and its catalog entry could not be rolled back. Local files were kept for recovery."
    }
}

@MainActor
final class LibraryListViewModel: ObservableObject {
    private static let liveReloadDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(900)
    nonisolated private static let liveImportNotificationLibraryIDKey = "libraryID"

    @Published private(set) var items: [LibraryListItem] = []
    @Published private(set) var importProgress: ImportedComicsImportProgress?
    @Published private(set) var isImporting = false
    @Published var alert: AppAlertState?

    private let store: any LibraryDescriptorStoring
    private let storageManager: LibraryStorageManager
    private let inspector: SQLiteDatabaseInspector
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: any LibraryScanning
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let importedComicsImportService: ImportedComicsImportService
    private let remoteBackgroundImportController: RemoteBackgroundImportController
    private let logger = AppLog.library

    private var descriptors: [LibraryDescriptor] = []
    private var cancellables = Set<AnyCancellable>()
    private var importTask: Task<Void, Never>?
    private var importCancellationController: LibraryImportCancellationController?
    private var activeImportID: UUID?

    init(
        store: any LibraryDescriptorStoring,
        storageManager: LibraryStorageManager,
        inspector: SQLiteDatabaseInspector,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: any LibraryScanning,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        importedComicsImportService: ImportedComicsImportService,
        remoteBackgroundImportController: RemoteBackgroundImportController
    ) {
        self.store = store
        self.storageManager = storageManager
        self.inspector = inspector
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.maintenanceStatusStore = maintenanceStatusStore
        self.importedComicsImportService = importedComicsImportService
        self.remoteBackgroundImportController = remoteBackgroundImportController
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
            logger.info("Library list loaded count=\(self.descriptors.count)")
        } catch {
            logger.error(
                "Library list load failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(title: "Failed to Load Libraries", message: error.userFacingMessage)
        }
    }

    func addLibraryFolders(from urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        logger.info("Library folders add requested count=\(urls.count)")
        var addedCount = 0
        var duplicateNames: [String] = []
        var failedItemNames: [String] = []
        var candidateDescriptors = descriptors
        var addedDescriptors: [LibraryDescriptor] = []

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

                if candidateDescriptors.contains(where: { $0.sourcePath == standardizedURL.path }) {
                    duplicateNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                let descriptor = try storageManager.registerLibrary(at: standardizedURL)
                candidateDescriptors.append(descriptor)
                addedDescriptors.append(descriptor)
                addedCount += 1
            } catch {
                failedItemNames.append(standardizedURL.lastPathComponent)
            }
        }

        do {
            try store.save(candidateDescriptors)
            descriptors = candidateDescriptors
            rebuildItems()
        } catch {
            addedDescriptors.forEach(storageManager.deleteLibraryAssets)
            logger.error(
                "Library folders add failed while saving added=\(addedCount) duplicates=\(duplicateNames.count) failed=\(failedItemNames.count) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(title: "Failed to Save Libraries", message: error.userFacingMessage)
            return
        }

        logger.info(
            "Library folders add completed added=\(addedCount) duplicates=\(duplicateNames.count) failed=\(failedItemNames.count) duplicateNames=\(AppLogSanitizer.namesPreview(duplicateNames), privacy: .public) failedNames=\(AppLogSanitizer.namesPreview(failedItemNames), privacy: .public)"
        )

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
            messageLines.append("Failed to add \(failedItemNames.count) item(s): \(NamePreviewFormatter.preview(from: failedItemNames)).")
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

        guard beginExclusiveLibraryStorageOperation() else {
            return nil
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        logger.info("Managed library create requested name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public)")
        do {
            let descriptor = try storageManager.createManagedLibrary(named: trimmedName)
            let candidateDescriptors = descriptors + [descriptor]
            do {
                try store.save(candidateDescriptors)
            } catch {
                try? storageManager.deleteManagedLibraryFilesIfNeeded(for: descriptor)
                storageManager.deleteLibraryAssets(for: descriptor)
                throw error
            }
            do {
                let sourceURL = try storageManager.restoreSourceURL(for: descriptor)
                let databaseURL = storageManager.databaseURL(for: descriptor)
                try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
                _ = try libraryScanner.scanLibrary(
                    sourceRootURL: sourceURL,
                    databaseURL: databaseURL,
                    cancellationCheck: nil,
                    progressHandler: nil
                )
            } catch {
                let setupError = error
                do {
                    try store.save(descriptors)
                } catch {
                    logger.warning(
                        "Managed library create rollback failed item=descriptorStore id=\(descriptor.id.uuidString, privacy: .public) name=\(AppLogSanitizer.truncated(descriptor.name), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                    )
                    throw ManagedLibraryCreationError.rollbackFailed
                }
                do {
                    try storageManager.deleteManagedLibraryFilesIfNeeded(for: descriptor)
                } catch {
                    logger.warning(
                        "Managed library create rollback failed item=managedFiles id=\(descriptor.id.uuidString, privacy: .public) name=\(AppLogSanitizer.truncated(descriptor.name), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                    )
                }
                storageManager.deleteLibraryAssets(for: descriptor)
                throw setupError
            }
            descriptors = candidateDescriptors
            rebuildItems()
            logger.info(
                "Managed library create completed id=\(descriptor.id.uuidString, privacy: .public) name=\(AppLogSanitizer.truncated(descriptor.name), privacy: .public)"
            )
            return descriptor.id
        } catch {
            logger.error(
                "Managed library create failed name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(title: "Failed to Create Library", message: error.userFacingMessage)
            return nil
        }
    }

    func importComicFiles(
        from urls: [URL],
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) {
        startComicImport(
            from: urls,
            traverseDirectories: false,
            destinationSelection: destinationSelection
        )
    }

    func importComicDirectories(
        from urls: [URL],
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) {
        startComicImport(
            from: urls,
            traverseDirectories: true,
            destinationSelection: destinationSelection
        )
    }

    @discardableResult
    func removeLibraries(at offsets: IndexSet) -> Bool {
        let idsToRemove = offsets.map { items[$0].descriptor.id }
        return removeLibraries(withIDs: idsToRemove)
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

        guard beginExclusiveLibraryStorageOperation() else {
            return false
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        var candidateDescriptors = descriptors
        candidateDescriptors[descriptorIndex].name = trimmedName
        candidateDescriptors[descriptorIndex].updatedAt = Date()

        do {
            try store.save(candidateDescriptors)
            descriptors = candidateDescriptors
            rebuildItems()
            logger.info(
                "Library rename completed id=\(id.uuidString, privacy: .public) name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public)"
            )
            return true
        } catch {
            logger.error(
                "Library rename failed id=\(id.uuidString, privacy: .public) name=\(AppLogSanitizer.truncated(trimmedName), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(title: "Failed to Rename Library", message: error.userFacingMessage)
            return false
        }
    }

    @discardableResult
    func removeLibrary(id: UUID) -> Bool {
        removeLibraries(withIDs: [id])
    }

    @discardableResult
    func removeLibraries(ids: [UUID]) -> Bool {
        removeLibraries(withIDs: ids)
    }

    func presentImportError(_ error: Error) {
        if error is CancellationError {
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return
        }

        alert = AppAlertState(title: "Import Failed", message: error.userFacingMessage)
    }

    func cancelComicImport() {
        importCancellationController?.cancel()
        importTask?.cancel()
    }

    private func startComicImport(
        from urls: [URL],
        traverseDirectories: Bool,
        destinationSelection: LibraryImportDestinationSelection
    ) {
        guard !urls.isEmpty, !isImporting else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }

        let cancellationController = LibraryImportCancellationController()
        let importID = UUID()
        importCancellationController = cancellationController
        activeImportID = importID
        isImporting = true
        importProgress = nil
        alert = nil

        importTask = Task {
            await importComicResources(
                from: urls,
                traverseDirectories: traverseDirectories,
                destinationSelection: destinationSelection,
                cancellationController: cancellationController,
                importID: importID
            )
        }
    }

    private func importComicResources(
        from urls: [URL],
        traverseDirectories: Bool,
        destinationSelection: LibraryImportDestinationSelection,
        cancellationController: LibraryImportCancellationController,
        importID: UUID
    ) async {
        defer {
            isImporting = false
            importProgress = nil
            importCancellationController = nil
            importTask = nil
            activeImportID = nil
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        do {
            let result = try await importedComicsImportService.importComicResourcesAsync(
                from: urls,
                traverseDirectories: traverseDirectories,
                accessSecurityScopedResources: true,
                destinationSelection: destinationSelection,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard self?.activeImportID == importID else {
                            return
                        }
                        self?.importProgress = progress
                    }
                },
                cancellationCheck: cancellationController.checkCancelled
            )
            reload()

            guard result.createdLibrary
                    || result.hasImportedAnyComics
                    || !result.unsupportedItemNames.isEmpty
                    || !result.failedItemNames.isEmpty
            else {
                return
            }

            let messageLines = result.completionMessageLines()

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
        } catch is CancellationError {
            logger.notice("Local comic import canceled")
        } catch {
            logger.error(
                "Local comic import failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Import Comics",
                message: error.userFacingMessage
            )
        }
    }

    private func removeLibraries(withIDs idsToRemove: [UUID]) -> Bool {
        let removedDescriptors = descriptors.filter { idsToRemove.contains($0.id) }
        let removedNames = removedDescriptors.map(\.name)

        guard !removedDescriptors.isEmpty else {
            return true
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return false
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        if !removedDescriptors.isEmpty {
            logger.notice(
                "Library remove requested count=\(removedDescriptors.count, privacy: .public) ids=\(AppLogSanitizer.namesPreview(removedDescriptors.map { $0.id.uuidString }), privacy: .public) names=\(AppLogSanitizer.namesPreview(removedNames), privacy: .public)"
            )
        }
        let updatedDescriptors = descriptors.filter { !idsToRemove.contains($0.id) }

        do {
            try store.save(updatedDescriptors)
            descriptors = updatedDescriptors
            rebuildItems()
            if !removedDescriptors.isEmpty {
                logger.info(
                    "Library remove completed count=\(removedDescriptors.count, privacy: .public) names=\(AppLogSanitizer.namesPreview(removedNames), privacy: .public)"
                )
            }
        } catch {
            logger.error(
                "Library remove failed count=\(removedDescriptors.count, privacy: .public) names=\(AppLogSanitizer.namesPreview(removedNames), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(title: "Failed to Remove Library", message: error.userFacingMessage)
            return false
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
            logger.warning(
                "Library remove file cleanup failed count=\(fileCleanupFailures.count, privacy: .public) names=\(AppLogSanitizer.namesPreview(fileCleanupFailures), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Library Removed with Warnings",
                message: "Removed the library from JamReader, but failed to delete local files for: \(NamePreviewFormatter.preview(from: fileCleanupFailures))."
            )
        }
        return true
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

    private func rebuildItems() {
        items = descriptors
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map(makeItem(for:))
    }

    private func makeItem(for descriptor: LibraryDescriptor) -> LibraryListItem {
        LibraryListItem(
            descriptor: descriptor,
            accessSnapshot: storageManager.accessSnapshot(for: descriptor, inspector: inspector),
            maintenanceRecord: maintenanceStatusStore.loadRecord(for: descriptor.id)
        )
    }

    private func refreshItem(for libraryID: UUID) {
        guard let descriptor = descriptors.first(where: { $0.id == libraryID }) else {
            reload()
            return
        }

        let refreshedItem = makeItem(for: descriptor)
        if let itemIndex = items.firstIndex(where: { $0.id == libraryID }) {
            items[itemIndex] = refreshedItem
        } else {
            rebuildItems()
        }
    }

    private func configureLiveLibraryUpdates() {
        NotificationCenter.default.publisher(for: .libraryContentsDidChange)
            .map { notification in
                notification.userInfo?[Self.liveImportNotificationLibraryIDKey] as? UUID
            }
            .debounce(for: Self.liveReloadDebounce, scheduler: RunLoop.main)
            .sink { [weak self] libraryID in
                guard let self else {
                    return
                }

                guard let libraryID else {
                    self.reload()
                    return
                }

                self.refreshItem(for: libraryID)
            }
            .store(in: &cancellables)
    }
}
