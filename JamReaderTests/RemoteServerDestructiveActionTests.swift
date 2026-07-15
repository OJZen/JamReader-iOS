import XCTest
@testable import JamReader

final class RemoteServerDestructiveActionTests: XCTestCase {
    private let profile = RemoteServerProfile(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        name: "Home NAS",
        providerKind: .smb,
        host: "nas.local",
        port: 445,
        shareName: "Comics",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 100)
    )

    func testDeleteServerExplainsAllLocalDataThatWillBeRemoved() {
        let action = RemoteServerDestructiveAction.deleteServer(profile)

        XCTAssertEqual(action.title, "Delete Server?")
        XCTAssertEqual(action.buttonTitle, "Delete Server")
        XCTAssertTrue(action.message.contains("saved credentials"))
        XCTAssertTrue(action.message.contains("downloaded comics"))
        XCTAssertTrue(action.message.contains("saved folder shortcuts"))
    }

    func testClearDownloadsIncludesAffectedItemCount() {
        let action = RemoteServerDestructiveAction.clearDownloads(profile, count: 3)

        XCTAssertEqual(action.title, "Clear Downloaded Comics?")
        XCTAssertTrue(action.message.contains("3 downloaded comics"))
        XCTAssertTrue(action.message.contains("Reading history remains"))
    }
}
