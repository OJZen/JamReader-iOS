import SwiftUI

/// An inline explanation at the top of content: status icon, title, message.
/// See docs/design-system/components/Notice.
struct NoticeView: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(AppFont.body(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
