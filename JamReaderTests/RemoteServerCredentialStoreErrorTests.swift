import Security
import XCTest
@testable import JamReader

final class RemoteServerCredentialStoreErrorTests: XCTestCase {
    func testUnexpectedKeychainStatusUsesActionableUserFacingCopy() {
        let error = RemoteServerCredentialStoreError.unexpectedStatus(errSecMissingEntitlement)

        XCTAssertEqual(
            error.errorDescription,
            "Saved credentials are unavailable. Open the server settings and save the password again."
        )
        XCTAssertFalse(error.errorDescription?.contains(String(errSecMissingEntitlement)) ?? true)
    }

    func testReplacementReferenceDoesNotOverwriteExistingCredentialKey() {
        let store = RemoteServerCredentialStore()
        let serverID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let credentialID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let existingKey = store.passwordReferenceKey(for: serverID)
        let replacementKey = store.replacementPasswordReferenceKey(
            for: serverID,
            credentialID: credentialID
        )

        XCTAssertNotEqual(replacementKey, existingKey)
        XCTAssertTrue(replacementKey.hasPrefix(existingKey))
        XCTAssertTrue(replacementKey.hasSuffix(credentialID.uuidString))
    }
}
