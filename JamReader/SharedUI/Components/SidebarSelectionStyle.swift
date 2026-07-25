import SwiftUI

extension View {
    func adaptiveRootListStyle(usesSidebarStyle: Bool) -> some View {
        modifier(AdaptiveRootListStyleModifier(usesSidebarStyle: usesSidebarStyle))
    }

    func persistentSidebarSelection(
        isSelected: Bool,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            PersistentSidebarSelectionModifier(
                isSelected: isSelected,
                isEnabled: isEnabled
            )
        )
    }
}

private struct AdaptiveRootListStyleModifier: ViewModifier {
    let usesSidebarStyle: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesSidebarStyle {
            content.listStyle(.sidebar)
        } else {
            content.listStyle(.insetGrouped)
        }
    }
}

private struct PersistentSidebarSelectionModifier: ViewModifier {
    private static let verticalContentPadding: CGFloat = 6

    let isSelected: Bool
    let isEnabled: Bool

    private var selectionShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CornerRadius.md,
            style: .continuous
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Self.verticalContentPadding)
                .background {
                    selectionShape
                        .fill(
                            isSelected
                                ? Color(uiColor: .tertiarySystemFill)
                                : Color.clear
                        )
                }
                .contentShape(.interaction, selectionShape)
                .contentShape(.hoverEffect, selectionShape)
                .hoverEffect(.highlight)
                .listRowInsets(
                    EdgeInsets(
                        top: Spacing.xxs,
                        leading: Spacing.xs,
                        bottom: Spacing.xxs,
                        trailing: Spacing.xs
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            content
        }
    }
}
