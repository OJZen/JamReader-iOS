import Foundation
import os

// MARK: - File-Backed JSON Storage

/// Reusable helper for stores that persist Codable values as JSON files
/// in the Application Support/JamReader/ directory.
struct FileBackedJSONStore {
    let fileManager: FileManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let fileName: String
    let storageDirectoryURL: URL?

    init(
        fileName: String,
        fileManager: FileManager = .default,
        storageDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileName = fileName
        self.storageDirectoryURL = storageDirectoryURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load<T: Decodable>(_ type: T.Type) throws -> T? {
        do {
            let url = try storageFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            AppLog.persistence.error(
                "JSON store load failed file=\(AppLogSanitizer.truncated(fileName), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            throw error
        }
    }

    func save<T: Encodable>(_ value: T) throws {
        do {
            let url = try storageFileURL()
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.persistence.error(
                "JSON store save failed file=\(AppLogSanitizer.truncated(fileName), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            throw error
        }
    }

    func storageFileURL() throws -> URL {
        let directory: URL
        if let storageDirectoryURL {
            directory = storageDirectoryURL
        } else {
            directory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("JamReader", isDirectory: true)
        }

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent(fileName)
    }
}

// MARK: - UserDefaults Codable Helpers

extension UserDefaults {
    func decodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLog.persistence.warning(
                "UserDefaults decode failed key=\(AppLogSanitizer.truncated(key), privacy: .public) type=\(String(describing: type), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return nil
        }
    }

    func setEncodable<T: Encodable>(_ value: T, forKey key: String) {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            AppLog.persistence.warning(
                "UserDefaults encode failed key=\(AppLogSanitizer.truncated(key), privacy: .public) type=\(String(describing: T.self), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return
        }
        set(data, forKey: key)
    }
}
