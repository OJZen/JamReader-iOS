import XCTest
@testable import JamReader

final class RemoteServerBrowsingModelsTests: XCTestCase {
    func testBrowsingErrorDescriptionsRemainUserFacing() {
        let serverName = "NAS"
        let fileName = "book.mobi"
        let endpoint = "nas.local"
        let webDAVEndpoint = "dav.local"

        XCTAssertEqual(
            RemoteServerBrowsingError.authenticationFailed(serverName).errorDescription,
            String(localized: "Could not sign in to \(serverName). Check the username and password, then try again.")
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.unsupportedComicFile(fileName).errorDescription,
            String(localized: "\(fileName) is not a supported remote comic.")
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.connectionFailed(endpoint).errorDescription,
            String(localized: "Could not reach \(endpoint). Check that the server is online and reachable from this device.")
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.insecureTransportBlocked(webDAVEndpoint).errorDescription,
            String(localized: "iOS blocked the insecure HTTP connection to \(webDAVEndpoint). Use HTTPS for this WebDAV server.")
        )
    }

    func testDiagnosticReasonsDoNotLeakIntoUserFacingDescriptions() {
        let diagnosticReason = "internal diagnostic reason"
        let errors: [(RemoteServerBrowsingError, String)] = [
            (
                .invalidProfile(diagnosticReason),
                String(localized: "The remote server profile is incomplete.")
            ),
            (
                .missingCredentials(diagnosticReason),
                String(localized: "The saved credentials for this server are unavailable. Edit the server and save them again.")
            ),
            (
                .cacheMaintenanceFailed(diagnosticReason),
                String(localized: "The remote cache could not be updated. Close any open comic and try again.")
            ),
            (
                .operationFailed(diagnosticReason),
                String(localized: "The remote operation could not be completed.")
            ),
        ]

        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.errorDescription, expectedDescription)
            XCTAssertFalse(error.errorDescription?.contains(diagnosticReason) == true)
        }
    }

    func testCapabilitiesSupportBrowsingAndSingleComicOpeningForCurrentProviders() {
        let service = RemoteServerBrowsingService()

        XCTAssertEqual(
            service.capabilities(for: .smb),
            RemoteServerBrowserCapabilities(
                providerKind: .smb,
                supportsDirectoryBrowsing: true,
                supportsSingleComicOpening: true
            )
        )
        XCTAssertEqual(
            service.capabilities(for: .webdav),
            RemoteServerBrowserCapabilities(
                providerKind: .webdav,
                supportsDirectoryBrowsing: true,
                supportsSingleComicOpening: true
            )
        )
    }

    func testValidationIssueIdentityIsStablePerInstance() {
        let issue = RemoteServerValidationIssue(
            severity: .error,
            message: "Host cannot be empty."
        )

        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.message, "Host cannot be empty.")
        XCTAssertEqual(issue.id, issue.id)
    }
}
