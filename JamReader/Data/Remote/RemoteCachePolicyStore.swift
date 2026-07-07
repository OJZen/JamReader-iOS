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
            return "Unlimited"
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
