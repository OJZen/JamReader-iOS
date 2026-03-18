import Foundation
import Security

enum RemoteServerCredentialStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidPasswordData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidPasswordData:
            return "Stored remote server credentials could not be decoded."
        }
    }
}

final class RemoteServerCredentialStore {
    private let service = "com.ojun.yacreader.remote-server-credentials"

    func passwordReferenceKey(for serverID: UUID) -> String {
        "remote-server.\(serverID.uuidString)"
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
                throw RemoteServerCredentialStoreError.invalidPasswordData
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw RemoteServerCredentialStoreError.unexpectedStatus(status)
        }
    }

    func savePassword(_ password: String, for referenceKey: String) throws {
        let data = Data(password.utf8)

        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: referenceKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: referenceKey,
            kSecValueData: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
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
            throw RemoteServerCredentialStoreError.unexpectedStatus(status)
        }
    }
}
