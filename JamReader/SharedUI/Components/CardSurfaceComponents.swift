import SwiftUI

struct InsetCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var contentPadding: CGFloat = 16
    var backgroundColor: Color = Color(.secondarySystemBackground)
    var strokeOpacity: Double = 0.05
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(contentPadding)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(strokeOpacity), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .hoverEffect(.lift)
    }
}

struct InsetListRowCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var contentPadding: CGFloat = 12
    var backgroundColor: Color = Color(.systemBackground)
    var strokeOpacity: Double = 0.04
    @ViewBuilder let content: () -> Content

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            backgroundColor: backgroundColor,
            strokeOpacity: strokeOpacity
        ) {
            content()
        }
    }
}

struct AdaptiveCardListRows<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    private let items: [Data.Element]
    private let columnCount: Int
    private let spacing: CGFloat
    private let horizontalInset: CGFloat
    private let top: CGFloat
    private let bottom: CGFloat
    private let appliesListRowStyling: Bool
    @ViewBuilder private let content: (Data.Element) -> Content

    init(
        _ data: Data,
        columnCount: Int,
        spacing: CGFloat = Spacing.sm,
        horizontalInset: CGFloat = 0,
        top: CGFloat = 6,
        bottom: CGFloat = 6,
        appliesListRowStyling: Bool = true,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = Array(data)
        self.columnCount = max(columnCount, 1)
        self.spacing = spacing
        self.horizontalInset = horizontalInset
        self.top = top
        self.bottom = bottom
        self.appliesListRowStyling = appliesListRowStyling
        self.content = content
    }

    var body: some View {
        if columnCount <= 1 {
            ForEach(items) { item in
                if appliesListRowStyling {
                    content(item)
                        .insetCardListRow(
                            horizontalInset: horizontalInset,
                            top: top,
                            bottom: bottom
                        )
                } else {
                    content(item)
                }
            }
        } else {
            ForEach(Array(groupedItems.enumerated()), id: \.offset) { _, rowItems in
                let row = HStack(alignment: .top, spacing: spacing) {
                    ForEach(rowItems) { item in
                        content(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(0..<max(0, columnCount - rowItems.count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                if appliesListRowStyling {
                    row.insetCardListRow(
                        horizontalInset: horizontalInset,
                        top: top,
                        bottom: bottom
                    )
                } else {
                    row
                }
            }
        }
    }

    private var groupedItems: [[Data.Element]] {
        guard columnCount > 1 else {
            return items.map { [$0] }
        }

        var result: [[Data.Element]] = []
        var index = 0
        while index < items.count {
            let endIndex = min(index + columnCount, items.count)
            result.append(Array(items[index..<endIndex]))
            index = endIndex
        }
        return result
    }
}

// MARK: - List Icon Badge

/// Standard iOS-style icon badge for navigation list rows.
/// Matches the visual pattern from iOS Settings.app — colored rounded-square background with white icon.
struct ListIconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}

// MARK: - Comic Status Meta Row

/// Compact single-line reading status for comic list rows.
/// Shows a status icon + progress text, then optional favorite/bookmark indicators.
/// Designed to replace AdaptiveStatusBadgeGroup in narrow list-row contexts.
struct ComicStatusMetaRow: View {
    let progressText: String
    let isRead: Bool
    var isFavorite: Bool = false
    var bookmarkCount: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRead ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isRead ? Color.statusRead : Color(.quaternaryLabel))

            Text(progressText)
                .font(.caption.weight(.medium))
                .foregroundStyle(isRead ? Color.statusRead : .secondary)

            if isFavorite {
                dot
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.appFavorite)
            }

            if bookmarkCount > 0 {
                dot
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.appAccent)
                Text("\(bookmarkCount)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var dot: some View {
        Text("·")
            .font(.caption)
            .foregroundStyle(Color(.quaternaryLabel))
    }
}

struct CompactActionChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

struct InlineMetadataItem: Identifiable {
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

struct InlineMetadataLine: View {
    let items: [InlineMetadataItem]
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 6

    private var visibleItems: [InlineMetadataItem] {
        items.filter { !$0.text.isEmpty }
    }

    @ViewBuilder
    var body: some View {
        if !visibleItems.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: horizontalSpacing) {
                    ForEach(visibleItems) { item in
                        InlineMetadataToken(item: item)
                    }
                }

                VStack(alignment: .leading, spacing: verticalSpacing) {
                    ForEach(visibleItems) { item in
                        InlineMetadataToken(item: item)
                    }
                }
            }
        }
    }
}

struct StatusBadgeItem: Identifiable {
    let id: String
    let title: String
    let tint: Color

    init(
        title: String,
        tint: Color,
        id: String? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.tint = tint
    }
}

private struct InlineMetadataToken: View {
    let item: InlineMetadataItem

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

struct AdaptiveStatusBadgeGroup: View {
    let badges: [StatusBadgeItem]
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    private var visibleBadges: [StatusBadgeItem] {
        badges.filter { !$0.title.isEmpty }
    }

    @ViewBuilder
    var body: some View {
        if !visibleBadges.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: horizontalSpacing) {
                    ForEach(visibleBadges) { badge in
                        StatusBadge(title: badge.title, tint: badge.tint)
                    }
                }

                VStack(alignment: .leading, spacing: verticalSpacing) {
                    ForEach(visibleBadges) { badge in
                        StatusBadge(title: badge.title, tint: badge.tint)
                    }
                }
            }
        }
    }
}

enum SummaryMetricPillStyle {
    case prominentValue
    case compactValue
}

struct SummaryMetricItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let tint: Color

    init(
        title: String,
        value: String,
        tint: Color,
        id: String? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.tint = tint
    }
}

struct SummaryMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    var style: SummaryMetricPillStyle = .prominentValue

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            if style == .compactValue {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var verticalSpacing: CGFloat {
        switch style {
        case .prominentValue:
            return 3
        case .compactValue:
            return 2
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .prominentValue:
            return 10
        case .compactValue:
            return 9
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .prominentValue:
            return 16
        case .compactValue:
            return 14
        }
    }
}

struct SummaryMetricGroup: View {
    let metrics: [SummaryMetricItem]
    var style: SummaryMetricPillStyle = .prominentValue
    var horizontalSpacing: CGFloat = 12
    var verticalSpacing: CGFloat = 10

    private var visibleMetrics: [SummaryMetricItem] {
        metrics.filter { !$0.value.isEmpty }
    }

    @ViewBuilder
    var body: some View {
        if !visibleMetrics.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: horizontalSpacing) {
                    ForEach(visibleMetrics) { metric in
                        SummaryMetricPill(
                            title: metric.title,
                            value: metric.value,
                            tint: metric.tint,
                            style: style
                        )
                    }
                }

                VStack(alignment: .leading, spacing: verticalSpacing) {
                    ForEach(visibleMetrics) { metric in
                        SummaryMetricPill(
                            title: metric.title,
                            value: metric.value,
                            tint: metric.tint,
                            style: style
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SectionSummaryCard<Content: View>: View {
    let title: String
    let subtitle: String?
    var badges: [StatusBadgeItem] = []
    var titleFont: Font = .title2.bold()
    var cornerRadius: CGFloat = 24
    var contentPadding: CGFloat = 18
    var strokeOpacity: Double = 0.05
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        badges: [StatusBadgeItem] = [],
        titleFont: Font = .title2.bold(),
        cornerRadius: CGFloat = 24,
        contentPadding: CGFloat = 18,
        strokeOpacity: Double = 0.05,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.titleFont = titleFont
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.strokeOpacity = strokeOpacity
        self.content = content
    }

    var body: some View {
        InsetCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            strokeOpacity: strokeOpacity
        ) {
            Text(title)
                .font(titleFont)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            AdaptiveStatusBadgeGroup(badges: badges)

            content()
        }
    }
}

extension SectionSummaryCard where Content == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        badges: [StatusBadgeItem] = [],
        titleFont: Font = .title2.bold(),
        cornerRadius: CGFloat = 24,
        contentPadding: CGFloat = 18,
        strokeOpacity: Double = 0.05
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            badges: badges,
            titleFont: titleFont,
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            strokeOpacity: strokeOpacity
        ) {
            EmptyView()
        }
    }
}

extension View {
    func insetCardListRow(
        horizontalInset: CGFloat = 0,
        top: CGFloat = 6,
        bottom: CGFloat = 6
    ) -> some View {
        listRowInsets(
            EdgeInsets(
                top: top,
                leading: horizontalInset,
                bottom: bottom,
                trailing: horizontalInset
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct FormOverviewItem: Identifiable {
    let id: String
    let title: String
    let value: String

    init(
        title: String,
        value: String,
        id: String? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
    }
}

struct FormOverviewContent<Footer: View>: View {
    let message: String?
    let items: [FormOverviewItem]
    @ViewBuilder let footer: () -> Footer

    init(
        message: String? = nil,
        items: [FormOverviewItem],
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.message = message
        self.items = items
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(items.filter { !$0.value.isEmpty }) { item in
                LabeledContent {
                    Text(item.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                } label: {
                    Text(item.title)
                }
            }

            footer()
        }
        .padding(.vertical, 6)
    }
}

extension FormOverviewContent where Footer == EmptyView {
    init(
        message: String? = nil,
        items: [FormOverviewItem]
    ) {
        self.init(message: message, items: items) {
            EmptyView()
        }
    }
}
