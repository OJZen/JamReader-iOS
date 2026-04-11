import Foundation

struct ReaderNavigationContext: Equatable {
    let title: String
    var comics: [LibraryComic]

    func currentIndex(for comicID: Int64) -> Int? {
        comics.firstIndex { $0.id == comicID }
    }

    func previousComic(for comicID: Int64) -> LibraryComic? {
        guard let index = currentIndex(for: comicID), index > 0 else {
            return nil
        }

        return comics[index - 1]
    }

    func nextComic(for comicID: Int64) -> LibraryComic? {
        guard let index = currentIndex(for: comicID), index < comics.count - 1 else {
            return nil
        }

        return comics[index + 1]
    }

    func positionText(for comicID: Int64) -> String? {
        guard let index = currentIndex(for: comicID) else {
            return nil
        }

        return "\(index + 1) of \(comics.count)"
    }
}
