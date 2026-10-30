import SwiftUI

/// Single-choice quick filters with optional icons, scrolling sideways
/// (see components/FilterChips).
struct FilterChipBar<T: Hashable>: View {
    let items: [T]
    let selection: T
    let title: (T) -> String
    var systemImage: (T) -> String? = { _ in nil }
    let action: (T) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items, id: \.self) { item in
                    let isSelected = selection == item

                    Button {
                        AppHaptics.selection()
                        action(item)
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            if let systemImage = systemImage(item) {
                                Image(systemName: systemImage)
                                    .accessibilityHidden(true)
                            }
                            Text(title(item))
                        }
                        .font(AppFont.subheadline(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.appAccentOnSoft : Color.textPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            isSelected ? Color.appAccentSoft : Color(.tertiarySystemFill),
                            in: Capsule(style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, Spacing.xxxs)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
