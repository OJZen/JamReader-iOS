import SwiftUI

struct RemoteCardActionMenuButton<MenuContent: View>: View {
    var accessibilityLabel = "More Actions"
    @ViewBuilder let content: MenuContent

    init(
        accessibilityLabel: String = "More Actions",
        @ViewBuilder content: () -> MenuContent
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct RemoteSavedFolderCard: View {
    let shortcut: RemoteFolderShortcut
    let profile: RemoteServerProfile
    var showsNavigationIndicator = true
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        RemoteBrowseCardShell(trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 30, height: 30)
                    .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.title)
                        .font(.headline)

                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(shortcut.path.isEmpty ? "/" : shortcut.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if showsNavigationIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 8) {
                StatusBadge(title: profile.providerKind.title, tint: profile.providerKind.tintColor)
                StatusBadge(title: "Updated \(shortcut.updatedAt.formatted(date: .abbreviated, time: .omitted))", tint: .teal)
            }
        }
    }
}

struct RemoteOfflineComicCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability
    var showsNavigationIndicator = true
    var trailingAccessoryReservedWidth: CGFloat = 0

    private var availabilityTint: Color {
        switch availability.kind {
        case .unavailable:
            return .secondary
        case .current:
            return .blue
        case .stale:
            return .orange
        }
    }

    private var subtitleText: String {
        switch availability.kind {
        case .unavailable:
            return "No downloaded copy available on this device."
        case .current:
            return "Downloaded on this device and ready to open locally."
        case .stale:
            return "A downloaded copy is available locally, but the remote file may be newer."
        }
    }

    var body: some View {
        RemoteBrowseCardShell(trailingAccessoryReservedWidth: trailingAccessoryReservedWidth) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(availabilityTint)
                    .frame(width: 30, height: 30)
                    .background(availabilityTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)

                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if showsNavigationIndicator {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 8) {
                if let badgeTitle = availability.badgeTitle {
                    StatusBadge(title: badgeTitle, tint: availabilityTint)
                }

                StatusBadge(title: session.progressText, tint: session.read ? .green : .orange)
            }

            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Last opened \(session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RemoteBrowseCardShell<Content: View>: View {
    let trailingAccessoryReservedWidth: CGFloat
    @ViewBuilder let content: Content

    init(
        trailingAccessoryReservedWidth: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.trailingAccessoryReservedWidth = trailingAccessoryReservedWidth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}
