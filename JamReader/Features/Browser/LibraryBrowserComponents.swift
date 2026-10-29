import SwiftUI

struct LibraryShortcutCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImageName: String
    let tint: Color
    let metadataText: String?
    let destination: AnyView
    let route: LibraryNavigationRoute?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImageName: String,
        tint: Color,
        metadataText: String? = nil,
        destination: AnyView,
        route: LibraryNavigationRoute? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.tint = tint
        self.metadataText = metadataText
        self.destination = destination
        self.route = route
    }
}

/// Main card of continue reading: cover, the title once, progress and
/// Continue. The whole card is one button; only the home aggregate names the
/// source library. See docs/design-system/components/ContinueReading.
struct ContinueReadingCard: View {
    let comic: LibraryComic
    let coverURL: URL?
    var coverSource: LocalComicCoverSource? = nil
    var heroSourceID: String? = nil
    var sourceLibraryName: String? = nil
    /// `surface-2` on plain pages; grouped pages such as the home pass `surface`.
    var background: Color = .surfaceSecondary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let coverWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            cover

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                if let sourceLibraryName {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "books.vertical")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(sourceLibraryName)
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                }

                Text(comic.displayTitle)
                    .font(AppFont.headline())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: Spacing.xs)

                JamProgressBar(fraction: comic.continueReadingFraction, height: 4)

                footer
                    .padding(.top, Spacing.xxs)
            }
            .frame(maxWidth: .infinity, minHeight: coverWidth / AppLayout.coverAspectRatio, alignment: .topLeading)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var cover: some View {
        LocalCoverThumbnailView(
            url: coverURL,
            fallbackSource: coverSource,
            placeholderSystemName: "book.closed",
            transitionKey: heroSourceID,
            heroSourceID: heroSourceID,
            width: coverWidth,
            height: coverWidth / AppLayout.coverAspectRatio
        )
        .overlay(alignment: .bottom) {
            if let fraction = comic.readingFraction {
                LibraryCoverProgressBar(fraction: fraction)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.thumbnail, style: .continuous))
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                progressText
                continueLabel
            }
        } else {
            HStack(spacing: Spacing.xs) {
                progressText
                    .frame(maxWidth: .infinity, alignment: .leading)
                continueLabel
            }
        }
    }

    private var progressText: some View {
        Text(comic.continueReadingProgressText)
            .font(AppFont.footnote())
            .foregroundStyle(Color.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
    }

    /// Looks like a small primary button; the card itself is the button.
    private var continueLabel: some View {
        Text("Continue")
            .font(AppFont.subheadline(.semibold))
            .foregroundStyle(Color.appOnJam)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color.appJam, in: Capsule())
    }
}

/// Jam progress on the system progress track (`fill-strong`).
struct JamProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemFill))

                Capsule()
                    .fill(Color.appJam)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension LibraryComic {
    /// Progress of a comic in continue reading, which also lists opened
    /// comics still on their first page.
    var continueReadingFraction: Double {
        guard let pageCount, pageCount > 0 else {
            return 0
        }

        return min(max(Double(currentPage) / Double(pageCount), 0), 1)
    }

    /// "Page 78 of 186 · Yesterday".
    var continueReadingProgressText: String {
        var parts: [String] = []
        if let pageCount, pageCount > 0 {
            parts.append(String(localized: "Page \(max(currentPage, 1)) of \(pageCount)"))
        } else if currentPage > 0 {
            parts.append(String(localized: "Page \(currentPage)"))
        }

        if let lastOpenedAt {
            parts.append(lastOpenedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }

        // Lines break only between the parts, never inside "3 min. ago".
        return parts
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " · ")
    }
}

struct LibraryBrowserContentCard<Content: View>: View {
    let minHeight: CGFloat
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 18
    var strokeOpacity: Double = 0.06
    var isSelected = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            strokeOpacity: strokeOpacity
        ) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.appJam, lineWidth: 2)
            }
        }
    }
}

struct LibraryBrowserListRowShell<
    LeadingAccessory: View,
    Thumbnail: View,
    Content: View,
    TrailingAccessory: View
>: View {
    var spacing: CGFloat = Spacing.sm
    var trailingAccessoryReservedWidth: CGFloat = 0
    @ViewBuilder let leadingAccessory: () -> LeadingAccessory
    @ViewBuilder let thumbnail: () -> Thumbnail
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailingAccessory: () -> TrailingAccessory

    var body: some View {
        HStack(spacing: spacing) {
            leadingAccessory()
            thumbnail()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingAccessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .padding(.trailing, trailingAccessoryReservedWidth)
        .contentShape(Rectangle())
    }
}

extension LibraryFolder {
    var browserMetadataText: String? {
        var parts: [String] = []

        if !isRoot && type != .comic {
            parts.append(type.title)
        }

        if finished {
            parts.append(String(localized: "Finished"))
        } else if completed {
            parts.append(String(localized: "Complete"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension LibraryComic {
    var browserMetadataText: String? {
        var parts: [String] = []

        if let issueLabel {
            parts.append("#\(issueLabel)")
        }

        if type != .comic || parts.isEmpty {
            parts.append(type.title)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
