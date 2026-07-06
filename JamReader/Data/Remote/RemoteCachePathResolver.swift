import CryptoKit
import Foundation

struct RemoteCachePathResolver {
    let remoteComicCacheRootURL: URL

    func cachedFileURL(for reference: RemoteComicFileReference) -> URL {
        let rootComponents: [String]
        if let cacheScopeKey = reference.cacheScopeKey {
            rootComponents = Self.cacheRootPathComponents(cacheScopeKey: cacheScopeKey)
        } else {
            rootComponents = Self.legacyCacheRootPathComponents(
                providerKind: reference.providerKind,
                providerRootIdentifier: reference.shareName
            )
        }

        return cachedFileURL(for: reference, rootComponents: rootComponents)
    }

    func legacyCachedFileURL(for reference: RemoteComicFileReference) -> URL {
        cachedFileURL(
            for: reference,
            rootComponents: Self.legacyCacheRootPathComponents(
                providerKind: reference.providerKind,
                providerRootIdentifier: reference.shareName
            )
        )
    }

    func cachedFileURL(
        for reference: RemoteComicFileReference,
        rootComponents: [String]
    ) -> URL {
        var destinationURL = remoteComicCacheRootURL
            .appendingPathComponent(reference.serverID.uuidString, isDirectory: true)
        for component in rootComponents {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        let normalizedPath = Self.smbRelativePath(forDisplayPath: reference.path)
        let components = normalizedPath
            .split(separator: "/")
            .map(String.init)
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }

        if components.isEmpty {
            return destinationURL.appendingPathComponent(
                reference.fileName,
                isDirectory: reference.isImageDirectoryComic
            )
        }

        for component in components.dropLast() {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        return destinationURL.appendingPathComponent(
            components.last ?? reference.fileName,
            isDirectory: reference.isImageDirectoryComic
        )
    }

    func cachedFileCandidateURLs(for reference: RemoteComicFileReference) -> [URL] {
        let preferredURL = cachedFileURL(for: reference)
        let legacyURL = legacyCachedFileURL(for: reference)
        guard preferredURL.standardizedFileURL.path != legacyURL.standardizedFileURL.path else {
            return [preferredURL]
        }

        return [preferredURL, legacyURL]
    }

    func cacheRootURL(for profile: RemoteServerProfile?) -> URL {
        guard let profile else {
            return remoteComicCacheRootURL
        }

        var cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        for component in Self.cacheRootPathComponents(cacheScopeKey: profile.remoteCacheScopeKey) {
            cacheURL.appendPathComponent(component, isDirectory: true)
        }

        return cacheURL
    }

    func legacyCacheRootURL(for profile: RemoteServerProfile) -> URL {
        var cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        for component in Self.legacyCacheRootPathComponents(
            providerKind: profile.providerKind,
            providerRootIdentifier: profile.normalizedProviderRootIdentifier
        ) {
            cacheURL.appendPathComponent(component, isDirectory: true)
        }

        return cacheURL
    }

    func cacheRootURLs(for profile: RemoteServerProfile?) -> [URL] {
        guard let profile else {
            return [remoteComicCacheRootURL]
        }

        var ordered: [URL] = []
        var seenPaths = Set<String>()
        for url in [cacheRootURL(for: profile), legacyCacheRootURL(for: profile)] {
            let standardizedPath = url.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            ordered.append(url)
        }
        return ordered
    }

    static func legacyCacheRootPathComponents(
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String
    ) -> [String] {
        switch providerKind {
        case .smb:
            let trimmed = providerRootIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return [trimmed.isEmpty ? "share" : trimmed]
        case .webdav:
            let components = normalizeDisplayPath(providerRootIdentifier)
                .split(separator: "/")
                .map(String.init)
            return components.isEmpty ? ["webdav-root"] : ["webdav"] + components
        }
    }

    static func cacheRootPathComponents(cacheScopeKey: String) -> [String] {
        let digest = SHA256.hash(data: Data(cacheScopeKey.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return ["scope-\(digest)"]
    }

    private static func normalizeDisplayPath(_ rawPath: String) -> String {
        let collapsedPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !collapsedPath.isEmpty else {
            return ""
        }

        return "/" + collapsedPath
    }

    private static func smbRelativePath(forDisplayPath path: String) -> String {
        let normalizedPath = normalizeDisplayPath(path)
        guard !normalizedPath.isEmpty else {
            return ""
        }

        return String(normalizedPath.dropFirst())
    }
}
