import XCTest
@testable import JamReader

final class RemoteServerProfileTests: XCTestCase {
    func testSMBProfileNormalizesDisplayAndCacheScopeFields() {
        let profile = RemoteServerProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: " NAS ",
            providerKind: .smb,
            host: " NAS.Local ",
            port: 445,
            shareName: " Comics ",
            baseDirectoryPath: " /Manga//2024/ ",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(profile.normalizedHost, "NAS.Local")
        XCTAssertEqual(profile.normalizedShareName, "Comics")
        XCTAssertEqual(profile.normalizedBaseDirectoryPath, "/Manga/2024")
        XCTAssertEqual(profile.providerRootDisplayPath, "/Comics/Manga/2024")
        XCTAssertEqual(profile.remoteCacheScopeKey, "smb|nas.local|445|Comics")
        XCTAssertEqual(profile.remoteScopeKey, "smb|nas.local|445|Comics|/Manga/2024")
    }

    func testWebDAVBaseURLNormalizesHostPathAndCollectionPath() {
        let profile = RemoteServerProfile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "WebDAV",
            providerKind: .webdav,
            host: "example.com/dav",
            port: 443,
            shareName: "/comics",
            baseDirectoryPath: "Series/Volume 1",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(profile.webDAVBaseURL?.absoluteString, "https://example.com/dav/comics")
        XCTAssertEqual(profile.connectionDisplayPath, "https://example.com/dav/comics/Series/Volume%201")
        XCTAssertEqual(profile.providerRootDisplayPath, "/comics/Series/Volume 1")
        XCTAssertEqual(profile.remoteScopeKey, "webdav|https://example.com/dav/comics|/Series/Volume 1")
    }

    func testWebDAVHTTPPortUsesHTTPDefaultPort() {
        let profile = RemoteServerProfile(
            name: "Local",
            providerKind: .webdav,
            host: "http://server.local/root",
            port: 80,
            shareName: "/dav",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(profile.resolvedWebDAVScheme, "http")
        XCTAssertEqual(profile.defaultPortForResolvedWebDAVScheme, 80)
        XCTAssertTrue(profile.usesDefaultPort)
        XCTAssertEqual(profile.webDAVBaseURL?.absoluteString, "http://server.local/root/dav")
        XCTAssertEqual(profile.endpointDisplayHost, "server.local")
    }
}
