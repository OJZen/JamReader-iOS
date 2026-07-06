import XCTest
@testable import JamReader

final class RemoteServerBrowsingModelsTests: XCTestCase {
    func testBrowsingErrorDescriptionsRemainUserFacing() {
        XCTAssertEqual(
            RemoteServerBrowsingError.authenticationFailed("NAS").errorDescription,
            "Could not sign in to NAS. Check the username and password, then try again."
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.unsupportedComicFile("book.mobi").errorDescription,
            "book.mobi is not a supported remote comic."
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.connectionFailed("nas.local").errorDescription,
            "Could not reach nas.local. Check that the server is online and reachable from this device."
        )
        XCTAssertEqual(
            RemoteServerBrowsingError.insecureTransportBlocked("dav.local").errorDescription,
            "iOS blocked the insecure HTTP connection to dav.local. Use HTTPS for this WebDAV server."
        )
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
