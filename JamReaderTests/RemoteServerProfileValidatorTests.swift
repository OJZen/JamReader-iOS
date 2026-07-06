import XCTest
@testable import JamReader

final class RemoteServerProfileValidatorTests: XCTestCase {
    func testSMBValidationReportsAllRequiredFieldIssues() {
        let profile = RemoteServerProfile(
            name: " ",
            providerKind: .smb,
            host: " ",
            port: 0,
            shareName: " ",
            authenticationMode: .usernamePassword,
            username: " ",
            passwordReferenceKey: nil,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            RemoteServerProfileValidator().validate(profile).map(\.message),
            [
                "A display name is required for the remote server.",
                "Host cannot be empty.",
                "Port must be between 1 and 65535.",
                "Share name cannot be empty.",
                "Username is required for this authentication mode.",
                "A saved password is required for this remote server."
            ]
        )
    }

    func testWebDAVValidationReportsInvalidBaseURL() {
        let profile = RemoteServerProfile(
            name: "WebDAV",
            providerKind: .webdav,
            host: " ",
            port: 443,
            shareName: "",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            RemoteServerProfileValidator().validate(profile).map(\.message),
            [
                "Host cannot be empty.",
                "Enter a valid WebDAV host or URL."
            ]
        )
    }

    func testValidGuestSMBProfileHasNoIssues() {
        let profile = RemoteServerProfile(
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: "Comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(RemoteServerProfileValidator().validate(profile).isEmpty)
    }

    func testBrowsingServiceValidationUsesSameRules() {
        let profile = RemoteServerProfile(
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 70_000,
            shareName: "Comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            RemoteServerBrowsingService().validateProfile(profile).map(\.message),
            RemoteServerProfileValidator().validate(profile).map(\.message)
        )
    }
}
