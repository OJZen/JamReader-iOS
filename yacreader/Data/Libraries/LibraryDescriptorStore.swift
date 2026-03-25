import Foundation

final class LibraryDescriptorStore {
    private let storage: FileBackedJSONStore

    init(fileManager: FileManager = .default) {
        self.storage = FileBackedJSONStore(fileName: "libraries.json", fileManager: fileManager)
    }

    func load() throws -> [LibraryDescriptor] {
        try storage.load([LibraryDescriptor].self) ?? []
    }

    func save(_ descriptors: [LibraryDescriptor]) throws {
        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        try storage.save(sortedDescriptors)
    }
}
