import SwiftUI

struct LibraryCompatibilityPresentation {
    let directImportsTitle: String
    let badgeTitle: String?
    let rowHint: String?
    let bannerTitle: String?
    let bannerMessage: String?
    let infoDetail: String?
    let iconName: String?
    let tint: Color?

    static func resolve(
        descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot
    ) -> LibraryCompatibilityPresentation {
        if accessSnapshot.database.exists, !accessSnapshot.database.hasCompatibleSchemaVersion {
            return .versionMismatch(accessSnapshot.database.version)
        }

        if descriptor.storageMode == .mirrored {
            return .mirrored
        }

        if !accessSnapshot.sourceWritable {
            return .readOnly
        }

        return .writable
    }

    static func resolve(
        descriptor: LibraryDescriptor,
        availability: LibraryImportDestinationOption.Availability
    ) -> LibraryCompatibilityPresentation {
        if descriptor.storageMode == .mirrored {
            return .mirrored
        }

        switch availability {
        case .available:
            return .writable
        case .unavailable:
            return .readOnly
        }
    }

    private static let writable = LibraryCompatibilityPresentation(
        directImportsTitle: "Allowed",
        badgeTitle: nil,
        rowHint: nil,
        bannerTitle: nil,
        bannerMessage: nil,
        infoDetail: nil,
        iconName: nil,
        tint: nil
    )

    private static let mirrored = LibraryCompatibilityPresentation(
        directImportsTitle: "Browse Only",
        badgeTitle: "Desktop Compatible",
        rowHint: "Browse here, then refresh after desktop changes.",
        bannerTitle: "Desktop-Compatible Library",
        bannerMessage: "Browse and read here, then refresh after desktop changes.",
        infoDetail: "This library stays compatible with its desktop source. Browse and read on iOS, but imports stay off. Run Refresh after desktop changes.",
        iconName: "desktopcomputer",
        tint: .blue
    )

    private static let readOnly = LibraryCompatibilityPresentation(
        directImportsTitle: "Unavailable",
        badgeTitle: nil,
        rowHint: "Readable here, but imports stay off for now.",
        bannerTitle: "Direct Imports Unavailable",
        bannerMessage: "This library is readable, but imports stay off until write access returns.",
        infoDetail: "This library is readable but not writable on iOS, so imports stay off for now.",
        iconName: "lock.fill",
        tint: .orange
    )

    private static func versionMismatch(_ version: String?) -> LibraryCompatibilityPresentation {
        let versionText = version ?? "Unknown"
        return LibraryCompatibilityPresentation(
            directImportsTitle: "Unavailable",
            badgeTitle: "Check DB Version",
            rowHint: "Database version \(versionText). Open read-only for now.",
            bannerTitle: "Library Version Not Supported",
            bannerMessage: "Database version \(versionText). This iOS build only writes to compatible libraries.",
            infoDetail: "Detected library.ydb version \(versionText). This build expects the \(LibraryDatabaseBootstrapper.currentDatabaseVersion) schema family, so write actions stay off until compatibility is confirmed.",
            iconName: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }
}
