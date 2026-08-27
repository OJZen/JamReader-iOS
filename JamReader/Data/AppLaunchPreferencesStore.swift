import Foundation
import os

extension Notification.Name {
    static let appLaunchPreferencesDidChange = Notification.Name(
        "JamReader.appLaunchPreferencesDidChange"
    )
}

final class AppLaunchPreferencesStore {
    static let destinationStorageKey = "appLaunch.destination"

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let logger = AppLog.app

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    func loadDestination() -> AppLaunchDestination {
        guard let storedValue = userDefaults.object(
            forKey: Self.destinationStorageKey
        ) else {
            return .defaultValue
        }

        guard let rawValue = storedValue as? String,
              let destination = AppLaunchDestination(rawValue: rawValue)
        else {
            userDefaults.set(
                AppLaunchDestination.defaultValue.rawValue,
                forKey: Self.destinationStorageKey
            )
            logger.warning(
                "App launch destination ignored rawValue=\(AppLogSanitizer.truncated(String(describing: storedValue)), privacy: .public) fallback=\(AppLaunchDestination.defaultValue.rawValue, privacy: .public)"
            )
            return .defaultValue
        }

        return destination
    }

    func saveDestination(_ destination: AppLaunchDestination) {
        guard loadDestination() != destination else {
            return
        }

        userDefaults.set(
            destination.rawValue,
            forKey: Self.destinationStorageKey
        )
        logger.info(
            "App launch destination saved value=\(destination.rawValue, privacy: .public)"
        )
        notificationCenter.post(
            name: .appLaunchPreferencesDidChange,
            object: self
        )
    }
}
