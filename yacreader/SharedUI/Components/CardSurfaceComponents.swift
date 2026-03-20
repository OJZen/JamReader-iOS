import SwiftUI

struct InsetCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var contentPadding: CGFloat = 16
    var strokeOpacity: Double = 0.05
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(contentPadding)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(strokeOpacity), lineWidth: 1)
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
