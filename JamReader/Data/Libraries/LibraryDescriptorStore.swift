import Foundation

protocol LibraryDescriptorStoring: AnyObject {
    func load() throws -> [LibraryDescriptor]
    func save(_ descriptors: [LibraryDescriptor]) throws
}

final class LibraryDescriptorStore {
    private let repository: LibraryCatalogRepository

    init(fileManager: FileManager = .default) {
        let database = AppLibraryDatabase(fileManager: fileManager)
        let assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
        self.repository = LibraryCatalogRepository(database: database, assetStore: assetStore)
    }

    func load() throws -> [LibraryDescriptor] {
        try repository.loadLibraries()
    }

    func save(_ descriptors: [LibraryDescriptor]) throws {
        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        try repository.replaceLibraries(with: sortedDescriptors)
    }
}

extension LibraryDescriptorStore: LibraryDescriptorStoring {}
