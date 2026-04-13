import Foundation

struct DiskUsageFootprint: Hashable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = DiskUsageFootprint(fileCount: 0, totalBytes: 0)
}

enum DiskUsageScanner {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey
    ]

    nonisolated static func allocatedByteCount(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Int64 {
        let standardizedURL = url.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedURL.path) else {
            return 0
        }

        let values = try? standardizedURL.resourceValues(forKeys: resourceKeys)
        if values?.isRegularFile == true {
            return allocatedByteCount(from: values)
        }

        return footprint(
            at: standardizedURL,
            fileManager: fileManager
        ).totalBytes
    }

    nonisolated static func footprint(
        at rootURL: URL,
        fileManager: FileManager = .default,
        options: FileManager.DirectoryEnumerationOptions = []
    ) -> DiskUsageFootprint {
        let standardizedURL = rootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedURL.path) else {
            return .empty
        }

        let rootValues = try? standardizedURL.resourceValues(forKeys: resourceKeys)
        if rootValues?.isRegularFile == true {
            return DiskUsageFootprint(
                fileCount: 1,
                totalBytes: allocatedByteCount(from: rootValues)
            )
        }

        guard let enumerator = fileManager.enumerator(
            at: standardizedURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return .empty
        }

        var fileCount = 0
        var totalBytes: Int64 = 0

        while let itemURL = enumerator.nextObject() as? URL {
            guard let values = try? itemURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true
            else {
                continue
            }

            fileCount += 1
            totalBytes += allocatedByteCount(from: values)
        }

        return DiskUsageFootprint(fileCount: fileCount, totalBytes: totalBytes)
    }

    nonisolated private static func allocatedByteCount(from values: URLResourceValues?) -> Int64 {
        Int64(
            values?.totalFileAllocatedSize
                ?? values?.fileAllocatedSize
                ?? values?.fileSize
                ?? 0
        )
    }
}
