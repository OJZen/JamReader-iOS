import Foundation

struct LibraryFolder: Identifiable, Hashable {
    let id: Int64
    let parentID: Int64
    let name: String
    let path: String
    let finished: Bool
    let completed: Bool
    let numChildren: Int?
    let firstChildHash: String?
    let customImage: String?
    let type: LibraryFileType
    let addedAt: Date?
    let updatedAt: Date?

    var previewCoverAssetKeys: [String] {
        guard let customImage,
              !customImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }

        return customImage
            .split(separator: "|")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    var isRoot: Bool {
        id == 1 || parentID == 0
    }

    var childCountText: String? {
        guard let numChildren else {
            return nil
        }

        return numChildren == 1 ? "1 item" : "\(numChildren) items"
    }
}
