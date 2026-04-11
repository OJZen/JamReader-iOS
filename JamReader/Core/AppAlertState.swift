import Foundation

/// Unified alert state used across all app features.
/// Replaces LibraryAlertState, RemoteAlertState, and SettingsAlertState.
struct AppAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let primaryActionTitle: String?
    let primaryAction: AppAlertAction?

    init(title: String, message: String) {
        self.title = title
        self.message = message
        self.primaryActionTitle = nil
        self.primaryAction = nil
    }

    init(title: String, message: String, actionTitle: String, action: AppAlertAction) {
        self.title = title
        self.message = message
        self.primaryActionTitle = actionTitle
        self.primaryAction = action
    }

    init(title: String, error: Error) {
        self.title = title
        self.message = error.userFacingMessage
        self.primaryActionTitle = nil
        self.primaryAction = nil
    }

    init(title: String, error: Error, actionTitle: String, action: AppAlertAction) {
        self.title = title
        self.message = error.userFacingMessage
        self.primaryActionTitle = actionTitle
        self.primaryAction = action
    }
}

/// Actions that can be triggered from an alert's primary button.
enum AppAlertAction: Equatable {
    case openLibrary(UUID, Int64)
}

extension AppAlertAction {
    var title: String {
        switch self {
        case .openLibrary:
            return "Open Library"
        }
    }
}

extension Error {
    /// Returns a user-friendly error message suitable for display in alerts.
    /// Prefers LocalizedError.errorDescription when available, falls back to
    /// a generic message for system/unknown errors.
    var userFacingMessage: String {
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        let raw = localizedDescription
        // Filter out unhelpful generic Apple error messages
        if raw.contains("NSLocalizedDescription") || raw.contains("NSUnderlyingError") {
            return "An unexpected error occurred. Please try again."
        }
        return raw
    }
}
