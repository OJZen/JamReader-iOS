import Foundation

struct ImportedComicInfoMetadata {
    var title: String?
    var issueNumber: String?
    var volume: String?
    var storyArc: String?
    var genre: String?
    var writer: String?
    var penciller: String?
    var inker: String?
    var colorist: String?
    var letterer: String?
    var coverArtist: String?
    var publicationDate: String?
    var publisher: String?
    var format: String?
    var ageRating: String?
    var synopsis: String?
    var characters: String?
    var notes: String?
    var comicVineID: String?
    var editor: String?
    var imprint: String?
    var teams: String?
    var locations: String?
    var series: String?
    var alternateSeries: String?
    var alternateNumber: String?
    var languageISO: String?
    var seriesGroup: String?
    var mainCharacterOrTeam: String?
    var review: String?
    var tags: String?
    var count: Int?
    var alternateCount: Int?
    var type: LibraryFileType?
    var isColor: Bool?

    var hasContent: Bool {
        title != nil ||
        issueNumber != nil ||
        volume != nil ||
        storyArc != nil ||
        genre != nil ||
        writer != nil ||
        penciller != nil ||
        inker != nil ||
        colorist != nil ||
        letterer != nil ||
        coverArtist != nil ||
        publicationDate != nil ||
        publisher != nil ||
        format != nil ||
        ageRating != nil ||
        synopsis != nil ||
        characters != nil ||
        notes != nil ||
        comicVineID != nil ||
        editor != nil ||
        imprint != nil ||
        teams != nil ||
        locations != nil ||
        series != nil ||
        alternateSeries != nil ||
        alternateNumber != nil ||
        languageISO != nil ||
        seriesGroup != nil ||
        mainCharacterOrTeam != nil ||
        review != nil ||
        tags != nil ||
        count != nil ||
        alternateCount != nil ||
        type != nil ||
        isColor != nil
    }
}

struct ComicInfoXMLParser {
    func parse(_ data: Data) -> ImportedComicInfoMetadata? {
        let document = XMLHash.config { options in
            options.caseInsensitive = true
            options.shouldProcessNamespaces = true
            options.detectParsingErrors = true
        }.parse(data)

        let root = document["ComicInfo"]
        guard root.element != nil else {
            return nil
        }

        var metadata = ImportedComicInfoMetadata()
        metadata.title = textValue(named: "Title", in: root)
        metadata.issueNumber = textValue(named: "Number", in: root)
        metadata.volume = textValue(named: "Volume", in: root)
        metadata.storyArc = textValue(named: "StoryArc", in: root)
        metadata.genre = textValue(named: "Genre", in: root)
        metadata.writer = multiValueText(named: "Writer", in: root)
        metadata.penciller = multiValueText(named: "Penciller", in: root)
        metadata.inker = multiValueText(named: "Inker", in: root)
        metadata.colorist = multiValueText(named: "Colorist", in: root)
        metadata.letterer = multiValueText(named: "Letterer", in: root)
        metadata.coverArtist = multiValueText(named: "CoverArtist", in: root)
        metadata.publisher = textValue(named: "Publisher", in: root)
        metadata.format = textValue(named: "Format", in: root)
        metadata.ageRating = textValue(named: "AgeRating", in: root)
        metadata.synopsis = textValue(named: "Summary", in: root)
        metadata.characters = multiValueText(named: "Characters", in: root)
        metadata.notes = textValue(named: "Notes", in: root)
        metadata.editor = textValue(named: "Editor", in: root)
        metadata.imprint = textValue(named: "Imprint", in: root)
        metadata.teams = multiValueText(named: "Teams", in: root)
        metadata.locations = multiValueText(named: "Locations", in: root)
        metadata.series = textValue(named: "Series", in: root)
        metadata.alternateSeries = textValue(named: "AlternateSeries", in: root)
        metadata.alternateNumber = textValue(named: "AlternateNumber", in: root)
        metadata.languageISO = textValue(named: "LanguageISO", in: root)
        metadata.seriesGroup = textValue(named: "SeriesGroup", in: root)
        metadata.mainCharacterOrTeam = textValue(named: "MainCharacterOrTeam", in: root)
        metadata.review = textValue(named: "Review", in: root)
        metadata.tags = multiValueText(named: "Tags", in: root)
        metadata.count = intValue(named: "Count", in: root)
        metadata.alternateCount = intValue(named: "AlternateCount", in: root)
        metadata.publicationDate = consolidatedDate(in: root)
        metadata.type = fileType(in: root)
        metadata.isColor = colorValue(in: root)
        metadata.comicVineID = comicVineID(in: root)

        return metadata.hasContent ? metadata : nil
    }

    private func textValue(named name: String, in root: XMLIndexer) -> String? {
        normalized(root[name].element?.text)
    }

    private func multiValueText(named name: String, in root: XMLIndexer) -> String? {
        guard let value = normalized(root[name].element?.text) else {
            return nil
        }

        return value.replacingOccurrences(of: ", ", with: "\n")
    }

    private func intValue(named name: String, in root: XMLIndexer) -> Int? {
        guard let rawValue = textValue(named: name, in: root) else {
            return nil
        }

        return Int(rawValue)
    }

    private func consolidatedDate(in root: XMLIndexer) -> String? {
        let year = intValue(named: "Year", in: root)
        let month = intValue(named: "Month", in: root)
        let day = intValue(named: "Day", in: root)

        guard year != nil || month != nil || day != nil else {
            return nil
        }

        return "\(day ?? 1)/\(month ?? 1)/\(year ?? 0)"
    }

    private func fileType(in root: XMLIndexer) -> LibraryFileType? {
        guard let value = normalized(root["Manga"].element?.text)?.lowercased() else {
            return nil
        }

        switch value {
        case "yes", "yesandrighttoleft":
            return .manga
        case "no":
            return .comic
        default:
            return nil
        }
    }

    private func colorValue(in root: XMLIndexer) -> Bool? {
        guard let value = normalized(root["BlackAndWhite"].element?.text)?.lowercased() else {
            return nil
        }

        switch value {
        case "yes":
            return false
        case "no":
            return true
        default:
            return nil
        }
    }

    private func comicVineID(in root: XMLIndexer) -> String? {
        guard let webValue = normalized(root["Web"].element?.text) else {
            return nil
        }

        let sanitized = webValue.replacingOccurrences(of: "/", with: "")
        guard let lastSegment = sanitized.split(separator: "-").last else {
            return nil
        }

        let comicVineID = String(lastSegment)
        return comicVineID.isEmpty ? nil : comicVineID
    }

    private func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
