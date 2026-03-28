import SwiftUI

struct RemoteInsetListRowCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            backgroundColor: Color(.systemBackground),
            strokeOpacity: 0.04
        ) {
            content()
        }
    }
}

struct RemoteSavedFolderCard: View {
    let shortcut: RemoteFolderShortcut
    let profile: RemoteServerProfile
    var showsNavigationIndicator = true
    var showsServerName = true
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        InsetCard(
            cornerRadius: 18,
            contentPadding: 12,
            backgroundColor: Color(.systemBackground),
            strokeOpacity: 0.04
        ) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 32, height: 32)
                    .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    if showsServerName {
                        Text(profile.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(shortcut.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    RemoteInlineMetadataLine(
                        items: primaryMetadataItems,
                        horizontalSpacing: 8,
                        verticalSpacing: 4
                    )

                    RemoteInlineMetadataLine(
                        items: secondaryMetadataItems,
                        horizontalSpacing: 8,
                        verticalSpacing: 4
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if showsNavigationIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    private var primaryMetadataItems: [RemoteInlineMetadataItem] {
        [
            RemoteInlineMetadataItem(
                systemImage: "folder",
                text: shortcut.path.isEmpty ? "/" : shortcut.path,
                tint: .blue
            )
        ]
    }

    private var secondaryMetadataItems: [RemoteInlineMetadataItem] {
        var items = [FormOverviewItem]()

        if !showsServerName {
            items.append(FormOverviewItem(title: "Server", value: profile.name))
        }

        items.append(
            FormOverviewItem(
                title: "Provider",
                value: profile.providerKind.title
            )
        )

        items.append(
            FormOverviewItem(
                title: "Updated",
                value: shortcut.updatedAt.formatted(date: .abbreviated, time: .omitted)
            )
        )

        return items.map { item in
            switch item.title {
            case "Server":
                return RemoteInlineMetadataItem(
                    systemImage: "server.rack",
                    text: item.value,
                    tint: .secondary
                )
            case "Provider":
                return RemoteInlineMetadataItem(
                    systemImage: "externaldrive.connected.to.line.below",
                    text: item.value,
                    tint: profile.providerKind.tintColor
                )
            default:
                return RemoteInlineMetadataItem(
                    systemImage: "clock",
                    text: item.value,
                    tint: .secondary
                )
            }
        }
    }
}

struct RemoteInlineMetadataItem: Identifiable {
    let id: String
    let systemImage: String
    let text: String
    let tint: Color

    init(
        systemImage: String,
        text: String,
        tint: Color = .secondary,
        id: String? = nil
    ) {
        self.id = id ?? "\(systemImage):\(text)"
        self.systemImage = systemImage
        self.text = text
        self.tint = tint
    }
}

struct RemoteInlineMetadataLine: View {
    let items: [RemoteInlineMetadataItem]
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 6

    private var visibleItems: [RemoteInlineMetadataItem] {
        items.filter { !$0.text.isEmpty }
    }

    @ViewBuilder
    var body: some View {
        if !visibleItems.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: horizontalSpacing) {
                    ForEach(visibleItems) { item in
                        RemoteInlineMetadataToken(item: item)
                    }
                }

                VStack(alignment: .leading, spacing: verticalSpacing) {
                    ForEach(visibleItems) { item in
                        RemoteInlineMetadataToken(item: item)
                    }
                }
            }
        }
    }
}

struct RemoteReadingProgressStrip: View {
    let progressText: String
    let fraction: Double
    let tint: Color

    private var clampedFraction: CGFloat {
        CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint)
                            .frame(
                                width: max(
                                    clampedFraction == 0 ? 0 : 6,
                                    geometry.size.width * clampedFraction
                                )
                            )
                    }
            }
            .frame(height: 4)

            Text(progressText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct RemoteInlineMetadataToken: View {
    let item: RemoteInlineMetadataItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.tint)

            Text(item.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct RemoteOfflineComicCard: View {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability
    let browsingService: RemoteServerBrowsingService
    var heroSourceID: String? = nil
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
            return "Remote only"
        case .current:
            return "Ready on device"
        case .stale:
            return "Local copy may be older"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteComicThumbnailView(
                profile: profile,
                item: session.directoryItem,
                browsingService: browsingService,
                prefersLocalCache: availability.hasLocalCopy,
                heroSourceID: heroSourceID,
                width: 60,
                height: 84
            )

            VStack(alignment: .leading, spacing: 7) {
                if showsServerName {
                    Text(profile.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(session.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                RemoteInlineMetadataLine(
                    items: locationItems,
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                )

                RemoteInlineMetadataLine(
                    items: statusItems,
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsNavigationIndicator {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    private var locationItems: [RemoteInlineMetadataItem] {
        [
            RemoteInlineMetadataItem(
                systemImage: "folder",
                text: session.parentDirectoryDisplayText,
                tint: .blue
            )
        ]
    }

    private var statusItems: [RemoteInlineMetadataItem] {
        var items = [RemoteInlineMetadataItem]()

        if session.hasBeenOpened {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "book.closed",
                    text: session.progressText,
                    tint: session.readingProgressTint
                )
            )
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "clock",
                    text: session.lastOpenedDisplayText,
                    tint: .secondary
                )
            )
        } else {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: availabilitySystemImage,
                    text: availabilityStatusText,
                    tint: availabilityTint
                )
            )

            if let fileSize = session.fileSize {
                items.append(
                    RemoteInlineMetadataItem(
                        systemImage: "internaldrive",
                        text: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                        tint: .secondary
                    )
                )
            }
        }

        return items
    }

    private var availabilitySystemImage: String {
        switch availability.kind {
        case .unavailable:
            return "icloud"
        case .current:
            return "arrow.down.circle.fill"
        case .stale:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

extension RemoteComicReadingSession {
    var readingProgressFraction: Double? {
        if read {
            return 1
        }

        if let pageCount, pageCount > 0 {
            return min(max(Double(currentPage) / Double(pageCount), 0), 1)
        }

        return hasBeenOpened && currentPage > 0 ? 0.04 : nil
    }

    var readingProgressTint: Color {
        if read {
            return .green
        }

        return hasBeenOpened ? .blue : .orange
    }

    var parentDirectoryDisplayText: String {
        let path = parentDirectoryPath
        return path.isEmpty ? "/" : path
    }

    var lastOpenedDisplayText: String {
        lastTimeOpened.formatted(date: .abbreviated, time: .shortened)
    }
}
