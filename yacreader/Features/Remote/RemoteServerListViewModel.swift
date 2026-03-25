import Combine
import Foundation

enum RemoteAlertPrimaryAction: Equatable {
    case openLibrary(UUID, Int64)

    var title: String {
        switch self {
        case .openLibrary:
            return "Open Library"
        }
    }
}

struct RemoteBrowserFeedbackState: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
    }

    let id = UUID()
    let title: String
    let message: String?
    let kind: Kind
    let primaryAction: RemoteAlertPrimaryAction?
    let autoDismissAfter: TimeInterval?

    init(
        title: String,
        message: String? = nil,
        kind: Kind = .success,
        primaryAction: RemoteAlertPrimaryAction? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.title = title
        self.message = message
        self.kind = kind
        self.primaryAction = primaryAction
        self.autoDismissAfter = autoDismissAfter
    }
}

struct RemoteAlertState: Identifiable, Error {
    let id = UUID()
    let title: String
    let message: String
    let primaryAction: RemoteAlertPrimaryAction?

    init(
        title: String,
        message: String,
        primaryAction: RemoteAlertPrimaryAction? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
    }
}

struct RemoteServerEditorDraft: Identifiable {
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
    @Published var alert: RemoteAlertState?

    private let profileStore: RemoteServerProfileStore
    private let folderShortcutStore: RemoteFolderShortcutStore
    private let credentialStore: RemoteServerCredentialStore
    private let browsingService: RemoteServerBrowsingService
    private let readingProgressStore: RemoteReadingProgressStore
    private var hasLoaded = false

    init(
        profileStore: RemoteServerProfileStore,
        folderShortcutStore: RemoteFolderShortcutStore,
        credentialStore: RemoteServerCredentialStore,
        browsingService: RemoteServerBrowsingService,
        readingProgressStore: RemoteReadingProgressStore
    ) {
        self.profileStore = profileStore
        self.folderShortcutStore = folderShortcutStore
        self.credentialStore = credentialStore
        self.browsingService = browsingService
        self.readingProgressStore = readingProgressStore
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
        } catch {
            profiles = []
            shortcutCount = 0
            cacheSummaryByServerID = [:]
            alert = RemoteAlertState(
                title: "Failed to Load Remote Servers",
                message: error.localizedDescription
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
            hasStoredPassword = (try? credentialStore.loadPassword(for: passwordReferenceKey)) != nil
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

    func save(draft: RemoteServerEditorDraft) -> Result<Void, RemoteAlertState> {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareName = draft.shareName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDirectoryPath = draft.baseDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = draft.password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let port = Int(draft.portText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(
                RemoteAlertState(
                    title: "Invalid Port",
                    message: "Enter a numeric port for this remote server."
                )
            )
        }

        let serverID = draft.existingProfileID ?? draft.id
        let passwordReferenceKey = credentialStore.passwordReferenceKey(for: serverID)
        let shouldPersistPassword = draft.authenticationMode.requiresPassword && !password.isEmpty
        let resolvedPasswordReferenceKey = draft.authenticationMode.requiresPassword
            ? (shouldPersistPassword || draft.hasStoredPassword ? passwordReferenceKey : nil)
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

        let blockingIssues = browsingService.validateProfile(profile)
            .filter { $0.severity == .error }
            .map(\.message)

        if draft.authenticationMode.requiresPassword && password.isEmpty && !draft.hasStoredPassword {
            return .failure(
                RemoteAlertState(
                    title: "Password Required",
                    message: "Enter a password for this remote server, or switch the connection to Guest."
                )
            )
        }

        if !blockingIssues.isEmpty {
            return .failure(
                RemoteAlertState(
                    title: "Incomplete Server",
                    message: blockingIssues.joined(separator: "\n")
                )
            )
        }

        do {
            let previousProfile = profiles.first(where: { $0.id == serverID })

            if draft.authenticationMode.requiresPassword {
                if shouldPersistPassword {
                    try credentialStore.savePassword(password, for: passwordReferenceKey)
                }
            } else if let existingPasswordReferenceKey = draft.existingPasswordReferenceKey {
                try credentialStore.deletePassword(for: existingPasswordReferenceKey)
            }

            var updatedProfiles = profiles
            if let existingIndex = updatedProfiles.firstIndex(where: { $0.id == serverID }) {
                updatedProfiles[existingIndex] = profile
            } else {
                updatedProfiles.append(profile)
            }

            try profileStore.save(updatedProfiles)

            if let previousProfile,
               previousProfile.remoteScopeKey != profile.remoteScopeKey {
                RemoteServerBrowserViewModel.clearRememberedPath(for: previousProfile)
                try? readingProgressStore.deleteSessions(for: previousProfile)
                try? folderShortcutStore.removeShortcuts(
                    for: previousProfile.id,
                    providerKind: previousProfile.providerKind,
                    providerRootIdentifier: previousProfile.normalizedProviderRootIdentifier
                )
                try? browsingService.clearCachedComics(for: previousProfile)
            }

            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshShortcutCount()
            refreshCacheSummaries()
            return .success(())
        } catch {
            return .failure(
                RemoteAlertState(
                    title: "Failed to Save Server",
                    message: error.localizedDescription
                )
            )
        }
    }

    func delete(_ profile: RemoteServerProfile) {
        do {
            var updatedProfiles = profiles
            updatedProfiles.removeAll { $0.id == profile.id }
            try profileStore.save(updatedProfiles)

            if let passwordReferenceKey = profile.passwordReferenceKey {
                try credentialStore.deletePassword(for: passwordReferenceKey)
            }

            try? browsingService.clearCachedComicsForServer(id: profile.id)
            try? readingProgressStore.deleteSessions(for: profile.id)
            try? folderShortcutStore.removeShortcuts(for: profile.id)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshShortcutCount()
            refreshCacheSummaries()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Remove Server",
                message: error.localizedDescription
            )
        }
    }

    func cacheSummary(for profile: RemoteServerProfile) -> RemoteComicCacheSummary {
        cacheSummaryByServerID[profile.id] ?? .empty
    }

    func shortcutCount(for profile: RemoteServerProfile) -> Int {
        shortcutCountByServerID[profile.id] ?? 0
    }

    func clearCache(for profile: RemoteServerProfile) {
        do {
            try browsingService.clearCachedComics(for: profile)
            try readingProgressStore.deleteSessions(for: profile)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            refreshCacheSummaries()
            refreshRecentActivity()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Clear Cache",
                message: error.localizedDescription
            )
        }
    }

    func refreshRecentActivity() {
        let activeServerIDs = Set(profiles.map(\.id))
        let allSessions = (try? readingProgressStore.loadSessions()) ?? []

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
        ((try? readingProgressStore.loadSessions()) ?? []).filter { $0.matches(profile: profile) }
    }

    func deleteRecentSession(_ session: RemoteComicReadingSession) {
        do {
            try readingProgressStore.deleteSession(session)
            refreshRecentActivity()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Delete History",
                message: error.localizedDescription
            )
        }
    }

    func clearRecentHistory(for profile: RemoteServerProfile) {
        do {
            try readingProgressStore.deleteSessions(for: profile)
            refreshRecentActivity()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Clear History",
                message: error.localizedDescription
            )
        }
    }

    func profile(withID profileID: UUID) -> RemoteServerProfile? {
        profiles.first { $0.id == profileID }
    }

    private func refreshShortcutCount() {
        let activeProfilesByServerID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let allShortcuts = (try? folderShortcutStore.load()) ?? []
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
}
