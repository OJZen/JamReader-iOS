import SwiftUI

struct RemoteInsetListRowCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentPadding)
            .background(
                Color(.systemBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

struct RemoteInlineMetadataStrip: View {
    let items: [RemoteInlineMetadataItem]
    var spacing: CGFloat = 10

    private var visibleItems: [RemoteInlineMetadataItem] {
        items.filter { !$0.text.isEmpty }
    }

    @ViewBuilder
    var body: some View {
        if !visibleItems.isEmpty {
            HStack(spacing: spacing) {
                ForEach(visibleItems) { item in
                    RemoteInlineMetadataToken(item: item)
                }

                Spacer(minLength: 0)
            }
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
        read ? .appSuccess : .textSecondary
    }

    var parentDirectoryDisplayText: String {
        let path = parentDirectoryPath
        return path.isEmpty ? "/" : path
    }

    var lastOpenedDisplayText: String {
        lastTimeOpened.formatted(date: .abbreviated, time: .shortened)
    }
}
