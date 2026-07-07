import CryptoKit
import Foundation
import os

enum AppLog {
    nonisolated static let subsystem = "ooou.fun.jamreader"

    nonisolated static let app = Logger(subsystem: subsystem, category: "App")
    nonisolated static let library = Logger(subsystem: subsystem, category: "Library")
    nonisolated static let libraryImport = Logger(subsystem: subsystem, category: "LibraryImport")
    nonisolated static let libraryIndexing = Logger(subsystem: subsystem, category: "LibraryIndexing")
    nonisolated static let reader = Logger(subsystem: subsystem, category: "Reader")
    nonisolated static let remote = Logger(subsystem: subsystem, category: "Remote")
    nonisolated static let remoteCache = Logger(subsystem: subsystem, category: "RemoteCache")
    nonisolated static let remoteNetwork = Logger(subsystem: subsystem, category: "RemoteNetwork")
    nonisolated static let webDAV = Logger(subsystem: subsystem, category: "WebDAV")
    nonisolated static let smb = Logger(subsystem: subsystem, category: "SMB")
    nonisolated static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    nonisolated static let ui = Logger(subsystem: subsystem, category: "UI")
}

enum AppLogSanitizer {
    nonisolated static let defaultTextLimit = 300
    nonisolated static let defaultErrorLimit = 500
    nonisolated static let defaultPathLimit = 240

    nonisolated static func truncated(_ value: String, limit: Int = defaultTextLimit) -> String {
        guard value.count > limit else {
            return value
        }

        guard limit > 0 else {
            return "(truncated, \(value.count) chars)"
        }

        let prefix = String(value.prefix(limit))
        return "\(prefix)...(truncated, \(value.count) chars)"
    }

    nonisolated static func errorDescription(_ error: Error, limit: Int = defaultErrorLimit) -> String {
        truncated(String(describing: error), limit: limit)
    }

    nonisolated static func url(_ url: URL, limit: Int = defaultPathLimit) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil

        let sanitizedURL = components?.url?.absoluteString ?? url.absoluteString
        return truncated(sanitizedURL, limit: limit)
    }

    nonisolated static func path(
        _ rawPath: String,
        preservingLastComponents count: Int = 4,
        limit: Int = defaultPathLimit
    ) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return "<empty>"
        }

        let separator = trimmedPath.contains("/") ? "/" : "\\"
        let isAbsolute = trimmedPath.hasPrefix(separator)
        let components = trimmedPath
            .split(separator: Character(separator))
            .map(String.init)
            .filter { !$0.isEmpty }

        let preservedCount = max(1, count)
        let displayPath: String
        if components.count > preservedCount {
            displayPath = ".../" + components.suffix(preservedCount).joined(separator: "/")
        } else {
            displayPath = (isAbsolute ? "/" : "") + components.joined(separator: "/")
        }

        return truncated(displayPath, limit: limit)
    }

    nonisolated static func namesPreview(
        _ names: [String],
        maxItems: Int = 8,
        limit: Int = defaultTextLimit
    ) -> String {
        guard !names.isEmpty else {
            return "<none>"
        }

        let visibleNames = names.prefix(max(1, maxItems))
        var preview = visibleNames.joined(separator: ", ")
        if names.count > visibleNames.count {
            preview += ", ...(+\(names.count - visibleNames.count) more)"
        }
        return truncated(preview, limit: limit)
    }

    nonisolated static func hashedIdentifier(
        _ value: String,
        prefixLength: Int = 12
    ) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(max(1, prefixLength)))
    }
}
