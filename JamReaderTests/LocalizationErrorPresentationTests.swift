import XCTest
@testable import JamReader

final class LocalizationErrorPresentationTests: XCTestCase {
    func testLibraryAndRendererDiagnosticsDoNotLeakIntoUserFacingDescriptions() {
        let diagnosticReason = "internal diagnostic reason"
        let errors: [(any LocalizedError, String)] = [
            (
                LibraryScannerError.openDatabaseFailed(diagnosticReason),
                String(localized: "Unable to open the app library database for scanning.")
            ),
            (
                LibraryScannerError.scanFailed(diagnosticReason),
                String(localized: "Library scan failed.")
            ),
            (
                LibraryDatabaseWriteError.openDatabaseFailed(diagnosticReason),
                String(localized: "Unable to open the app library database for writing.")
            ),
            (
                LibraryDatabaseWriteError.updateFailed(diagnosticReason),
                String(localized: "Unable to update the app library database.")
            ),
            (
                LibraryDatabaseReadError.openDatabaseFailed(diagnosticReason),
                String(localized: "Unable to open the app library database.")
            ),
            (
                LibraryDatabaseReadError.queryFailed(diagnosticReason),
                String(localized: "Library query failed.")
            ),
            (
                LibraryDatabaseBootstrapError.createDatabaseFailed(diagnosticReason),
                String(localized: "Unable to initialize the app library database.")
            ),
            (
                NativeLibraryStorageError.openDatabaseFailed(diagnosticReason),
                String(localized: "Unable to open the app library database.")
            ),
            (
                NativeLibraryStorageError.statementPreparationFailed(diagnosticReason),
                String(localized: "Unable to prepare an app library query.")
            ),
            (
                NativeLibraryStorageError.executionFailed(diagnosticReason),
                String(localized: "Unable to update the app library database.")
            ),
            (
                MuPDFDocumentRendererError.openFailed(diagnosticReason),
                String(localized: "MuPDF could not open this document.")
            ),
            (
                MuPDFDocumentRendererError.renderFailed(diagnosticReason),
                String(localized: "MuPDF could not render this page.")
            ),
        ]

        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.errorDescription, expectedDescription)
            XCTAssertFalse(error.errorDescription?.contains(diagnosticReason) == true)
        }
    }

    func testLibraryDiagnosticsRemainAvailableForLogging() {
        let diagnosticReason = "database is locked at sqlite step 17"
        let errors: [any LocalizedError] = [
            LibraryDatabaseBootstrapError.createDatabaseFailed(diagnosticReason),
            LibraryDatabaseReadError.queryFailed(diagnosticReason),
            LibraryDatabaseWriteError.updateFailed(diagnosticReason),
            LibraryScannerError.scanFailed(diagnosticReason),
            NativeLibraryStorageError.executionFailed(diagnosticReason),
        ]

        for error in errors {
            XCTAssertTrue(
                AppLogSanitizer.errorDescription(error).contains(diagnosticReason),
                "Diagnostic reason was lost for \(String(describing: error))"
            )
            XCTAssertFalse(error.errorDescription?.contains(diagnosticReason) == true)
        }
    }
}
