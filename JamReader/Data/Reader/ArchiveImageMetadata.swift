import Foundation

struct ArchiveImageMetadata {
    let pageCount: Int
    let coverData: Data?
    let embeddedComicInfoData: Data?

    init(pageCount: Int, coverData: Data?, embeddedComicInfoData: Data? = nil) {
        self.pageCount = pageCount
        self.coverData = coverData
        self.embeddedComicInfoData = embeddedComicInfoData
    }
}
