import SwiftUI

struct RemoteComicInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: RemoteServerProfile
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let browsingService: RemoteServerBrowsingService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryContent
                        .padding(.vertical, 4)
                }

                if !readingRows.isEmpty {
                    Section("Reading") {
                        ForEach(readingRows) { row in
                            metadataRow(row)
                        }
                    }
                }

                Section("File") {
                    ForEach(fileRows) { row in
                        metadataRow(row)
                    }
                }

                Section("Location") {
                    ForEach(locationRows) { row in
                        metadataRow(row)
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .adaptiveSheetWidth(720)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var summaryContent: some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                prefersLocalCache: cacheAvailability.hasLocalCopy,
                width: 112,
                height: 160
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Text(formatDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    infoChip(
                        title: offlineStatusText,
                        systemImage: offlineStatusSymbolName,
                        tint: offlineStatusTint
                    )

                    if let readingSession {
                        infoChip(
                            title: readingSession.progressText,
                            systemImage: "book.closed",
                            tint: .blue
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoChip(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tint.opacity(0.12),
                in: Capsule(style: .continuous)
            )
    }

    @ViewBuilder
    private func metadataRow(_ row: RemoteComicInfoRow) -> some View {
        if row.isMultiline {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(row.value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        } else {
            LabeledContent(row.title) {
                Text(row.value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private var readingRows: [RemoteComicInfoRow] {
        guard let readingSession else {
            return []
        }

        var rows: [RemoteComicInfoRow] = [
            .init(title: "Status", value: readingSession.progressText)
        ]

        if readingSession.hasBeenOpened {
            rows.append(.init(title: "Current Page", value: "\(max(readingSession.currentPage, 1))"))
        }

        if let pageCount = readingSession.pageCount, pageCount > 0 {
            rows.append(.init(title: "Pages", value: "\(pageCount)"))
        }

        if !readingSession.bookmarkPageIndices.isEmpty {
            rows.append(.init(title: "Bookmarks", value: "\(readingSession.bookmarkPageIndices.count)"))
        }

        rows.append(
            .init(
                title: "Last Opened",
                value: readingSession.lastTimeOpened.formatted(date: .abbreviated, time: .shortened)
            )
        )

        return rows
    }

    private var fileRows: [RemoteComicInfoRow] {
        var rows: [RemoteComicInfoRow] = [
            .init(title: "Name", value: item.name),
            .init(title: "Format", value: formatDisplayName),
            .init(title: "Offline", value: offlineStatusText)
        ]

        if let fileSize = item.fileSize {
            rows.append(
                .init(
                    title: "Size",
                    value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                )
            )
        } else if let pageCountHint = item.pageCountHint, item.isComicDirectory {
            rows.append(
                .init(
                    title: "Pages",
                    value: "\(pageCountHint)"
                )
            )
        }

        if let modifiedAt = item.modifiedAt {
            rows.append(
                .init(
                    title: "Modified",
                    value: modifiedAt.formatted(date: .abbreviated, time: .shortened)
                )
            )
        }

        return rows
    }

    private var locationRows: [RemoteComicInfoRow] {
        [
            .init(title: "Server", value: profile.displayTitle),
            .init(title: "Type", value: profile.providerDisplayTitle),
            .init(title: "Address", value: profile.endpointDisplayHost),
            .init(title: "Share", value: profile.providerRootDisplayPath),
            .init(title: "Path", value: item.path, isMultiline: true)
        ]
    }

    private var formatDisplayName: String {
        if item.isComicDirectory {
            return "Image Folder Comic"
        }

        let ext = URL(fileURLWithPath: item.name).pathExtension.lowercased()
        switch ext {
        case "cbz":
            return "CBZ (ZIP)"
        case "zip":
            return "ZIP"
        case "cbr":
            return "CBR (RAR)"
        case "rar":
            return "RAR"
        case "cb7":
            return "CB7 (7Z)"
        case "7z":
            return "7Z"
        case "cbt":
            return "CBT (TAR)"
        case "tar":
            return "TAR"
        case "pdf":
            return "PDF"
        case "epub":
            return "EPUB"
        case "mobi":
            return "MOBI"
        default:
            return ext.isEmpty ? "Comic File" : ext.uppercased()
        }
    }

    private var offlineStatusText: String {
        cacheAvailability.badgeTitle ?? "Not Downloaded"
    }

    private var offlineStatusSymbolName: String {
        switch cacheAvailability.kind {
        case .unavailable:
            return "icloud.slash"
        case .current:
            return "arrow.down.circle"
        case .stale:
            return "arrow.clockwise.circle"
        }
    }

    private var offlineStatusTint: Color {
        switch cacheAvailability.kind {
        case .unavailable:
            return .secondary
        case .current:
            return .blue
        case .stale:
            return .orange
        }
    }
}

private struct RemoteComicInfoRow: Identifiable {
    let title: String
    let value: String
    var isMultiline: Bool = false

    var id: String {
        title
    }
}
