import Foundation

struct RemoteComicDownloadResult: Hashable {
    enum Source: Hashable {
        case downloaded
        case cachedCurrent
        case cachedFallback(String)
    }

    let localFileURL: URL
    let source: Source
}

struct RemoteComicBatchDownloadOutcome {
    let reference: RemoteComicFileReference
    let result: RemoteComicDownloadResult?
    let error: Error?
}

struct RemoteComicCacheSummary: Hashable {
    let fileCount: Int
    let totalBytes: Int64
    let cachedComicBytes: Int64
    let otherCacheBytes: Int64

    static let empty = RemoteComicCacheSummary(
        fileCount: 0,
        totalBytes: 0,
        cachedComicBytes: 0,
        otherCacheBytes: 0
    )

    init(
        fileCount: Int,
        totalBytes: Int64,
        cachedComicBytes: Int64? = nil,
        auxiliaryBytes: Int64? = nil,
        otherCacheBytes: Int64? = nil
    ) {
        self.fileCount = fileCount
        self.totalBytes = max(0, totalBytes)
        self.cachedComicBytes = max(0, cachedComicBytes ?? totalBytes)
        self.otherCacheBytes = max(0, otherCacheBytes ?? auxiliaryBytes ?? 0)
    }

    var isEmpty: Bool {
        totalBytes <= 0
    }

    var hasCachedComics: Bool {
        fileCount > 0 && cachedComicBytes > 0
    }

    var hasOtherCacheData: Bool {
        otherCacheBytes > 0
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var cachedComicSizeText: String {
        ByteCountFormatter.string(fromByteCount: cachedComicBytes, countStyle: .file)
    }

    var otherCacheSizeText: String {
        ByteCountFormatter.string(fromByteCount: otherCacheBytes, countStyle: .file)
    }

    var summaryText: String {
        if !hasCachedComics {
            return hasOtherCacheData ? "Other cache data · \(otherCacheSizeText)" : "Cached data · \(sizeText)"
        }

        if fileCount == 1 {
            return "1 cached comic · \(cachedComicSizeText)"
        }

        return "\(fileCount) cached comics · \(cachedComicSizeText)"
    }
}

struct RemoteComicCachedAvailability: Hashable {
    enum Kind: Hashable {
        case unavailable
        case current
        case stale
    }

    let kind: Kind

    static let unavailable = RemoteComicCachedAvailability(kind: .unavailable)

    var hasLocalCopy: Bool {
        kind != .unavailable
    }

    var badgeTitle: String? {
        switch kind {
        case .unavailable:
            return nil
        case .current:
            return "Offline Ready"
        case .stale:
            return "Older Local Copy"
        }
    }
}
