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
    var showsServerName = true
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        InsetCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 30, height: 30)
                    .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.title)
                        .font(.headline)
                }

                Spacer(minLength: 8)

                if showsNavigationIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            AdaptiveStatusBadgeGroup(
                badges: shortcutBadges,
                horizontalSpacing: 6,
                verticalSpacing: 6
            )

            FormOverviewContent(items: shortcutOverviewItems)
        }
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    private var shortcutBadges: [StatusBadgeItem] {
        [
            StatusBadgeItem(
                title: profile.providerKind.title,
                tint: profile.providerKind.tintColor
            )
        ]
    }

    private var shortcutOverviewItems: [FormOverviewItem] {
        var items = [FormOverviewItem]()

        if showsServerName {
            items.append(FormOverviewItem(title: "Server", value: profile.name))
        }

        items.append(
            FormOverviewItem(
                title: "Path",
                value: shortcut.path.isEmpty ? "/" : shortcut.path
            )
        )

        items.append(
            FormOverviewItem(
                title: "Updated",
                value: shortcut.updatedAt.formatted(date: .abbreviated, time: .omitted)
            )
        )

        return items
    }
}

struct RemoteOfflineComicCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability
    var showsNavigationIndicator = true
    var showsServerName = true
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

    private var availabilityStatusText: String {
        switch availability.kind {
        case .unavailable:
            return "No local copy"
        case .current:
            return "Ready on device"
        case .stale:
            return "Local copy may be older"
        }
    }

    var body: some View {
        InsetCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(availabilityTint)
                    .frame(width: 30, height: 30)
                    .background(availabilityTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)
                }

                Spacer(minLength: 8)

                if showsNavigationIndicator {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }

            AdaptiveStatusBadgeGroup(
                badges: statusBadges,
                horizontalSpacing: 6,
                verticalSpacing: 6
            )

            FormOverviewContent(items: overviewItems)
        }
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    private var statusBadges: [StatusBadgeItem] {
        var badges = [StatusBadgeItem]()

        if let badgeTitle = availability.badgeTitle {
            badges.append(StatusBadgeItem(title: badgeTitle, tint: availabilityTint))
        }

        badges.append(
            StatusBadgeItem(
                title: session.progressText,
                tint: session.read ? .green : .orange
            )
        )

        return badges
    }

    private var overviewItems: [FormOverviewItem] {
        var items = [FormOverviewItem]()

        if showsServerName {
            items.append(FormOverviewItem(title: "Server", value: profile.name))
        }

        items.append(FormOverviewItem(title: "Status", value: availabilityStatusText))
        items.append(
            FormOverviewItem(
                title: "Opened",
                value: session.lastTimeOpened.formatted(date: .abbreviated, time: .shortened)
            )
        )

        return items
    }
}
