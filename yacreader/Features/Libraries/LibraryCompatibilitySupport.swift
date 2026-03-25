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
        rowHint: "Browse and read here, then refresh after desktop-side changes.",
        bannerTitle: "Desktop-Compatible Library",
        bannerMessage: "This library stays compatible with a desktop or external source. Browse, search, and read on iOS, then run Refresh after desktop-side changes to pick up new files.",
        infoDetail: "This library is being kept compatible with a desktop or external source. It remains available for browsing, search, reading, and metadata compatibility, but direct file imports are disabled to avoid writing into a mirrored library. After desktop-side changes, open the library and run Refresh on iOS to pick up new files.",
        iconName: "desktopcomputer",
        tint: .blue
    )

    private static let readOnly = LibraryCompatibilityPresentation(
        directImportsTitle: "Unavailable",
        badgeTitle: nil,
        rowHint: "Currently readable on this device, but direct imports stay disabled until write access returns.",
        bannerTitle: "Direct Imports Unavailable",
        bannerMessage: "This library is currently readable on this device, but direct imports stay disabled until write access returns.",
        infoDetail: "This library is currently readable but not writable from iOS, so direct file imports are disabled until write access is available again.",
        iconName: "lock.fill",
        tint: .orange
    )

    private static func versionMismatch(_ version: String?) -> LibraryCompatibilityPresentation {
        let versionText = version ?? "Unknown"
        return LibraryCompatibilityPresentation(
            directImportsTitle: "Unavailable",
            badgeTitle: "Check DB Version",
            rowHint: "This library database uses version \(versionText). Open it in read-only mode until compatibility is confirmed.",
            bannerTitle: "Library Version Not Supported",
            bannerMessage: "This library uses database version \(versionText). The current iOS build only writes to compatible YACReader databases.",
            infoDetail: "The detected library.ydb version is \(versionText), while this iOS build expects a compatible \(LibraryDatabaseBootstrapper.currentDatabaseVersion) schema family. Browsing may still work, but direct imports and write operations should stay blocked until compatibility is confirmed.",
            iconName: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }
}
