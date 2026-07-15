import Foundation
import os

extension Notification.Name {
    static let libraryPreferencesDidChange = Notification.Name(
        "JamReader.libraryPreferencesDidChange"
    )
}

final class LibraryPreferencesStore {
    static let recentWindowStorageKey = "libraryRecentWindowDays"

    private let userDefaults: UserDefaults
    private let logger = AppLog.library

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRecentWindow() -> LibraryRecentWindowOption {
        guard let storedValue = userDefaults.object(forKey: Self.recentWindowStorageKey) else {
            return .defaultOption
        }

        let rawValue: Int?
        if let number = storedValue as? NSNumber {
            rawValue = number.intValue
        } else if let string = storedValue as? String {
            rawValue = Int(string)
        } else {
            rawValue = nil
        }

        guard let rawValue,
              let option = LibraryRecentWindowOption(rawValue: rawValue)
        else {
            userDefaults.set(
                LibraryRecentWindowOption.defaultOption.rawValue,
                forKey: Self.recentWindowStorageKey
            )
            logger.warning(
                "Library recent window preference ignored rawValue=\(AppLogSanitizer.truncated(String(describing: storedValue)), privacy: .public) fallback=\(LibraryRecentWindowOption.defaultOption.rawValue, privacy: .public)"
            )
            return .defaultOption
        }

        return option
    }

    func saveRecentWindow(_ option: LibraryRecentWindowOption) {
        let previousValue = userDefaults.object(forKey: Self.recentWindowStorageKey) as? NSNumber
        guard previousValue?.intValue != option.rawValue else {
            return
        }

        userDefaults.set(option.rawValue, forKey: Self.recentWindowStorageKey)
        logger.info(
            "Library recent window preference saved days=\(option.rawValue, privacy: .public)"
        )
        NotificationCenter.default.post(
            name: .libraryPreferencesDidChange,
            object: self
        )
    }
}
