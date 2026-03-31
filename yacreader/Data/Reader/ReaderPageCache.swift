import CryptoKit
import Foundation

struct ReaderPageCacheKey: Sendable {
    let namespace: String
    let pageIdentifier: String

    nonisolated fileprivate var storageKey: String {
        ReaderPageCache.hashedKey(for: "\(namespace)|\(pageIdentifier)")
    }
}

actor ReaderPageCache {
    static let shared = ReaderPageCache()

    private let fileManager: FileManager
    private let memoryCache: NSCache<NSString, NSData>
    private let maxDiskBytes: Int64
    private let diskRootURL: URL

    private var hasPreparedDiskRoot = false
    private var lastTrimDate = Date.distantPast

    init(
        fileManager: FileManager = .default,
        maxDiskBytes: Int64 = 512 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.maxDiskBytes = maxDiskBytes

        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 48
        cache.totalCostLimit = 192 * 1_024 * 1_024
        self.memoryCache = cache

        let cachesURL = (try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.diskRootURL = cachesURL
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("ReaderPages", isDirectory: true)
    }

    nonisolated static func namespace(for documentURL: URL) -> String {
        let standardizedURL = documentURL.standardizedFileURL
        let values = try? standardizedURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        let fileSize = values?.fileSize ?? 0
        let modificationInterval = Int64(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let resourceID = values?.fileResourceIdentifier.map { "\($0)" } ?? ""
        let rawNamespace = "\(standardizedURL.path)|\(fileSize)|\(modificationInterval)|\(resourceID)"
        return hashedKey(for: rawNamespace)
    }

    func data(for key: ReaderPageCacheKey) async -> Data? {
        let storageKey = key.storageKey as NSString
        if let cachedValue = memoryCache.object(forKey: storageKey) {
            return Data(referencing: cachedValue)
        }

        do {
            try prepareDiskRootIfNeeded()
        } catch {
            return nil
        }

        let fileURL = fileURL(for: key.storageKey)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            memoryCache.setObject(data as NSData, forKey: storageKey, cost: data.count)
            touch(fileURL)
            return data
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    func store(_ data: Data, for key: ReaderPageCacheKey) async {
        let storageKey = key.storageKey as NSString
        memoryCache.setObject(data as NSData, forKey: storageKey, cost: data.count)

        do {
            try prepareDiskRootIfNeeded()
            let fileURL = fileURL(for: key.storageKey)
            try data.write(to: fileURL, options: [.atomic])
            touch(fileURL)
            trimIfNeeded()
        } catch {
            return
        }
    }

    private func prepareDiskRootIfNeeded() throws {
        guard !hasPreparedDiskRoot else {
            return
        }

        if !fileManager.fileExists(atPath: diskRootURL.path) {
            try fileManager.createDirectory(at: diskRootURL, withIntermediateDirectories: true)
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableRootURL = diskRootURL
        try? mutableRootURL.setResourceValues(resourceValues)

        hasPreparedDiskRoot = true
    }

    private func trimIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastTrimDate) >= 30 else {
            return
        }
        lastTrimDate = now

        // Capture values before leaving the actor so the background task
        // doesn't need to hop back onto the actor to read them.
        let diskRootURL = self.diskRootURL
        let maxDiskBytes = self.maxDiskBytes
        let fileManager = self.fileManager

        Task.detached(priority: .background) {
            Self.performTrim(diskRootURL: diskRootURL, maxDiskBytes: maxDiskBytes, fileManager: fileManager)
        }
    }

    // Runs entirely off the actor — only touches the file system.
    nonisolated private static func performTrim(diskRootURL: URL, maxDiskBytes: Int64, fileManager: FileManager) {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .creationDateKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: diskRootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var files: [(url: URL, size: Int64, lastAccess: Date)] = []
        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: resourceKeys)
            guard values?.isRegularFile == true else { continue }

            let fileSize = Int64(values?.fileSize ?? 0)
            let lastAccess = values?.contentAccessDate
                ?? values?.contentModificationDate
                ?? values?.creationDate
                ?? .distantPast

            files.append((fileURL, fileSize, lastAccess))
            totalSize += fileSize
        }

        guard totalSize > maxDiskBytes else { return }

        for file in files.sorted(by: { $0.lastAccess < $1.lastAccess }) {
            do {
                try fileManager.removeItem(at: file.url)
                totalSize -= file.size
            } catch {
                continue
            }
            if totalSize <= maxDiskBytes { break }
        }
    }

    private func touch(_ fileURL: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.contentAccessDate = Date()
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func fileURL(for storageKey: String) -> URL {
        diskRootURL
            .appendingPathComponent(storageKey, isDirectory: false)
            .appendingPathExtension("pagecache")
    }

    fileprivate nonisolated static func hashedKey(for rawValue: String) -> String {
        SHA256.hash(data: Data(rawValue.utf8)).hexString
    }
}

private extension Sequence where Element == UInt8 {
    nonisolated var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
