import SwiftUI

// iOS 27 bar and margin behaviors used for iPhone Duo's side bars. Each falls
// back to the current behavior on earlier systems.
// See docs/design-system/06-iphone-duo.md.

extension ToolbarContent {
    /// The last items a crowded side bar hides: library home [+], the remote
    /// folder pin, and selection mode's Done and Mark as Read.
    @ToolbarContentBuilder
    func keepsVisibleLongest() -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            visibilityPriority(.high)
        } else {
            self
        }
    }

    /// A text button whose words carry the information (Select All) stays in
    /// the horizontal bar instead of becoming a side bar symbol.
    @ToolbarContentBuilder
    func staysInHorizontalBar() -> some ToolbarContent {
        if #available(iOS 27.1, *) {
            axisBehavior(.horizontalOnly)
        } else {
            self
        }
    }
}

extension View {
    /// Task screens (selection mode) keep their bar items when space runs out;
    /// browsing screens keep the default, which hides items first.
    @ViewBuilder
    func prefersToolbarItemsWhenCompressed(_ isEnabled: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalCompressionBehavior(isEnabled ? .prefersToolbarItems : .automatic)
        } else {
            self
        }
    }

    /// A sheet whose only bar item is Cancel keeps its bar horizontal, leaving
    /// the width to its content.
    @ViewBuilder
    func keepsSheetBarHorizontal() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}

/// A page's ⋯ menu. From iOS 27.1 its items join the system overflow menu, so
/// a screen has one ⋯ and a side bar can fold other items into it; earlier
/// systems keep the page's own ⋯ button.
struct PageOverflowMenu<Content: View>: ToolbarContent {
    private let title: LocalizedStringKey
    private let content: () -> Content

    init(_ title: LocalizedStringKey = "More", @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarOverflowMenu {
                content()
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    content()
                } label: {
                    Label(title, systemImage: "ellipsis")
                }
            }
        }
    }
}

/// The background shape of a floating container (task bar, toast). From iOS
/// 27.1 its corners follow the screen corners it sits near; earlier systems
/// keep the fixed radius.
func floatingContainerShape(cornerRadius: CGFloat) -> AnyShape {
    if #available(iOS 27.1, *) {
        return AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(cornerRadius)), isUniform: true))
    }
    return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
}

extension View {
    /// iPhone Duo: while a vertical fold is active, a floating element that is
    /// centered across the screen moves into the trailing area instead of
    /// spanning the fold, as the system does with alerts.
    func staysClearOfActiveVerticalFold() -> some View {
        modifier(StaysClearOfActiveVerticalFoldModifier())
    }
}

private struct StaysClearOfActiveVerticalFoldModifier: ViewModifier {
    @State private var trailingAreaWidth: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: trailingAreaWidth)
            .frame(maxWidth: .infinity, alignment: trailingAreaWidth == nil ? .center : .trailing)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { update(proxy) }
                        .onChange(of: proxy.size) { _, _ in update(proxy) }
                }
            }
    }

    private func update(_ proxy: GeometryProxy) {
        guard #available(iOS 27.1, *) else {
            return
        }

        let fold = proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
            .first { $0.isActive && $0.frame.height > $0.frame.width }
        let width = fold.map { max(proxy.size.width - $0.frame.maxX, 0) }
        if width != trailingAreaWidth {
            trailingAreaWidth = width
        }
    }
}

extension View {
    /// Select and Done read as text in the horizontal bar. From iOS 27.1 they
    /// keep their symbol so they can move into a side bar (a title-only item
    /// stays in the horizontal bar).
    @ViewBuilder
    func barButtonTextBeforeSideBars() -> some View {
        if #available(iOS 27.1, *) {
            self
        } else {
            labelStyle(.titleOnly)
        }
    }
}
