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
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class LibraryListViewModel: ObservableObject {
    @Published private(set) var items: [LibraryListItem] = []
    @Published var alert: LibraryAlertState?

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let inspector: SQLiteDatabaseInspector
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: LibraryScanner
    private let fileManager: FileManager

    private let supportedComicFileExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf"
    ]
    private let importedComicsLibraryName = "Imported Comics"

    private var descriptors: [LibraryDescriptor] = []

    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        inspector: SQLiteDatabaseInspector,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: LibraryScanner,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.storageManager = storageManager
        self.inspector = inspector
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.fileManager = fileManager
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

    func importLibraries(from urls: [URL]) {
        var addedCount = 0
        var importedComicCount = 0
        var duplicateNames: [String] = []
        var unsupportedFileNames: [String] = []
        var failedItemNames: [String] = []
        var comicFileURLs: [URL] = []
        var importedLibraryForScan: LibraryDescriptor?
        var importedLibraryScanSummary: LibraryScanSummary?
        var importedLibraryScanError: Error?

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

                if values.isDirectory == true {
                    if descriptors.contains(where: { $0.sourcePath == standardizedURL.path }) {
                        duplicateNames.append(standardizedURL.lastPathComponent)
                        continue
                    }

                    let descriptor = try storageManager.registerLibrary(at: standardizedURL)
                    descriptors.append(descriptor)
                    addedCount += 1
                    continue
                }

                let fileExtension = standardizedURL.pathExtension.lowercased()
                guard supportedComicFileExtensions.contains(fileExtension) else {
                    unsupportedFileNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                comicFileURLs.append(standardizedURL)
            } catch {
                failedItemNames.append(standardizedURL.lastPathComponent)
            }
        }

        if !comicFileURLs.isEmpty {
            do {
                let (importedLibrary, wasCreated) = try ensureImportedComicsLibrary()
                if wasCreated {
                    addedCount += 1
                }
                importedLibraryForScan = importedLibrary

                let destinationDirectoryURL = URL(
                    fileURLWithPath: importedLibrary.sourcePath,
                    isDirectory: true
                )

                for comicFileURL in comicFileURLs {
                    let scopedAccess = comicFileURL.startAccessingSecurityScopedResource()
                    defer {
                        if scopedAccess {
                            comicFileURL.stopAccessingSecurityScopedResource()
                        }
                    }

                    let destinationURL = uniqueDestinationURL(
                        for: comicFileURL,
                        in: destinationDirectoryURL
                    )

                    do {
                        try fileManager.copyItem(at: comicFileURL, to: destinationURL)
                        importedComicCount += 1
                    } catch {
                        failedItemNames.append(comicFileURL.lastPathComponent)
                    }
                }
            } catch {
                alert = LibraryAlertState(
                    title: "Failed to Import Comics",
                    message: error.localizedDescription
                )
            }
        }

        if importedComicCount > 0, let importedLibraryForScan {
            do {
                importedLibraryScanSummary = try ensureIndexedLibrary(for: importedLibraryForScan)
            } catch {
                importedLibraryScanError = error
            }
        }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Save Libraries", message: error.localizedDescription)
            return
        }

        if importedComicCount > 0 || !unsupportedFileNames.isEmpty || !failedItemNames.isEmpty {
            var messageLines: [String] = []

            if addedCount > 0 {
                let libraryWord = addedCount == 1 ? "library" : "libraries"
                messageLines.append("Added \(addedCount) \(libraryWord).")
            }

            if importedComicCount > 0 {
                let comicWord = importedComicCount == 1 ? "comic file" : "comic files"
                messageLines.append("Imported \(importedComicCount) \(comicWord) into \(importedComicsLibraryName).")
                if let importedLibraryScanSummary {
                    messageLines.append(importedLibraryScanSummary.indexedSummaryLine + ".")
                } else if let importedLibraryScanError {
                    messageLines.append("Automatic indexing failed: \(importedLibraryScanError.localizedDescription)")
                    messageLines.append("Open Imported Comics and run Refresh to index the new files.")
                }
            }

            if !duplicateNames.isEmpty {
                let folderWord = duplicateNames.count == 1 ? "folder" : "folders"
                messageLines.append("Skipped \(duplicateNames.count) duplicate library \(folderWord).")
            }

            if !unsupportedFileNames.isEmpty {
                let fileWord = unsupportedFileNames.count == 1 ? "file" : "files"
                messageLines.append("Skipped \(unsupportedFileNames.count) unsupported \(fileWord).")
            }

            if !failedItemNames.isEmpty {
                messageLines.append("Failed to import \(failedItemNames.count) item(s): \(previewList(from: failedItemNames)).")
            }

            alert = LibraryAlertState(
                title: importedComicCount > 0 ? "Import Completed" : "Import Finished with Warnings",
                message: messageLines.joined(separator: "\n")
            )
            return
        }

        if addedCount == 0, !duplicateNames.isEmpty {
            let names = duplicateNames.sorted().joined(separator: ", ")
            alert = LibraryAlertState(title: "Library Already Added", message: names)
        }
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
        alert = LibraryAlertState(title: "Import Failed", message: error.localizedDescription)
    }

    private func ensureImportedComicsLibrary() throws -> (descriptor: LibraryDescriptor, wasCreated: Bool) {
        let rootURL = try storageManager
            .ensureImportedComicsLibraryRootURL()
            .standardizedFileURL

        if let existingDescriptor = descriptors.first(where: { $0.sourcePath == rootURL.path }) {
            return (existingDescriptor, false)
        }

        let descriptor = try storageManager.registerLibrary(
            at: rootURL,
            suggestedName: importedComicsLibraryName
        )
        descriptors.append(descriptor)
        return (descriptor, true)
    }

    private func ensureIndexedLibrary(for descriptor: LibraryDescriptor) throws -> LibraryScanSummary {
        let databaseURL = storageManager.databaseURL(for: descriptor)
        let accessSession = try storageManager.makeAccessSession(for: descriptor)
        return try withExtendedLifetime(accessSession) {
            try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
            return try libraryScanner.rescanLibrary(
                sourceRootURL: accessSession.sourceURL,
                databaseURL: databaseURL
            )
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        var counter = 1

        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) (\(counter))"
            } else {
                candidateName = "\(baseName) (\(counter)).\(fileExtension)"
            }

            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            counter += 1
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
