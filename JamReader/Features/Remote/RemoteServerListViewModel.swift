import Combine
import Foundation
import os

struct RemoteBrowserFeedbackState: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
    }

    let id = UUID()
    let title: String
    let message: String?
    let kind: Kind
    let primaryAction: AppAlertAction?
    let autoDismissAfter: TimeInterval?

    init(
        title: String,
        message: String? = nil,
        kind: Kind = .success,
        primaryAction: AppAlertAction? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.title = title
        self.message = message
        self.kind = kind
        self.primaryAction = primaryAction
        self.autoDismissAfter = autoDismissAfter
    }
}

struct RemoteServerEditorDraft: Identifiable, Equatable {
    let id: UUID
    let existingProfileID: UUID?
    let createdAt: Date?
    let existingPasswordReferenceKey: String?

    var name: String
    var providerKind: RemoteProviderKind
    var host: String
    var portText: String
    var shareName: String
    var baseDirectoryPath: String
    var authenticationMode: RemoteServerAuthenticationMode
    var username: String
    var password: String
    var hasStoredPassword: Bool

    var navigationTitle: String {
        existingProfileID == nil
            ? "New \(providerKind.title) Server"
            : "Edit \(providerKind.title) Server"
    }

    var actionTitle: String {
        existingProfileID == nil ? "Add" : "Save"
    }
}

@MainActor
final class RemoteServerListViewModel: ObservableObject {
    @Published private(set) var profiles: [RemoteServerProfile] = []
    @Published private(set) var latestSessionsByServerID: [UUID: RemoteComicReadingSession] = [:]
    @Published private(set) var shortcutCountByServerID: [UUID: Int] = [:]
    @Published private(set) var cacheSummaryByServerID: [UUID: RemoteComicCacheSummary] = [:]
    @Published private(set) var shortcutCount = 0
    @Published var alert: AppAlertState?

    private let profileStore: RemoteServerProfileStore
    private let folderShortcutStore: RemoteFolderShortcutStore
    private let credentialStore: RemoteServerCredentialStore
    private let browsingService: RemoteServerBrowsingService
    private let readingProgressStore: RemoteReadingProgressStore
    private let remoteBackgroundImportController: RemoteBackgroundImportController
    private let logger = AppLog.remote
    private let cacheLogger = AppLog.remoteCache
    private var hasLoaded = false

    init(
        profileStore: RemoteServerProfileStore,
        folderShortcutStore: RemoteFolderShortcutStore,
        credentialStore: RemoteServerCredentialStore,
        browsingService: RemoteServerBrowsingService,
        readingProgressStore: RemoteReadingProgressStore,
        remoteBackgroundImportController: RemoteBackgroundImportController
    ) {
        self.profileStore = profileStore
        self.folderShortcutStore = folderShortcutStore
        self.credentialStore = credentialStore
        self.browsingService = browsingService
        self.readingProgressStore = readingProgressStore
        self.remoteBackgroundImportController = remoteBackgroundImportController
    }

    var serverCountText: String {
        "\(profiles.count)"
    }

    var recentServerCountText: String {
        "\(latestSessionsByServerID.count)"
    }

    var shortcutCountText: String {
        "\(shortcutCount)"
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        load()
    }

    func load() {
        do {
            profiles = try profileStore.load()
            refreshRecentActivity()
            refreshShortcutCount()
            refreshCacheSummaries()
            let profileCount = profiles.count
            let recentCount = latestSessionsByServerID.count
            logger.info("Remote server list loaded count=\(profileCount) recent=\(recentCount)")
        } catch {
            profiles = []
            shortcutCount = 0
            cacheSummaryByServerID = [:]
            logger.error(
                "Remote server list load failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Load Remote Servers",
                message: error.userFacingMessage
            )
        }
    }

    func makeCreateDraft() -> RemoteServerEditorDraft {
        RemoteServerEditorDraft(
            id: UUID(),
            existingProfileID: nil,
            createdAt: nil,
            existingPasswordReferenceKey: nil,
            name: "",
            providerKind: .smb,
            host: "",
            portText: String(RemoteProviderKind.smb.defaultPort),
            shareName: "",
            baseDirectoryPath: "",
            authenticationMode: .usernamePassword,
            username: "",
            password: "",
            hasStoredPassword: false
        )
    }

    func makeEditDraft(for profile: RemoteServerProfile) -> RemoteServerEditorDraft {
        let hasStoredPassword: Bool
        if let passwordReferenceKey = profile.passwordReferenceKey {
            do {
                hasStoredPassword = try credentialStore.loadPassword(for: passwordReferenceKey) != nil
            } catch {
                hasStoredPassword = false
                logger.warning(
                    "Remote server stored password status load failed serverID=\(profile.id.uuidString, privacy: .public) provider=\(profile.providerKind.rawValue, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
        } else {
            hasStoredPassword = false
        }

        return RemoteServerEditorDraft(
            id: profile.id,
            existingProfileID: profile.id,
            createdAt: profile.createdAt,
            existingPasswordReferenceKey: profile.passwordReferenceKey,
            name: profile.name,
            providerKind: profile.providerKind,
            host: profile.host,
            portText: String(profile.port),
            shareName: profile.shareName,
            baseDirectoryPath: profile.baseDirectoryPath,
            authenticationMode: profile.authenticationMode,
            username: profile.username,
            password: "",
            hasStoredPassword: hasStoredPassword
        )
    }

    func save(draft: RemoteServerEditorDraft) -> AppAlertState? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareName = draft.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDirectoryPath = draft.baseDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = draft.password.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveAction = draft.existingProfileID == nil ? "create" : "update"

        guard let port = Int(draft.portText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            logger.warning("Remote server save rejected action=\(saveAction, privacy: .public) reason=invalidPort")
            return AppAlertState(
                title: "Invalid Port",
                message: "Enter a numeric port for this remote server."
            )
        }

        let serverID = draft.existingProfileID ?? draft.id
        let shouldPersistPassword = draft.authenticationMode.requiresPassword && !password.isEmpty
        let retainedPasswordReferenceKey = draft.existingPasswordReferenceKey
            ?? (draft.hasStoredPassword ? credentialStore.passwordReferenceKey(for: serverID) : nil)
        let stagedPasswordReferenceKey = shouldPersistPassword
            ? credentialStore.replacementPasswordReferenceKey(for: serverID)
            : nil
        let resolvedPasswordReferenceKey = draft.authenticationMode.requiresPassword
            ? (stagedPasswordReferenceKey ?? retainedPasswordReferenceKey)
            : nil

        let profile = RemoteServerProfile(
            id: serverID,
            name: name,
            providerKind: draft.providerKind,
            host: host,
            port: port,
            shareName: shareName,
            baseDirectoryPath: baseDirectoryPath,
            authenticationMode: draft.authenticationMode,
            username: username,
            passwordReferenceKey: resolvedPasswordReferenceKey,
            createdAt: draft.createdAt ?? Date(),
            updatedAt: Date()
        )
        let provider = profile.providerKind.rawValue
        let endpointHost = AppLogSanitizer.truncated(profile.endpointDisplayHost)
        logger.notice(
            "Remote server save requested action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) host=\(endpointHost, privacy: .public)"
        )

        let blockingIssues = browsingService.validateProfile(profile)
            .filter { $0.severity == .error }
            .map(\.message)

        if draft.authenticationMode.requiresPassword && password.isEmpty && !draft.hasStoredPassword {
            logger.warning(
                "Remote server save rejected action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) reason=missingPassword"
            )
            return AppAlertState(
                title: "Password Required",
                message: "Enter a password for this remote server, or switch the connection to Guest."
            )
        }

        if !blockingIssues.isEmpty {
            logger.warning(
                "Remote server save rejected action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) validationErrors=\(blockingIssues.count)"
            )
            return AppAlertState(
                title: "Incomplete Server",
                message: blockingIssues.joined(separator: "\n")
            )
        }

        guard remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            logger.warning(
                "Remote server save rejected action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) reason=remoteTaskInProgress"
            )
            return remoteTaskInProgressAlert
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        do {
            let previousProfile = profiles.first(where: { $0.id == serverID })
            let didChangeRemoteLocation = previousProfile.map {
                $0.remoteScopeKey != profile.remoteScopeKey
            } ?? false
            let didChangeCredentialIdentity = previousProfile.map {
                $0.authenticationMode != profile.authenticationMode
                    || $0.username != profile.username
            } ?? false
            let didRotatePassword = previousProfile != nil && shouldPersistPassword

            if let stagedPasswordReferenceKey {
                try credentialStore.savePassword(password, for: stagedPasswordReferenceKey)
            }

            var updatedProfiles = profiles
            if let existingIndex = updatedProfiles.firstIndex(where: { $0.id == serverID }) {
                updatedProfiles[existingIndex] = profile
            } else {
                updatedProfiles.append(profile)
            }

            do {
                try profileStore.save(updatedProfiles)
            } catch {
                if let stagedPasswordReferenceKey {
                    do {
                        try credentialStore.deletePassword(for: stagedPasswordReferenceKey)
                    } catch {
                        logger.warning(
                            "Remote server save rollback failed item=stagedCredential action=\(saveAction, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                        )
                    }
                }
                throw error
            }

            let previousPasswordReferenceKey = previousProfile?.passwordReferenceKey
                ?? draft.existingPasswordReferenceKey
            if let previousPasswordReferenceKey,
               previousPasswordReferenceKey != resolvedPasswordReferenceKey {
                do {
                    try credentialStore.deletePassword(for: previousPasswordReferenceKey)
                } catch {
                    logger.warning(
                        "Remote server save cleanup failed item=previousCredential action=\(saveAction, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                    )
                }
            }

            if let previousProfile {
                if didChangeRemoteLocation || didChangeCredentialIdentity {
                    cleanupStateAfterProfileScopeChange(previousProfile)
                }

                if didChangeRemoteLocation || didChangeCredentialIdentity || didRotatePassword {
                    browsingService.evictActiveConnections(for: previousProfile)
                    browsingService.evictActiveConnections(for: profile)
                }
            }

            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshShortcutCount()
            refreshCacheSummaries()
            let profileCount = profiles.count
            logger.info(
                "Remote server save completed action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) locationChanged=\(didChangeRemoteLocation) credentialsChanged=\(didChangeCredentialIdentity) passwordRotated=\(didRotatePassword) count=\(profileCount)"
            )
            return nil
        } catch {
            logger.error(
                "Remote server save failed action=\(saveAction, privacy: .public) provider=\(provider, privacy: .public) serverID=\(serverID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return AppAlertState(
                title: "Failed to Save Server",
                message: error.userFacingMessage
            )
        }
    }

    @discardableResult
    func delete(_ profile: RemoteServerProfile) -> Bool {
        guard beginStorageMaintenance() else {
            return false
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        let provider = profile.providerKind.rawValue
        logger.notice(
            "Remote server delete requested provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
        )
        do {
            var updatedProfiles = profiles
            updatedProfiles.removeAll { $0.id == profile.id }
            try profileStore.save(updatedProfiles)

            if let passwordReferenceKey = profile.passwordReferenceKey {
                do {
                    try credentialStore.deletePassword(for: passwordReferenceKey)
                } catch {
                    logger.warning(
                        "Remote server delete cleanup failed item=credential provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                    )
                }
            }

            cleanupStateAfterServerDelete(profile)
            browsingService.evictActiveConnections(for: profile)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshShortcutCount()
            refreshCacheSummaries()
            let profileCount = profiles.count
            logger.info(
                "Remote server delete completed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) remaining=\(profileCount)"
            )
            return true
        } catch {
            logger.error(
                "Remote server delete failed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Remove Server",
                message: error.userFacingMessage
            )
            return false
        }
    }

    func cacheSummary(for profile: RemoteServerProfile) -> RemoteComicCacheSummary {
        cacheSummaryByServerID[profile.id] ?? .empty
    }

    func shortcutCount(for profile: RemoteServerProfile) -> Int {
        shortcutCountByServerID[profile.id] ?? 0
    }

    func clearCache(for profile: RemoteServerProfile) {
        guard beginStorageMaintenance() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        let provider = profile.providerKind.rawValue
        cacheLogger.notice(
            "Remote server comic cache clear requested provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
        )
        do {
            try browsingService.clearCachedComics(for: profile)
            browsingService.evictActiveConnections(for: profile)
            refreshCacheSummaries()
            refreshRecentActivity()
            cacheLogger.info(
                "Remote server comic cache clear completed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
            )
        } catch {
            cacheLogger.error(
                "Remote server comic cache clear failed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Clear Cache",
                message: error.userFacingMessage
            )
        }
    }

    func clearOtherCache(for profile: RemoteServerProfile) {
        guard beginStorageMaintenance() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        let provider = profile.providerKind.rawValue
        cacheLogger.notice(
            "Remote server auxiliary cache clear requested provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
        )
        do {
            try browsingService.clearOtherCachedData(for: profile)
            browsingService.evictActiveConnections(for: profile)
            refreshCacheSummaries()
            cacheLogger.info(
                "Remote server auxiliary cache clear completed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
            )
        } catch {
            cacheLogger.error(
                "Remote server auxiliary cache clear failed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Clear Other Cache Data",
                message: error.userFacingMessage
            )
        }
    }

    func refreshRecentActivity() {
        let activeServerIDs = Set(profiles.map(\.id))
        let allSessions = loadReadingSessionsForViewState(reason: "recentActivity")

        latestSessionsByServerID = allSessions.reduce(into: [:]) { result, session in
            guard activeServerIDs.contains(session.serverID),
                  let profile = profiles.first(where: { $0.id == session.serverID }),
                  session.matches(profile: profile),
                  result[session.serverID] == nil
            else {
                return
            }

            result[session.serverID] = session
        }
    }

    func latestSession(for profile: RemoteServerProfile) -> RemoteComicReadingSession? {
        latestSessionsByServerID[profile.id]
    }

    func recentSessions(for profile: RemoteServerProfile) -> [RemoteComicReadingSession] {
        loadReadingSessionsForViewState(reason: "profileHistory").filter { $0.matches(profile: profile) }
    }

    func deleteRecentSession(_ session: RemoteComicReadingSession) {
        logger.info(
            "Remote recent session delete requested serverID=\(session.serverID.uuidString, privacy: .public) path=\(AppLogSanitizer.path(session.path), privacy: .public)"
        )
        do {
            try readingProgressStore.deleteSession(session)
            refreshRecentActivity()
            logger.info(
                "Remote recent session delete completed serverID=\(session.serverID.uuidString, privacy: .public)"
            )
        } catch {
            logger.error(
                "Remote recent session delete failed serverID=\(session.serverID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Delete History",
                message: error.userFacingMessage
            )
        }
    }

    func clearRecentHistory(for profile: RemoteServerProfile) {
        let provider = profile.providerKind.rawValue
        logger.notice(
            "Remote recent history clear requested provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
        )
        do {
            try readingProgressStore.deleteSessions(for: profile)
            refreshRecentActivity()
            logger.info(
                "Remote recent history clear completed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public)"
            )
        } catch {
            logger.error(
                "Remote recent history clear failed provider=\(provider, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: "Failed to Clear History",
                message: error.userFacingMessage
            )
        }
    }

    func profile(withID profileID: UUID) -> RemoteServerProfile? {
        profiles.first { $0.id == profileID }
    }

    private func cleanupStateAfterProfileScopeChange(_ previousProfile: RemoteServerProfile) {
        RemoteServerBrowserViewModel.clearRememberedPath(for: previousProfile)
        let provider = previousProfile.providerKind.rawValue
        let serverID = previousProfile.id.uuidString

        do {
            try readingProgressStore.deleteSessions(for: previousProfile)
        } catch {
            logger.warning(
                "Remote server scope change cleanup failed item=readingHistory provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            try folderShortcutStore.removeShortcuts(
                for: previousProfile.id,
                providerKind: previousProfile.providerKind,
                providerRootIdentifier: previousProfile.normalizedProviderRootIdentifier
            )
        } catch {
            logger.warning(
                "Remote server scope change cleanup failed item=folderShortcuts provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            try browsingService.clearCachedComicsForServer(id: previousProfile.id)
        } catch {
            cacheLogger.warning(
                "Remote server scope change cleanup failed item=cachedComics provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }

    private func cleanupStateAfterServerDelete(_ profile: RemoteServerProfile) {
        let provider = profile.providerKind.rawValue
        let serverID = profile.id.uuidString

        do {
            try browsingService.clearCachedComicsForServer(id: profile.id)
        } catch {
            cacheLogger.warning(
                "Remote server delete cleanup failed item=cachedComics provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            try readingProgressStore.deleteSessions(for: profile.id)
        } catch {
            logger.warning(
                "Remote server delete cleanup failed item=readingHistory provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            try folderShortcutStore.removeShortcuts(for: profile.id)
        } catch {
            logger.warning(
                "Remote server delete cleanup failed item=folderShortcuts provider=\(provider, privacy: .public) serverID=\(serverID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }

    private func refreshShortcutCount() {
        let activeProfilesByServerID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let allShortcuts = loadFolderShortcutsForViewState(reason: "shortcutCount")
        let scopedShortcuts = allShortcuts.filter { shortcut in
            guard let profile = activeProfilesByServerID[shortcut.serverID] else {
                return false
            }

            return shortcut.matches(profile: profile)
        }
        shortcutCount = scopedShortcuts.count
        shortcutCountByServerID = Dictionary(
            grouping: scopedShortcuts,
            by: \.serverID
        ).mapValues(\.count)
    }

    private func refreshCacheSummaries() {
        cacheSummaryByServerID = profiles.reduce(into: [:]) { result, profile in
            result[profile.id] = browsingService.cacheSummary(for: profile)
        }
    }

    private func beginStorageMaintenance() -> Bool {
        guard remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            alert = remoteTaskInProgressAlert
            return false
        }

        return true
    }

    private var remoteTaskInProgressAlert: AppAlertState {
        AppAlertState(
            title: "Remote Task in Progress",
            message: "Wait for the current remote task to finish."
        )
    }

    private func loadReadingSessionsForViewState(reason: String) -> [RemoteComicReadingSession] {
        do {
            return try readingProgressStore.loadSessions()
        } catch {
            logger.warning(
                "Remote server list reading history fallback reason=\(reason, privacy: .public) result=empty error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return []
        }
    }

    private func loadFolderShortcutsForViewState(reason: String) -> [RemoteFolderShortcut] {
        do {
            return try folderShortcutStore.load()
        } catch {
            logger.warning(
                "Remote server list folder shortcuts fallback reason=\(reason, privacy: .public) result=empty error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return []
        }
    }
}
