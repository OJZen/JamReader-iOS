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

    private var descriptors: [LibraryDescriptor] = []

    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        inspector: SQLiteDatabaseInspector
    ) {
        self.store = store
        self.storageManager = storageManager
        self.inspector = inspector
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
        var duplicateNames: [String] = []

        for url in urls {
            if descriptors.contains(where: { $0.sourcePath == url.standardizedFileURL.path }) {
                duplicateNames.append(url.lastPathComponent)
                continue
            }

            do {
                let descriptor = try storageManager.registerLibrary(at: url)
                descriptors.append(descriptor)
                addedCount += 1
            } catch {
                alert = LibraryAlertState(title: "Failed to Add Library", message: error.localizedDescription)
            }
        }

        do {
            try store.save(descriptors)
            rebuildItems()
        } catch {
            alert = LibraryAlertState(title: "Failed to Save Libraries", message: error.localizedDescription)
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
