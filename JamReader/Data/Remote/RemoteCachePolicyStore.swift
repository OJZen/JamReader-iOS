import Foundation

enum RemoteComicCachePolicyPreset: String, CaseIterable, Identifiable {
    case compact
    case balanced
    case extended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .balanced:
            return "Balanced"
        case .extended:
            return "Extended"
        }
    }

    var subtitle: String {
        policy.summaryText
    }

    var policy: RemoteComicCachePolicy {
        switch self {
        case .compact:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 12,
                maximumTotalCacheBytes: 512 * 1_024 * 1_024
            )
        case .balanced:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 48,
                maximumTotalCacheBytes: 2 * 1_024 * 1_024 * 1_024
            )
        case .extended:
            return RemoteComicCachePolicy(
                maximumCachedComicFileCount: 120,
                maximumTotalCacheBytes: 5 * 1_024 * 1_024 * 1_024
            )
        }
    }
}

struct RemoteComicCachePolicy: Hashable {
    let maximumCachedComicFileCount: Int
    let maximumTotalCacheBytes: Int64

    var summaryText: String {
        let sizeText = ByteCountFormatter.string(
            fromByteCount: maximumTotalCacheBytes,
            countStyle: .file
        )
        let comicWord = maximumCachedComicFileCount == 1 ? "comic" : "comics"
        return "Up to \(maximumCachedComicFileCount) \(comicWord) or \(sizeText)"
    }
}

final class RemoteCachePolicyStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadPreset() -> RemoteComicCachePolicyPreset {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let preset = RemoteComicCachePolicyPreset(rawValue: rawValue) {
            return preset
        }

        return .balanced
    }

    func loadPolicy() -> RemoteComicCachePolicy {
        loadPreset().policy
    }

    func savePreset(_ preset: RemoteComicCachePolicyPreset) {
        userDefaults.set(preset.rawValue, forKey: storageKey)
    }

    private let storageKey = "remoteBrowser.cachePolicyPreset"
}
