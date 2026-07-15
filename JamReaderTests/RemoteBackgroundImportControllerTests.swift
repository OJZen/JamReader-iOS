import XCTest
@testable import JamReader

@MainActor
final class RemoteBackgroundImportControllerTests: XCTestCase {
    func testImportAndStorageMaintenanceAreMutuallyExclusive() async {
        let controller = RemoteBackgroundImportController()

        XCTAssertTrue(controller.beginExclusiveStorageMaintenance())
        XCTAssertFalse(
            controller.start { _, _ in
                XCTFail("Import should not start during storage maintenance")
            }
        )
        controller.endExclusiveStorageMaintenance()

        XCTAssertTrue(
            controller.start { _, _ in
                await Task.yield()
            }
        )
        XCTAssertFalse(controller.beginExclusiveStorageMaintenance())

        controller.cancelActiveImport()
        await Task.yield()
    }
}
