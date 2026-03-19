import Combine
import Foundation

enum RemoteAlertPrimaryAction {
    case openLibrary(UUID, Int64)

    var title: String {
        switch self {
        case .openLibrary:
            return "Open Library"
        }
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
        existingProfileID == nil ? "New SMB Server" : "Edit SMB Server"
    }

    var actionTitle: String {
        existingProfileID == nil ? "Add" : "Save"
    }
}

@MainActor
final class RemoteServerListViewModel: ObservableObject {
    @Published private(set) var profiles: [RemoteServerProfile] = []
    @Published private(set) var latestSessionsByServerID: [UUID: RemoteComicReadingSession] = [:]
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
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

    var summaryText: String {
        switch profiles.count {
        case 0:
            return "Save SMB servers here, then browse remote folders and open comic archives on demand."
        case 1:
            return "1 remote server is ready for SMB browsing."
        default:
            return "\(profiles.count) remote servers are ready for SMB browsing."
        }
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
            refreshCacheSummary()
        } catch {
            profiles = []
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
            portText: "445",
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
                    message: "Enter a numeric port for the SMB server."
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
                    message: "Enter a password for this SMB server, or switch the connection to Guest."
                )
            )
        }

        if !blockingIssues.isEmpty {
            return .failure(
                RemoteAlertState(
                    title: "Incomplete SMB Server",
                    message: blockingIssues.joined(separator: "\n")
                )
            )
        }

        do {
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
            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshCacheSummary()
            return .success(())
        } catch {
            return .failure(
                RemoteAlertState(
                    title: "Failed to Save SMB Server",
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

            try? browsingService.clearCachedComics(for: profile)
            try? readingProgressStore.deleteSessions(for: profile.id)
            try? folderShortcutStore.removeShortcuts(for: profile.id)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            profiles = updatedProfiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            refreshRecentActivity()
            refreshCacheSummary()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Remove SMB Server",
                message: error.localizedDescription
            )
        }
    }

    func refreshCacheSummary() {
        cacheSummary = browsingService.cacheSummary()
    }

    func cacheSummary(for profile: RemoteServerProfile) -> RemoteComicCacheSummary {
        browsingService.cacheSummary(for: profile)
    }

    func clearCache(for profile: RemoteServerProfile) {
        do {
            try browsingService.clearCachedComics(for: profile)
            refreshCacheSummary()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Clear Cache",
                message: error.localizedDescription
            )
        }
    }

    func clearAllCache() {
        do {
            try browsingService.clearCachedComics()
            refreshCacheSummary()
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
}
