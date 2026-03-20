import SwiftUI

struct RemoteDirectoryItemListRow: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(2)

                statusBadgeCluster

                metadataLine
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, trailingAccessoryReservedWidth)
    }

    @ViewBuilder
    private var statusBadgeCluster: some View {
        let descriptors = statusBadgeDescriptors

        if !descriptors.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(descriptors) { descriptor in
                        StatusBadge(title: descriptor.title, tint: descriptor.tint)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(descriptors) { descriptor in
                        StatusBadge(title: descriptor.title, tint: descriptor.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        let descriptors = metadataDescriptors

        if !descriptors.isEmpty {
            HStack(spacing: 10) {
                ForEach(descriptors) { descriptor in
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.canOpenAsComic {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                width: 54,
                height: 76
            )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.isDirectory ? Color.blue.opacity(0.14) : Color.green.opacity(0.14))
                .frame(width: 54, height: 76)
                .overlay {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.richtext.fill")
                        .font(.title3)
                        .foregroundStyle(item.isDirectory ? .blue : .green)
            }
        }
    }

    private var statusBadgeDescriptors: [RemoteDirectoryStatusBadgeDescriptor] {
        var descriptors: [RemoteDirectoryStatusBadgeDescriptor] = []

        if item.isDirectory {
            descriptors.append(RemoteDirectoryStatusBadgeDescriptor(title: "Folder", tint: .blue))
        }

        if let readingSession {
            descriptors.append(
                RemoteDirectoryStatusBadgeDescriptor(
                    title: readingSession.progressText,
                    tint: readingSession.read ? .green : .orange
                )
            )
        }

        if let cacheBadgeTitle = cacheAvailability.badgeTitle {
            descriptors.append(
                RemoteDirectoryStatusBadgeDescriptor(
                    title: cacheBadgeTitle,
                    tint: cacheAvailability.kind == .current ? .blue : .orange
                )
            )
        }

        return descriptors
    }

    private var metadataDescriptors: [RemoteDirectoryMetadataDescriptor] {
        var descriptors: [RemoteDirectoryMetadataDescriptor] = []

        if let fileSize = item.fileSize, item.canOpenAsComic {
            descriptors.append(
                RemoteDirectoryMetadataDescriptor(
                    title: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                    systemImage: "internaldrive"
                )
            )
        }

        if let modifiedAt = item.modifiedAt {
            descriptors.append(
                RemoteDirectoryMetadataDescriptor(
                    title: modifiedAt.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
            )
        }

        return descriptors
    }
}

struct RemoteDirectoryGridCard: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            leadingVisual
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                statusBadgeCluster

                metadataLine
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusBadgeCluster: some View {
        let descriptors = statusBadgeDescriptors

        if !descriptors.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(descriptors) { descriptor in
                        StatusBadge(title: descriptor.title, tint: descriptor.tint)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(descriptors) { descriptor in
                        StatusBadge(title: descriptor.title, tint: descriptor.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        let descriptors = metadataDescriptors

        if !descriptors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(descriptors) { descriptor in
                    Label(descriptor.title, systemImage: descriptor.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.canOpenAsComic {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                width: 148,
                height: 208
            )
            .padding(12)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.14))
                .frame(height: 208)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.blue)

                        Text("Folder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
            }
                .padding(12)
        }
    }

    private var statusBadgeDescriptors: [RemoteDirectoryStatusBadgeDescriptor] {
        var descriptors: [RemoteDirectoryStatusBadgeDescriptor] = []

        if item.isDirectory {
            descriptors.append(RemoteDirectoryStatusBadgeDescriptor(title: "Folder", tint: .blue))
        }

        if let readingSession {
            descriptors.append(
                RemoteDirectoryStatusBadgeDescriptor(
                    title: readingSession.progressText,
                    tint: readingSession.read ? .green : .orange
                )
            )
        }

        if let cacheBadgeTitle = cacheAvailability.badgeTitle {
            descriptors.append(
                RemoteDirectoryStatusBadgeDescriptor(
                    title: cacheBadgeTitle,
                    tint: cacheAvailability.kind == .current ? .blue : .orange
                )
            )
        }

        return descriptors
    }

    private var metadataDescriptors: [RemoteDirectoryMetadataDescriptor] {
        var descriptors: [RemoteDirectoryMetadataDescriptor] = []

        if let fileSize = item.fileSize, item.canOpenAsComic {
            descriptors.append(
                RemoteDirectoryMetadataDescriptor(
                    title: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                    systemImage: "internaldrive"
                )
            )
        }

        if let modifiedAt = item.modifiedAt {
            descriptors.append(
                RemoteDirectoryMetadataDescriptor(
                    title: modifiedAt.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
            )
        }

        return descriptors
    }
}

private struct RemoteDirectoryStatusBadgeDescriptor: Identifiable {
    let id = UUID()
    let title: String
    let tint: Color
}

private struct RemoteDirectoryMetadataDescriptor: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct RemoteBrowserImportProgressView: View {
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(description)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
