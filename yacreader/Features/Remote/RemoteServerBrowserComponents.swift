import SwiftUI

struct RemoteDirectoryItemListRow: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let readingSession {
                        Label(readingSession.progressText, systemImage: "bookmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(readingSession.read ? .green : .orange)
                    }

                    if let fileSize = item.fileSize, item.canOpenAsComic {
                        Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let modifiedAt = item.modifiedAt {
                        Text(modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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
}

struct RemoteDirectoryGridCard: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    let onImport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                leadingVisual
                    .frame(maxWidth: .infinity)

                if let onImport {
                    Button(action: onImport) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let readingSession {
                    Text(readingSession.progressText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(readingSession.read ? .green : .orange)
                } else if let fileSize = item.fileSize, item.canOpenAsComic {
                    Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.isDirectory {
                    Text("Folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
