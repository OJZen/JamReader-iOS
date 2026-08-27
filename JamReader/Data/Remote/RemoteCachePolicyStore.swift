import Foundation
import os

enum RemoteComicCachePolicyPreset: String, CaseIterable, Identifiable {
    case fiveHundredMB = "500mb"
    case oneGigabyte = "1gb"
    case twoGigabytes = "2gb"
    case fourGigabytes = "4gb"
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHundredMB:
            return "500 MB"
        case .oneGigabyte:
            return "1024 MB"
        case .twoGigabytes:
            return "2048 MB"
        case .fourGigabytes:
            return "4096 MB"
        case .unlimited:
            return String(localized: "Unlimited")
        }
    }

    var policy: RemoteComicCachePolicy {
        switch self {
        case .fiveHundredMB:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 12,
                maximumTotalCacheBytes: 500 * 1_024 * 1_024
            )
        case .oneGigabyte:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 24,
                maximumTotalCacheBytes: 1 * 1_024 * 1_024 * 1_024
            )
        case .twoGigabytes:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 48,
                maximumTotalCacheBytes: 2 * 1_024 * 1_024 * 1_024
            )
        case .fourGigabytes:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 96,
                maximumTotalCacheBytes: 4 * 1_024 * 1_024 * 1_024
            )
        case .unlimited:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: .max,
                maximumTotalCacheBytes: .max
            )
        }
    }
}

struct RemoteComicCachePolicy: Hashable {
    let maximumCachedComicFileCount: Int
    let maximumTotalCacheBytes: Int64
}

final class RemoteCachePolicyStore {
    static let downloadFullCopyWhileReadingStorageKey = "remoteBrowser.downloadFullCopyWhileReading"

    private let userDefaults: UserDefaults
    private let logger = AppLog.remoteCache

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadPreset() -> RemoteComicCachePolicyPreset {
        guard let rawValue = userDefaults.string(forKey: storageKey) else {
            return .oneGigabyte
        }

        if let preset = RemoteComicCachePolicyPreset(rawValue: rawValue) {
            return preset
        }

        if let migratedPreset = legacyPreset(for: rawValue) {
            userDefaults.set(migratedPreset.rawValue, forKey: storageKey)
            logger.info(
                "Remote cache policy legacy preset migrated from=\(AppLogSanitizer.truncated(rawValue), privacy: .public) to=\(migratedPreset.rawValue, privacy: .public)"
            )
            return migratedPreset
        }

        userDefaults.set(RemoteComicCachePolicyPreset.oneGigabyte.rawValue, forKey: storageKey)
        logger.warning(
            "Remote cache policy preset ignored rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public) fallback=\(RemoteComicCachePolicyPreset.oneGigabyte.rawValue, privacy: .public)"
        )
        return .oneGigabyte
    }

    func loadPolicy() -> RemoteComicCachePolicy {
        loadPreset().policy
    }

    func savePreset(_ preset: RemoteComicCachePolicyPreset) {
        userDefaults.set(preset.rawValue, forKey: storageKey)
    }

    func loadDownloadsFullCopyWhileReading() -> Bool {
        guard let storedValue = userDefaults.object(
            forKey: Self.downloadFullCopyWhileReadingStorageKey
        ) else {
            return true
        }

        guard let number = storedValue as? NSNumber else {
            userDefaults.set(true, forKey: Self.downloadFullCopyWhileReadingStorageKey)
            logger.warning(
                "Remote reader download preference ignored rawValue=\(AppLogSanitizer.truncated(String(describing: storedValue)), privacy: .public) fallback=true"
            )
            return true
        }

        return number.boolValue
    }

    func saveDownloadsFullCopyWhileReading(_ isEnabled: Bool) {
        let previousValue = userDefaults.object(
            forKey: Self.downloadFullCopyWhileReadingStorageKey
        ) as? NSNumber
        guard previousValue?.boolValue != isEnabled else {
            return
        }

        userDefaults.set(
            isEnabled,
            forKey: Self.downloadFullCopyWhileReadingStorageKey
        )
        logger.info(
            "Remote reader download preference saved enabled=\(isEnabled, privacy: .public)"
        )
    }

    private func legacyPreset(for rawValue: String) -> RemoteComicCachePolicyPreset? {
        switch rawValue {
        case "compact":
            return .fiveHundredMB
        case "balanced":
            return .twoGigabytes
        case "extended":
            return .fourGigabytes
        default:
            return nil
        }
    }

    private let storageKey = "remoteBrowser.cachePolicyPreset"
}
