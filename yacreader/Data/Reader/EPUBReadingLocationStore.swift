import Foundation

final class EPUBReadingLocationStore: @unchecked Sendable {
    static let shared = EPUBReadingLocationStore()

    private let defaults: UserDefaults
    private let queue = DispatchQueue(
        label: "YACReader.EPUBReadingLocationStore",
        qos: .utility
    )
    private let keyPrefix = "epub.reader.location."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func location(for document: EBookComicDocument) -> String? {
        queue.sync {
            defaults.string(forKey: key(for: document.documentID))
        }
    }

    func saveLocation(_ location: String?, for document: EBookComicDocument) {
        let key = key(for: document.documentID)
        let sanitized = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.async { [defaults] in
            guard let sanitized, !sanitized.isEmpty else {
                defaults.removeObject(forKey: key)
                return
            }

            defaults.set(sanitized, forKey: key)
        }
    }

    private func key(for documentID: String) -> String {
        keyPrefix + documentID
    }
}
