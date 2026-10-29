import Combine
import Foundation

/// One in-progress comic in the library-home aggregate. Comic row IDs are
/// only meaningful inside their own library, so entries are keyed by both.
struct ContinueReadingEntry: Identifiable, Equatable {
    let library: LibraryDescriptor
    let comic: LibraryComic

    var id: String {
        "\(library.id.uuidString):\(comic.id)"
    }
}

/// Continue reading across all local libraries, built from bounded
/// per-library queries. See docs/design-system/components/ContinueReading.
enum LibraryContinueReadingAggregate {
    /// Each library contributes at most this many comics.
    static let perLibraryLimit = 20
    /// Main card plus shelf on the home.
    static let homeLimit = 10

    /// Most recently opened first; comics never opened sort last, ties keep
    /// the library order and each library's own query order.
    static func entries(
        libraries: [LibraryDescriptor],
        perLibraryLimit: Int = perLibraryLimit,
        loadComics: (LibraryDescriptor, Int) throws -> [LibraryComic]
    ) -> [ContinueReadingEntry] {
        var ranked: [(entry: ContinueReadingEntry, libraryIndex: Int, position: Int)] = []
        for (libraryIndex, library) in libraries.enumerated() {
            guard let comics = try? loadComics(library, perLibraryLimit) else {
                continue
            }

            for (position, comic) in comics.prefix(perLibraryLimit).enumerated() {
                ranked.append((ContinueReadingEntry(library: library, comic: comic), libraryIndex, position))
            }
        }

        return ranked.sorted { lhs, rhs in
            let lhsDate = lhs.entry.comic.lastOpenedAt ?? .distantPast
            let rhsDate = rhs.entry.comic.lastOpenedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.libraryIndex != rhs.libraryIndex {
                return lhs.libraryIndex < rhs.libraryIndex
            }
            return lhs.position < rhs.position
        }
        .map(\.entry)
    }

    /// Groups for the "All" page, in library order.
    static func groupedByLibrary(
        _ entries: [ContinueReadingEntry],
        libraryOrder: [LibraryDescriptor]
    ) -> [(library: LibraryDescriptor, entries: [ContinueReadingEntry])] {
        libraryOrder.compactMap { library in
            let libraryEntries = entries.filter { $0.library.id == library.id }
            return libraryEntries.isEmpty ? nil : (library, libraryEntries)
        }
    }

    /// The reader moves between comics of one library only.
    static func navigationComics(
        for entry: ContinueReadingEntry,
        in entries: [ContinueReadingEntry]
    ) -> [LibraryComic] {
        entries
            .filter { $0.library.id == entry.library.id }
            .map(\.comic)
    }
}

/// Loads the aggregate for the library home, its sidebar row and the "All" page.
final class LibraryContinueReadingViewModel: ObservableObject {
    @Published private(set) var entries: [ContinueReadingEntry] = []
    @Published private(set) var libraries: [LibraryDescriptor] = []

    private let databaseReader: LibraryDatabaseReader
    private let storageManager: LibraryStorageManager
    private let coverLocator: LibraryCoverLocator

    init(dependencies: AppDependencies) {
        self.databaseReader = dependencies.libraryDatabaseReader
        self.storageManager = dependencies.libraryStorageManager
        self.coverLocator = dependencies.libraryCoverLocator
    }

    func reload(items: [LibraryListItem]) {
        let readableLibraries = items
            .filter { $0.accessSnapshot.database.exists }
            .map(\.descriptor)
        let databaseReader = databaseReader
        let storageManager = storageManager

        libraries = readableLibraries
        entries = LibraryContinueReadingAggregate.entries(libraries: readableLibraries) { library, limit in
            try databaseReader.loadSpecialListComics(
                databaseURL: storageManager.databaseURL(for: library),
                kind: .reading,
                limit: limit
            )
        }
    }

    var groups: [(library: LibraryDescriptor, entries: [ContinueReadingEntry])] {
        LibraryContinueReadingAggregate.groupedByLibrary(entries, libraryOrder: libraries)
    }

    func coverURL(for entry: ContinueReadingEntry) -> URL? {
        coverLocator.coverURL(
            for: entry.comic,
            metadataRootURL: storageManager.metadataRootURL(for: entry.library)
        )
    }

    func heroSourceID(for entry: ContinueReadingEntry) -> String {
        "library-home-reading-\(entry.id)"
    }
}
