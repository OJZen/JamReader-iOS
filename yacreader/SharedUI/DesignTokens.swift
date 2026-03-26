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

    static let coverAspectRatio: CGFloat = 2.0 / 3.0

    static let listRowHeight: CGFloat = 64
    static let listThumbnailSize: CGFloat = 48

    static let bottomBarHeight: CGFloat = 49
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
}
