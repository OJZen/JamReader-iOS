import Combine
import SwiftUI

@MainActor
final class RemoteOfflineShelfViewModel: ObservableObject {
    struct Entry: Identifiable, Hashable {
        let session: RemoteComicReadingSession
        let profile: RemoteServerProfile
        let availability: RemoteComicCachedAvailability

        var id: String {
            session.id
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
    @Published private(set) var isLoading = false
    @Published var alert: BrowseHomeAlert?

    private let remoteServerProfileStore: RemoteServerProfileStore
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.remoteServerProfileStore = dependencies.remoteServerProfileStore
        self.remoteReadingProgressStore = dependencies.remoteReadingProgressStore
        self.remoteServerBrowsingService = dependencies.remoteServerBrowsingService
    }

    var summaryTitle: String {
        switch entries.count {
        case 0:
            return "No offline comics yet"
        case 1:
            return "1 offline-ready comic"
        default:
            return "\(entries.count) offline-ready comics"
        }
    }

    var summaryText: String {
        if entries.isEmpty {
            return "Open a remote comic once and keep the downloaded copy on this device for quick access later."
        }

        return "These downloaded remote comics can open from local cache immediately, without waiting on the SMB server."
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let profiles = try remoteServerProfileStore.load()
            let sessions = try remoteReadingProgressStore.loadSessions()
            let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            entries = sessions.compactMap { session in
                let availability = remoteServerBrowsingService.cachedAvailability(for: session.comicFileReference)
                guard availability.hasLocalCopy,
                      let profile = profilesByID[session.serverID] else {
                    return nil
                }

                return Entry(session: session, profile: profile, availability: availability)
            }
            cacheSummary = remoteServerBrowsingService.cacheSummary()
            alert = nil
        } catch {
            entries = []
            cacheSummary = .empty
            alert = BrowseHomeAlert(
                title: "Offline Shelf Unavailable",
                message: error.localizedDescription
            )
        }
    }
}

struct RemoteOfflineShelfView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteOfflineShelfViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: RemoteOfflineShelfViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                if viewModel.entries.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Offline Comics",
                        systemImage: "arrow.down.circle",
                        description: Text("Browse a remote server and open a comic once to keep a downloaded copy ready on this device.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.entries) { entry in
                            NavigationLink {
                                RemoteComicLoadingView(
                                    profile: entry.profile,
                                    item: entry.session.directoryItem,
                                    dependencies: dependencies,
                                    openMode: .preferLocalCache
                                )
                            } label: {
                                RemoteOfflineShelfCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(background)
        .navigationTitle("Offline Shelf")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.summaryTitle)
                .font(.title2.bold())

            Text(viewModel.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(
                viewModel.cacheSummary.isEmpty ? "No downloaded remote comics yet" : viewModel.cacheSummary.summaryText,
                systemImage: "internaldrive.fill"
            )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.65),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct RemoteOfflineShelfCard: View {
    let entry: RemoteOfflineShelfViewModel.Entry

    private var badgeTint: Color {
        switch entry.availability.kind {
        case .unavailable:
            return .secondary
        case .current:
            return .blue
        case .stale:
            return .orange
        }
    }

    private var summaryText: String {
        switch entry.availability.kind {
        case .unavailable:
            return "This local copy is no longer available."
        case .current:
            return "Opens directly from the downloaded copy saved on this device."
        case .stale:
            return "Opens from a downloaded copy on this device. The remote server may have a newer version."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(badgeTint)
                    .frame(width: 32, height: 32)
                    .background(badgeTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.session.displayName)
                        .font(.headline)

                    Text(entry.profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                if let badgeTitle = entry.availability.badgeTitle {
                    StatusBadge(title: badgeTitle, tint: badgeTint)
                }

                StatusBadge(
                    title: entry.session.progressText,
                    tint: entry.session.read ? .green : .orange
                )
            }

            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Last opened \(entry.session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}
