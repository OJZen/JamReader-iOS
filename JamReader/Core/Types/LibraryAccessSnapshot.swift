import Foundation

struct LibraryAccessSnapshot: Equatable {
    var sourceExists: Bool
    var sourceReadable: Bool
    var sourceWritable: Bool
    var metadataExists: Bool
    var database: LibraryDatabaseSummary
    var lastError: String?

    init(
        sourceExists: Bool = false,
        sourceReadable: Bool = false,
        sourceWritable: Bool = false,
        metadataExists: Bool = false,
        database: LibraryDatabaseSummary = LibraryDatabaseSummary(),
        lastError: String? = nil
    ) {
        self.sourceExists = sourceExists
        self.sourceReadable = sourceReadable
        self.sourceWritable = sourceWritable
        self.metadataExists = metadataExists
        self.database = database
        self.lastError = lastError
    }

    var sourceStatus: String {
        if !sourceExists {
            return "Missing"
        }

        if sourceReadable {
            return "Readable"
        }

        return "No Access"
    }

    var writeStatus: String {
        sourceWritable ? "Writable" : "Read Only"
    }
}
