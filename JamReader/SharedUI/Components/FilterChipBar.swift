import SwiftUI

struct FilterChipBar<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T?
    let label: (T) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(items, id: \.self) { item in
                    let isSelected = selection == item

                    Button {
                        withAnimation(AppAnimation.standard) {
                            selection = selection == item ? nil : item
                        }
                        AppHaptics.selection()
                    } label: {
                        Text(label(item))
                            .font(AppFont.subheadline(.semibold))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
                            .background(
                                isSelected ? Color.appAccent : Color.surfaceSecondary,
                                in: RoundedRectangle(
                                    cornerRadius: CornerRadius.sm,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.xxxs)
        }
    }
}
