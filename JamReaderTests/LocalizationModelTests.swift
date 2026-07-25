import Foundation
import XCTest
@testable import JamReader

final class LocalizationModelTests: XCTestCase {
    func testDefaultImportedLibraryUsesLocalizedDisplayNameUntilRenamed() {
        let defaultDescriptor = makeDescriptor(
            kind: .importedComics,
            name: LibraryDescriptor.defaultImportedComicsName
        )
        XCTAssertEqual(
            defaultDescriptor.displayName,
            String(localized: "Imported Comics")
        )

        let renamedDescriptor = makeDescriptor(
            kind: .importedComics,
            name: "My Imports"
        )
        XCTAssertEqual(renamedDescriptor.displayName, "My Imports")

        let userLibraryWithReservedName = makeDescriptor(
            kind: .linkedFolder,
            name: LibraryDescriptor.defaultImportedComicsName
        )
        XCTAssertEqual(
            userLibraryWithReservedName.displayName,
            LibraryDescriptor.defaultImportedComicsName
        )
    }

    func testMaintenanceRecordKeepsStableStoredTitleAndLocalizesForDisplay() {
        let record = LibraryMaintenanceRecord(
            libraryID: UUID(),
            title: "Library Refreshed",
            summary: LibraryScanSummary(folderCount: 1, comicCount: 2),
            scope: .library,
            contextPath: nil,
            scannedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(record.title, "Library Refreshed")
        XCTAssertEqual(
            record.localizedTitle,
            String(localized: "Library Refreshed")
        )
    }

    func testUnknownMaintenanceTitlePassesThroughUnchanged() {
        let record = LibraryMaintenanceRecord(
            libraryID: UUID(),
            title: "Custom Maintenance",
            summary: LibraryScanSummary(folderCount: 0, comicCount: 0),
            scope: .library,
            contextPath: nil,
            scannedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(record.localizedTitle, "Custom Maintenance")
    }

    private func makeDescriptor(kind: LibraryKind, name: String) -> LibraryDescriptor {
        LibraryDescriptor(
            id: UUID(),
            kind: kind,
            name: name,
            rootPath: "/",
            bookmarkData: Data(),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
