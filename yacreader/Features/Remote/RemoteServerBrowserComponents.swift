import SwiftUI

struct RemoteDirectoryItemListRow: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    var trailingAccessoryReservedWidth: CGFloat = 0

    private var presentation: RemoteDirectoryItemPresentation {
        RemoteDirectoryItemPresentation(
            item: item,
            readingSession: readingSession,
            cacheAvailability: cacheAvailability
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                statusBadgeCluster

                overviewSummaryText
            }
        }
        .padding(.vertical, 1)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    @ViewBuilder
    private var statusBadgeCluster: some View {
        AdaptiveStatusBadgeGroup(badges: presentation.statusBadgeDescriptors)
    }

    @ViewBuilder
    private var overviewSummaryText: some View {
        if let summary = presentation.overviewSummaryText {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.canOpenAsComic {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                width: 48,
                height: 68
            )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.isDirectory ? Color.blue.opacity(0.14) : Color.green.opacity(0.14))
                .frame(width: 48, height: 68)
                .overlay {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.richtext.fill")
                        .font(.title3)
                        .foregroundStyle(item.isDirectory ? .blue : .green)
            }
        }
    }

}

struct RemoteDirectoryGridCard: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService

    private var presentation: RemoteDirectoryItemPresentation {
        RemoteDirectoryItemPresentation(
            item: item,
            readingSession: readingSession,
            cacheAvailability: cacheAvailability
        )
    }

    var body: some View {
        InsetCard(cornerRadius: 18, contentPadding: 0, strokeOpacity: 0.06) {
            leadingVisual
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                statusBadgeCluster

                overviewSummaryText
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var statusBadgeCluster: some View {
        AdaptiveStatusBadgeGroup(badges: presentation.statusBadgeDescriptors)
    }

    @ViewBuilder
    private var overviewSummaryText: some View {
        if let summary = presentation.overviewSummaryText {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.canOpenAsComic {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                width: 136,
                height: 190
            )
            .padding(10)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.14))
                .frame(height: 190)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue)
            }
                .padding(10)
        }
    }

}

private struct RemoteDirectoryItemPresentation {
    let statusBadgeDescriptors: [StatusBadgeItem]
    let overviewSummaryText: String?

    init(
        item: RemoteDirectoryItem,
        readingSession: RemoteComicReadingSession?,
        cacheAvailability: RemoteComicCachedAvailability
    ) {
        var statusBadgeDescriptors: [StatusBadgeItem] = []
        var overviewSegments: [String] = []

        if item.isDirectory {
            statusBadgeDescriptors.append(
                StatusBadgeItem(title: "Folder", tint: .blue)
            )
        }

        if let readingSession {
            statusBadgeDescriptors.append(
                StatusBadgeItem(
                    title: readingSession.progressText,
                    tint: readingSession.read ? .green : .orange
                )
            )
        }

        if let cacheBadgeTitle = cacheAvailability.badgeTitle {
            statusBadgeDescriptors.append(
                StatusBadgeItem(
                    title: cacheBadgeTitle,
                    tint: cacheAvailability.kind == .current ? .blue : .orange
                )
            )
        }

        if let fileSize = item.fileSize, item.canOpenAsComic {
            overviewSegments.append(
                ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            )
        }

        if let modifiedAt = item.modifiedAt {
            overviewSegments.append(
                modifiedAt.formatted(date: .abbreviated, time: .omitted)
            )
        }

        self.statusBadgeDescriptors = statusBadgeDescriptors
        self.overviewSummaryText = overviewSegments.isEmpty ? nil : overviewSegments.joined(separator: " · ")
    }
}

struct RemoteBrowserImportProgressView: View {
    let description: String

    var body: some View {
        RemoteBrowserOverlaySurface {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)

                Text(description)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
    }
}

struct RemoteBrowserFeedbackCard: View {
    let feedback: RemoteBrowserFeedbackState
    let onPrimaryAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        RemoteBrowserOverlaySurface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text(feedback.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let message = feedback.message, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let onPrimaryAction,
                       let primaryAction = feedback.primaryAction {
                        Button(primaryAction.title, action: onPrimaryAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }

                Spacer(minLength: 12)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var iconName: String {
        switch feedback.kind {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var iconTint: Color {
        switch feedback.kind {
        case .success:
            return .green
        case .info:
            return .blue
        }
    }
}

private struct RemoteBrowserOverlaySurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(cornerRadius: 20, contentPadding: 14, strokeOpacity: 0.05) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
