import SwiftUI

/// Single-choice quick filters with optional icons, scrolling sideways. At
/// accessibility sizes they wrap instead, since one chip can fill the width
/// (see components/FilterChips).
struct FilterChipBar<T: Hashable>: View {
    let items: [T]
    let selection: T
    let title: (T) -> String
    var systemImage: (T) -> String? = { _ in nil }
    let action: (T) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            WrappingHStack(horizontalSpacing: Spacing.xs, verticalSpacing: Spacing.xs) {
                chips
            }
            .padding(.vertical, Spacing.xxxs)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    chips
                }
                .padding(.vertical, Spacing.xxxs)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var chips: some View {
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
}
