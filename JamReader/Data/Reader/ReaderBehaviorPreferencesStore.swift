import Foundation
import os

extension Notification.Name {
    static let readerBehaviorPreferencesDidChange = Notification.Name(
        "JamReader.readerBehaviorPreferencesDidChange"
    )
}

final class ReaderBehaviorPreferencesStore {
    static let keepsScreenAwakeStorageKey = "reader.behavior.keepsScreenAwake"

    private let userDefaults: UserDefaults
    private let logger = AppLog.reader

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadKeepsScreenAwake() -> Bool {
        guard let storedValue = userDefaults.object(
            forKey: Self.keepsScreenAwakeStorageKey
        ) else {
            return true
        }

        guard let number = storedValue as? NSNumber else {
            userDefaults.set(true, forKey: Self.keepsScreenAwakeStorageKey)
            logger.warning(
                "Reader behavior preference repaired invalid stored value fallback=true"
            )
            return true
        }

        return number.boolValue
    }

    func saveKeepsScreenAwake(_ keepsScreenAwake: Bool) {
        guard loadKeepsScreenAwake() != keepsScreenAwake else {
            return
        }

        userDefaults.set(keepsScreenAwake, forKey: Self.keepsScreenAwakeStorageKey)
        logger.info(
            "Reader behavior preference saved keepsScreenAwake=\(keepsScreenAwake, privacy: .public)"
        )
        NotificationCenter.default.post(
            name: .readerBehaviorPreferencesDidChange,
            object: self
        )
    }
}
