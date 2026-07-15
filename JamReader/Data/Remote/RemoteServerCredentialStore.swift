import Foundation
import os
import Security

enum RemoteServerCredentialStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidPasswordData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus:
            return "Saved credentials are unavailable. Open the server settings and save the password again."
        case .invalidPasswordData:
            return "Stored remote server credentials could not be decoded."
        }
    }
}

final class RemoteServerCredentialStore {
    private let service = "com.ojun.jamreader.remote-server-credentials"

    func passwordReferenceKey(for serverID: UUID) -> String {
        "remote-server.\(serverID.uuidString)"
    }

    func replacementPasswordReferenceKey(
        for serverID: UUID,
        credentialID: UUID = UUID()
    ) -> String {
        "\(passwordReferenceKey(for: serverID)).\(credentialID.uuidString)"
    }

    func loadPassword(for referenceKey: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: referenceKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                AppLog.persistence.error(
                    "Remote credential load failed referenceID=\(Self.logIdentifier(for: referenceKey), privacy: .public) reason=invalidPasswordData"
                )
                throw RemoteServerCredentialStoreError.invalidPasswordData
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            AppLog.persistence.error(
                "Remote credential load failed referenceID=\(Self.logIdentifier(for: referenceKey), privacy: .public) status=\(status)"
            )
            throw RemoteServerCredentialStoreError.unexpectedStatus(status)
        }
    }

    func savePassword(_ password: String, for referenceKey: String) throws {
        let data = Data(password.utf8)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: referenceKey
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        } else {
            status = updateStatus
        }

        guard status == errSecSuccess else {
            AppLog.persistence.error(
                "Remote credential save failed referenceID=\(Self.logIdentifier(for: referenceKey), privacy: .public) status=\(status)"
            )
            throw RemoteServerCredentialStoreError.unexpectedStatus(status)
        }
    }

    func deletePassword(for referenceKey: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: referenceKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            AppLog.persistence.error(
                "Remote credential delete failed referenceID=\(Self.logIdentifier(for: referenceKey), privacy: .public) status=\(status)"
            )
            throw RemoteServerCredentialStoreError.unexpectedStatus(status)
        }
    }

    private static func logIdentifier(for referenceKey: String) -> String {
        AppLogSanitizer.hashedIdentifier(referenceKey)
    }
}
