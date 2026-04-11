import SwiftUI

struct RemoteBrowserContextGlyph: View {
    let isRoot: Bool

    private var tint: Color {
        isRoot ? .teal : .blue
    }

    private var systemImage: String {
        isRoot ? "square.grid.2x2.fill" : "folder.fill"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

struct RemoteBrowserQuickActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

struct RemoteDirectoryItemListRow: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    var heroSourceID: String? = nil
    var trailingAccessoryReservedWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            leadingVisual

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                RemoteInlineMetadataStrip(
                    items: supportingMetadataItems,
                    spacing: 8
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .contentShape(Rectangle())
    }

    private var supportingMetadataItems: [RemoteInlineMetadataItem] {
        var items = [RemoteInlineMetadataItem]()

        if item.isDirectory {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "folder",
                    text: "Folder",
                    tint: .blue
                )
            )

            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "clock",
                    text: item.modifiedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Browse folder",
                    tint: .secondary
                )
            )
            return items
        }

        if item.isComicDirectory {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "photo.on.rectangle",
                    text: item.pageCountHint.map { "\($0) pages" } ?? "Image folder comic",
                    tint: .secondary
                )
            )
        }

        if let readingSession {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "book.closed",
                    text: readingSession.progressText,
                    tint: readingSession.readingProgressTint
                )
            )
            return items
        }

        if let cacheBadgeTitle = cacheAvailability.badgeTitle {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: cacheAvailability.kind == .current
                        ? "arrow.down.circle.fill"
                        : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                    text: cacheBadgeTitle,
                    tint: cacheAvailability.kind == .current ? .blue : .orange
                )
            )
            return items
        }

        if let fileSize = item.fileSize {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "internaldrive",
                    text: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                    tint: .secondary
                )
            )
        } else {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: item.isComicDirectory ? "photo.on.rectangle" : (item.canOpenAsComic ? "book.closed" : "doc"),
                    text: item.isComicDirectory ? "Image folder comic" : (item.canOpenAsComic ? "Comic file" : "Remote file"),
                    tint: .secondary
                )
            )
        }

        if let modifiedAt = item.modifiedAt {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "clock",
                    text: modifiedAt.formatted(date: .abbreviated, time: .omitted),
                    tint: .secondary
                )
            )
        }

        return items
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.canOpenAsComic {
            RemoteComicThumbnailView(
                profile: profile,
                item: item,
                browsingService: browsingService,
                prefersLocalCache: cacheAvailability.hasLocalCopy,
                heroSourceID: heroSourceID,
                width: 44,
                height: 62
            )
            .overlay(alignment: .bottomTrailing) {
                cacheStatusDot(size: 8)
            }
        } else {
            RemoteDirectorySymbolTile(
                systemImage: item.isDirectory ? "folder.fill" : "doc.richtext.fill",
                tint: item.isDirectory ? .blue : .green,
                width: 44,
                height: 62
            )
        }
    }

    @ViewBuilder
    private func cacheStatusDot(size: CGFloat) -> some View {
        switch cacheAvailability.kind {
        case .current:
            Image(systemName: "circle.fill")
                .font(.system(size: size))
                .foregroundStyle(Color.statusCached)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .offset(x: Spacing.xxxs, y: Spacing.xxxs)
        case .stale:
            Image(systemName: "circle.fill")
                .font(.system(size: size))
                .foregroundStyle(Color.statusStale)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0.5)
                .offset(x: Spacing.xxxs, y: Spacing.xxxs)
        case .unavailable:
            EmptyView()
        }
    }

}

extension RemoteDirectoryItemListRow: Equatable {
    static func == (lhs: RemoteDirectoryItemListRow, rhs: RemoteDirectoryItemListRow) -> Bool {
        lhs.item == rhs.item
            && lhs.readingSession == rhs.readingSession
            && lhs.cacheAvailability == rhs.cacheAvailability
            && lhs.profile.id == rhs.profile.id
            && lhs.heroSourceID == rhs.heroSourceID
            && lhs.trailingAccessoryReservedWidth == rhs.trailingAccessoryReservedWidth
    }
}

struct RemoteDirectoryGridCard: View {
    let item: RemoteDirectoryItem
    let readingSession: RemoteComicReadingSession?
    let cacheAvailability: RemoteComicCachedAvailability
    let profile: RemoteServerProfile
    let browsingService: RemoteServerBrowsingService
    var heroSourceID: String? = nil

    private var presentation: RemoteDirectoryItemPresentation {
        RemoteDirectoryItemPresentation(
            item: item,
            readingSession: readingSession,
            cacheAvailability: cacheAvailability
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            leadingVisual
                .frame(maxWidth: .infinity)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: CornerRadius.card,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: CornerRadius.card
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(AppFont.footnote(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                compactStatusLine
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
        }
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    }

    @ViewBuilder
    private var compactStatusLine: some View {
        RemoteInlineMetadataLine(
            items: presentation.metadataItems,
            horizontalSpacing: Spacing.xs,
            verticalSpacing: Spacing.xxs
        )
    }

    @ViewBuilder
    private var supportingSummaryLine: some View {
        RemoteDirectorySupportingLine(
            systemImage: presentation.supportingSystemImage,
            text: presentation.supportingText,
            tint: presentation.supportingTint,
            lineLimit: 2
        )
    }

    @ViewBuilder
    private var leadingVisual: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width
            let imageHeight = cardWidth / AppLayout.coverAspectRatio

            if item.canOpenAsComic {
                RemoteComicThumbnailView(
                    profile: profile,
                    item: item,
                    browsingService: browsingService,
                    prefersLocalCache: cacheAvailability.hasLocalCopy,
                    heroSourceID: heroSourceID,
                    width: cardWidth,
                    height: imageHeight
                )
                .frame(width: cardWidth, height: imageHeight)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    gridCacheStatusBadge
                }
                .overlay(alignment: .bottom) {
                    readingProgressBar
                }
            } else {
                LinearGradient(
                    colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: cardWidth, height: imageHeight)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: cardWidth * 0.22, weight: .semibold))
                        .foregroundStyle(.blue.opacity(0.75))
                }
            }
        }
        .aspectRatio(AppLayout.coverAspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private var readingProgressBar: some View {
        if let session = readingSession, session.hasBeenOpened, !session.read,
           let pageCount = session.pageCount, pageCount > 0 {
            GeometryReader { proxy in
                let progress = CGFloat(session.currentPage) / CGFloat(pageCount)
                Rectangle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: proxy.size.width * progress, height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
        }
    }

    @ViewBuilder
    private var gridCacheStatusBadge: some View {
        switch cacheAvailability.kind {
        case .current:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .background(Circle().fill(Color.statusCached).padding(-1))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .padding(Spacing.xs)
        case .stale:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .background(Circle().fill(Color.statusStale).padding(-1))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .padding(Spacing.xs)
        case .unavailable:
            EmptyView()
        }
    }

}

extension RemoteDirectoryGridCard: Equatable {
    static func == (lhs: RemoteDirectoryGridCard, rhs: RemoteDirectoryGridCard) -> Bool {
        lhs.item == rhs.item
            && lhs.readingSession == rhs.readingSession
            && lhs.cacheAvailability == rhs.cacheAvailability
            && lhs.profile.id == rhs.profile.id
            && lhs.heroSourceID == rhs.heroSourceID
    }
}

private struct RemoteDirectoryItemPresentation {
    let metadataItems: [RemoteInlineMetadataItem]
    let supportingText: String
    let supportingSystemImage: String
    let supportingTint: Color

    init(
        item: RemoteDirectoryItem,
        readingSession: RemoteComicReadingSession?,
        cacheAvailability: RemoteComicCachedAvailability
    ) {
        var metadataItems = [RemoteInlineMetadataItem]()
        var overviewSegments: [String] = []
        let supportingText: String
        let supportingSystemImage: String

        if item.isComicDirectory, let pageCountHint = item.pageCountHint {
            metadataItems.append(
                RemoteInlineMetadataItem(
                    systemImage: "photo.on.rectangle",
                    text: "\(pageCountHint) pages",
                    tint: .secondary
                )
            )
        }

        if let readingSession {
            metadataItems.append(
                RemoteInlineMetadataItem(
                    systemImage: "book.closed",
                    text: readingSession.progressText,
                    tint: readingSession.read ? .green : .orange
                )
            )
        }

        if let cacheBadgeTitle = cacheAvailability.badgeTitle {
            metadataItems.append(
                RemoteInlineMetadataItem(
                    systemImage: cacheAvailability.kind == .current
                        ? "arrow.down.circle.fill"
                        : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                    text: cacheBadgeTitle,
                    tint: cacheAvailability.kind == .current ? .blue : .orange
                )
            )
        }

        if let fileSize = item.fileSize, item.canOpenAsComic {
            metadataItems.append(
                RemoteInlineMetadataItem(
                    systemImage: "internaldrive",
                    text: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                    tint: .secondary
                )
            )
            overviewSegments.append(
                ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            )
        }

        if let modifiedAt = item.modifiedAt {
            overviewSegments.append(
                modifiedAt.formatted(date: .abbreviated, time: .omitted)
            )
        }

        self.metadataItems = metadataItems
        if overviewSegments.isEmpty {
            if item.isDirectory {
                supportingText = "Browse this folder"
            } else if item.isComicDirectory {
                supportingText = item.pageCountHint.map { "\($0) image pages" } ?? "Image folder comic"
            } else if item.canOpenAsComic {
                supportingText = "Open comic"
            } else {
                supportingText = "Remote file"
            }
        } else {
            supportingText = overviewSegments.joined(separator: " · ")
        }
        self.supportingText = supportingText

        if item.isDirectory {
            supportingSystemImage = "folder.fill"
        } else if item.isComicDirectory {
            supportingSystemImage = "photo.on.rectangle.fill"
        } else if item.canOpenAsComic {
            supportingSystemImage = "book.closed.fill"
        } else {
            supportingSystemImage = "doc.fill"
        }
        self.supportingSystemImage = supportingSystemImage
        self.supportingTint = item.isDirectory ? .blue : .secondary
    }
}

private struct RemoteDirectorySupportingLine: View {
    let systemImage: String
    let text: String
    let tint: Color
    var lineLimit = 1

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, Spacing.xxxs)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}

private struct RemoteDirectorySymbolTile: View {
    let systemImage: String
    let tint: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.10), lineWidth: 1)
            }
    }
}

struct RemoteBrowserImportProgressView: View {
    let progress: RemoteBrowserProgressState
    var onCancel: (() -> Void)? = nil

    var body: some View {
        RemoteBrowserOverlaySurface {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(progress.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if let fraction = progress.clampedFraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let detail = progress.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let fraction = progress.clampedFraction {
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                } else {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Working…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let onCancel {
                    Button("Cancel Import", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, Spacing.xxxs)
                }
            }
        }
    }
}

struct RemoteBrowserCollapsibleImportProgressView: View {
    let progress: RemoteBrowserProgressState
    @Binding var isExpanded: Bool
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                expandedCard
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.82, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.9, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                    )
            } else {
                compactButton
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.78, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.92, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(AppAnimation.overlayPop, value: isExpanded)
    }

    private var expandedCard: some View {
        RemoteBrowserOverlaySurface {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(progress.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            if let fraction = progress.clampedFraction {
                                Text("\(Int((fraction * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let detail = progress.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Button {
                        withAnimation(AppAnimation.overlayPop) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse Import")
                }

                if let fraction = progress.clampedFraction {
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                } else {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Working…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let onCancel {
                    Button("Cancel Import", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, Spacing.xxxs)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .trailing)
    }

    private var compactButton: some View {
        Button {
            withAnimation(AppAnimation.overlayPop) {
                isExpanded = true
            }
        } label: {
            RemoteBrowserImportOrb(
                progress: progress,
                size: 60,
                lineWidth: 5,
                contentMode: .percentage
            )
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand Import")
    }
}

struct RemoteBrowserFeedbackCard: View {
    let feedback: RemoteBrowserFeedbackState
    let onPrimaryAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        RemoteBrowserOverlaySurface {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: Spacing.xs) {
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
                        .padding(Spacing.xs)
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

private struct RemoteBrowserImportOrb: View {
    enum ContentMode {
        case symbol
        case percentage
    }

    let progress: RemoteBrowserProgressState
    let size: CGFloat
    let lineWidth: CGFloat
    var contentMode: ContentMode = .symbol

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(Color.white.opacity(0.18))
            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: 1)

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            if let fraction = progress.clampedFraction {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.04))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.88),
                                .accentColor,
                                Color.white.opacity(0.88)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .scaleEffect(max(0.65, size / 72))
            }

            switch contentMode {
            case .symbol:
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: max(12, size * 0.3), weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
            case .percentage:
                Text(compactPercentageLabel)
                    .font(.system(size: max(12, size * 0.22), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var compactPercentageLabel: String {
        guard let fraction = progress.clampedFraction else {
            return "..."
        }

        return "\(Int((fraction * 100).rounded()))%"
    }
}

private struct RemoteBrowserOverlaySurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.xxs)
    }
}
