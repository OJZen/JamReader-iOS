import Foundation

struct LibraryDescriptor: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sourcePath: String
    var sourceBookmarkData: Data
    var storageMode: LibraryStorageMode
    var createdAt: Date
    var updatedAt: Date
}
