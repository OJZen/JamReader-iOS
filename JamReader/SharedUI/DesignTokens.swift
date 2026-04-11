import SwiftUI
import UIKit

// MARK: - Spacing

enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20

    static let thumbnail: CGFloat = 10
    static let card: CGFloat = 14
    static let sheet: CGFloat = 20
}

// MARK: - Semantic Colors

extension Color {
    // Functional
    static let appAccent = Color.accentColor
    static let appSuccess = Color.green
    static let appWarning = Color.orange
    static let appDanger = Color.red
    static let appFavorite = Color.yellow

    // Surfaces
    static let surfacePrimary = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let surfaceGrouped = Color(.systemGroupedBackground)
    static let surfaceGroupedSecondary = Color(.secondarySystemGroupedBackground)

    // Text
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let textPlaceholder = Color(.placeholderText)

    // Status
    static let statusRead = Color.green.opacity(0.8)
    static let statusUnread = Color(.tertiaryLabel)
    static let statusOffline = Color.blue.opacity(0.8)
    static let statusStale = Color.orange.opacity(0.8)
    static let statusCached = Color.green.opacity(0.6)
}

// MARK: - Typography

enum AppFont {
    static func title(_ weight: Font.Weight = .bold) -> Font {
        .system(.title, weight: weight)
    }

    static func title2(_ weight: Font.Weight = .bold) -> Font {
        .system(.title2, weight: weight)
    }

    static func title3(_ weight: Font.Weight = .semibold) -> Font {
        .system(.title3, weight: weight)
    }

    static func headline(_ weight: Font.Weight = .semibold) -> Font {
        .system(.headline, weight: weight)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(.body, weight: weight)
    }

    static func callout(_ weight: Font.Weight = .regular) -> Font {
        .system(.callout, weight: weight)
    }

    static func subheadline(_ weight: Font.Weight = .regular) -> Font {
        .system(.subheadline, weight: weight)
    }

    static func footnote(_ weight: Font.Weight = .regular) -> Font {
        .system(.footnote, weight: weight)
    }

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(.caption, weight: weight)
    }

    static func caption2(_ weight: Font.Weight = .regular) -> Font {
        .system(.caption2, weight: weight)
    }
}

// MARK: - Shadows

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum AppShadow {
    static let sm = ShadowStyle(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
    static let md = ShadowStyle(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    static let lg = ShadowStyle(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    static let thumbnail = ShadowStyle(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
}

// MARK: - Animation

enum AppAnimation {
    static let chromeToggle = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let sheetPresent = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let overlayPop = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let quickFade = Animation.easeInOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.2)
}

// MARK: - Layout Constants

enum AppLayout {
    static let gridItemMinWidth: CGFloat = 120
    static let gridItemMaxWidth: CGFloat = 180
    static let gridSpacing: CGFloat = Spacing.sm
    static let regularInlineActionMinWidth: CGFloat = 700
    static let regularReaderLayoutMinWidth: CGFloat = 700
    static let regularNavigationSplitMinWidth: CGFloat = 780
    static let regularListTwoColumnMinWidth: CGFloat = 760
    static let regularListThreeColumnMinWidth: CGFloat = 1080

    static let coverAspectRatio: CGFloat = 2.0 / 3.0

    static let listRowHeight: CGFloat = 64
    static let listThumbnailSize: CGFloat = 48

    static let bottomBarHeight: CGFloat = 49

    static func usesRegularWidthLayout(
        horizontalSizeClass: UserInterfaceSizeClass?,
        containerWidth: CGFloat,
        minimumWidth: CGFloat = regularInlineActionMinWidth
    ) -> Bool {
        horizontalSizeClass == .regular && max(containerWidth, 0) >= minimumWidth
    }

    static func adaptiveListColumnCount(
        horizontalSizeClass: UserInterfaceSizeClass?,
        containerWidth: CGFloat
    ) -> Int {
        guard horizontalSizeClass == .regular else {
            return 1
        }

        let width = max(containerWidth, 0)
        if width >= regularListThreeColumnMinWidth {
            return 3
        }

        if width >= regularListTwoColumnMinWidth {
            return 2
        }

        return 1
    }

    static func adaptiveListColumnSpacing(for columnCount: Int) -> CGFloat {
        switch columnCount {
        case 3:
            return 10
        case 2:
            return 12
        default:
            return 0
        }
    }
}

// MARK: - Haptics

enum AppHaptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - View Modifiers

extension View {
    func appShadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Adds a pointer hover effect for iPad trackpad/mouse users.
    func pointerHoverEffect(_ effect: HoverEffect = .highlight) -> some View {
        self.hoverEffect(effect)
    }

    func adaptiveSheetWidth(_ maxWidth: CGFloat = 640) -> some View {
        modifier(AdaptiveSheetWidthModifier(maxWidth: maxWidth))
    }

    func adaptiveFormSheet(
        _ maxWidth: CGFloat = 720,
        regularMinWidth: CGFloat = AppLayout.regularInlineActionMinWidth
    ) -> some View {
        modifier(
            AdaptiveFormSheetModifier(
                maxWidth: maxWidth,
                regularMinWidth: regularMinWidth
            )
        )
    }

    func adaptiveContentWidth(
        _ maxWidth: CGFloat = 1180,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(AdaptiveContentWidthModifier(maxWidth: maxWidth, alignment: alignment))
    }

    func readContainerWidth(into width: Binding<CGFloat>) -> some View {
        modifier(ContainerWidthReaderModifier(width: width))
    }
}

private struct AdaptiveSheetWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content.frame(
            maxWidth: horizontalSizeClass == .regular ? maxWidth : .infinity
        )
    }
}

private struct AdaptiveFormSheetModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var containerWidth: CGFloat = 0

    let maxWidth: CGFloat
    let regularMinWidth: CGFloat

    private var usesExpandedSheetLayout: Bool {
        AppLayout.usesRegularWidthLayout(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: containerWidth,
            minimumWidth: regularMinWidth
        )
    }

    func body(content: Content) -> some View {
        content
            .readContainerWidth(into: $containerWidth)
            .adaptiveSheetWidth(maxWidth)
            .presentationDetents(usesExpandedSheetLayout ? [.large] : [.medium, .large])
    }
}

private struct AdaptiveContentWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let maxWidth: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(
                maxWidth: horizontalSizeClass == .regular ? maxWidth : .infinity,
                alignment: alignment
            )
            .frame(
                maxWidth: .infinity,
                alignment: horizontalSizeClass == .regular ? .center : alignment
            )
    }
}

private struct ContainerWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContainerWidthReaderModifier: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ContainerWidthPreferenceKey.self,
                        value: geometry.size.width
                    )
                }
            }
            .onPreferenceChange(ContainerWidthPreferenceKey.self) { newWidth in
                let normalizedWidth = max(newWidth, 0)
                guard Int(width.rounded(.toNearestOrAwayFromZero))
                    != Int(normalizedWidth.rounded(.toNearestOrAwayFromZero))
                else {
                    return
                }

                width = normalizedWidth
            }
    }
}

struct PersistentRowActionButtonLabel: View {
    var systemImage = "ellipsis.circle"

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
}
