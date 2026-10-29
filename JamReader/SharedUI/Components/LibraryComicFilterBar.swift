import SwiftUI

/// Single-choice quick filters, scrolling sideways (see components/FilterChips).
struct LibraryComicFilterBar: View {
    let selection: LibraryComicQuickFilter
    let action: (LibraryComicQuickFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(LibraryComicQuickFilter.allCases) { filter in
                    let isSelected = selection == filter

                    Button {
                        AppHaptics.selection()
                        action(filter)
                    } label: {
                        Text(filter.title)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Comic Filters"))
    }
}
