import Foundation

struct LibraryComicMetadata: Equatable {
    let comicID: Int64
    let fileName: String

    var title: String
    var series: String
    var issueNumber: String
    var volume: String
    var storyArc: String
    var publicationDate: String
    var publisher: String
    var imprint: String
    var format: String
    var languageISO: String
    var type: LibraryFileType
    var writer: String
    var penciller: String
    var inker: String
    var colorist: String
    var letterer: String
    var coverArtist: String
    var editor: String
    var synopsis: String
    var notes: String
    var review: String
    var tags: String
    var characters: String
    var teams: String
    var locations: String

    init(
        comicID: Int64,
        fileName: String,
        title: String = "",
        series: String = "",
        issueNumber: String = "",
        volume: String = "",
        storyArc: String = "",
        publicationDate: String = "",
        publisher: String = "",
        imprint: String = "",
        format: String = "",
        languageISO: String = "",
        type: LibraryFileType = .comic,
        writer: String = "",
        penciller: String = "",
        inker: String = "",
        colorist: String = "",
        letterer: String = "",
        coverArtist: String = "",
        editor: String = "",
        synopsis: String = "",
        notes: String = "",
        review: String = "",
        tags: String = "",
        characters: String = "",
        teams: String = "",
        locations: String = ""
    ) {
        self.comicID = comicID
        self.fileName = fileName
        self.title = title
        self.series = series
        self.issueNumber = issueNumber
        self.volume = volume
        self.storyArc = storyArc
        self.publicationDate = publicationDate
        self.publisher = publisher
        self.imprint = imprint
        self.format = format
        self.languageISO = languageISO
        self.type = type
        self.writer = writer
        self.penciller = penciller
        self.inker = inker
        self.colorist = colorist
        self.letterer = letterer
        self.coverArtist = coverArtist
        self.editor = editor
        self.synopsis = synopsis
        self.notes = notes
        self.review = review
        self.tags = tags
        self.characters = characters
        self.teams = teams
        self.locations = locations
    }

    init(comic: LibraryComic) {
        self.init(
            comicID: comic.id,
            fileName: comic.fileName,
            title: comic.title ?? "",
            series: comic.series ?? "",
            issueNumber: comic.issueNumber ?? "",
            volume: comic.volume ?? "",
            type: comic.type
        )
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? fileName : trimmedTitle
    }
}

struct BatchComicMetadataPatch: Equatable {
    var shouldUpdateType = false
    var type: LibraryFileType = .comic

    var shouldUpdateRating = false
    var rating = 0

    var shouldUpdateSeries = false
    var series = ""

    var shouldUpdateVolume = false
    var volume = ""

    var shouldUpdateStoryArc = false
    var storyArc = ""

    var shouldUpdatePublisher = false
    var publisher = ""

    var shouldUpdateLanguageISO = false
    var languageISO = ""

    var shouldUpdateFormat = false
    var format = ""

    var shouldUpdateTags = false
    var tags = ""

    var hasChanges: Bool {
        shouldUpdateType
            || shouldUpdateRating
            || shouldUpdateSeries
            || shouldUpdateVolume
            || shouldUpdateStoryArc
            || shouldUpdatePublisher
            || shouldUpdateLanguageISO
            || shouldUpdateFormat
            || shouldUpdateTags
    }

    var enabledFieldCount: Int {
        [
            shouldUpdateType,
            shouldUpdateRating,
            shouldUpdateSeries,
            shouldUpdateVolume,
            shouldUpdateStoryArc,
            shouldUpdatePublisher,
            shouldUpdateLanguageISO,
            shouldUpdateFormat,
            shouldUpdateTags,
        ]
        .filter { $0 }
        .count
    }
}

extension LibraryComicMetadata {
    mutating func applyImportedComicInfo(
        _ imported: ImportedComicInfoMetadata,
        policy: ComicInfoImportPolicy = .overwriteExisting
    ) {
        apply(imported.title, to: \.title, policy: policy)
        apply(imported.series, to: \.series, policy: policy)
        apply(imported.issueNumber, to: \.issueNumber, policy: policy)
        apply(imported.volume, to: \.volume, policy: policy)
        apply(imported.storyArc, to: \.storyArc, policy: policy)
        apply(imported.publicationDate, to: \.publicationDate, policy: policy)
        apply(imported.publisher, to: \.publisher, policy: policy)
        apply(imported.imprint, to: \.imprint, policy: policy)
        apply(imported.format, to: \.format, policy: policy)
        apply(imported.languageISO, to: \.languageISO, policy: policy)
        apply(imported.writer, to: \.writer, policy: policy)
        apply(imported.penciller, to: \.penciller, policy: policy)
        apply(imported.inker, to: \.inker, policy: policy)
        apply(imported.colorist, to: \.colorist, policy: policy)
        apply(imported.letterer, to: \.letterer, policy: policy)
        apply(imported.coverArtist, to: \.coverArtist, policy: policy)
        apply(imported.editor, to: \.editor, policy: policy)
        apply(imported.synopsis, to: \.synopsis, policy: policy)
        apply(imported.notes, to: \.notes, policy: policy)
        apply(imported.review, to: \.review, policy: policy)
        apply(imported.tags, to: \.tags, policy: policy)
        apply(imported.characters, to: \.characters, policy: policy)
        apply(imported.teams, to: \.teams, policy: policy)
        apply(imported.locations, to: \.locations, policy: policy)
        apply(imported.type, to: \.type, policy: policy)
    }

    private mutating func apply(
        _ importedValue: String?,
        to keyPath: WritableKeyPath<LibraryComicMetadata, String>,
        policy: ComicInfoImportPolicy
    ) {
        guard let importedValue else {
            return
        }

        if policy == .overwriteExisting || self[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self[keyPath: keyPath] = importedValue
        }
    }

    private mutating func apply(
        _ importedValue: LibraryFileType?,
        to keyPath: WritableKeyPath<LibraryComicMetadata, LibraryFileType>,
        policy: ComicInfoImportPolicy
    ) {
        guard let importedValue else {
            return
        }

        if policy == .overwriteExisting || self[keyPath: keyPath] == .comic {
            self[keyPath: keyPath] = importedValue
        }
    }
}
