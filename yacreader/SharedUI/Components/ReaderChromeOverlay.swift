import SwiftUI
import UIKit

private enum ReaderChromeMetrics {
    static let horizontalPadding: CGFloat = 16
    static let topContentSpacing: CGFloat = 8
    static let bottomContentSpacing: CGFloat = 10
    static let buttonSize: CGFloat = 42
    static let compactButtonSize: CGFloat = 28
    static let dockItemSpacing: CGFloat = 12
    static let statusTopOffset: CGFloat = 78
}

private enum ReaderGlassKind {
    case toolbar
    case control
    case label
    case badge

    @available(iOS 26.0, *)
    var glass: Glass {
        switch self {
        case .toolbar, .label:
            .clear
        case .control, .badge:
            .regular
        }
    }

    var fallbackMaterial: Material {
        switch self {
        case .toolbar:
            .thinMaterial
        case .control, .label, .badge:
            .ultraThinMaterial
        }
    }

    var strokeOpacity: Double {
        switch self {
        case .toolbar:
            0.07
        case .control:
            0.12
        case .label:
            0.08
        case .badge:
            0.10
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .toolbar:
            0.12
        case .control:
            0.14
        case .label:
            0.10
        case .badge:
            0.12
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .toolbar:
            16
        case .control:
            12
        case .label, .badge:
            10
        }
    }
}

struct ReaderSurface<Content: View, TopBar: View, BottomBar: View, StatusOverlay: View, ModalOverlay: View>: View {
    let isInteractionLocked: Bool
    let isChromeHidden: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: () -> BottomBar
    @ViewBuilder let statusOverlay: () -> StatusOverlay
    @ViewBuilder let modalOverlay: () -> ModalOverlay

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = ReaderSafeAreaResolver.resolvedInsets(from: proxy.safeAreaInsets)

            ZStack {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!isInteractionLocked)

                ReaderChromeBackdrop(
                    isVisible: !isChromeHidden,
                    safeAreaInsets: safeAreaInsets
                )

                ReaderChromeOverlay(
                    isHidden: isChromeHidden,
                    safeAreaInsets: safeAreaInsets
                ) {
                    topBar()
                } bottomBar: {
                    bottomBar()
                }
                .allowsHitTesting(!isInteractionLocked)

                ReaderTopStatusStack(
                    isChromeHidden: isChromeHidden,
                    safeAreaInsets: safeAreaInsets
                ) {
                    statusOverlay()
                }
                .allowsHitTesting(!isInteractionLocked)

                modalOverlay()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }
}

private enum ReaderSafeAreaResolver {
    static func resolvedInsets(from geometryInsets: EdgeInsets) -> EdgeInsets {
        let windowInsets = currentWindowInsets
        return EdgeInsets(
            top: max(geometryInsets.top, windowInsets.top),
            leading: max(geometryInsets.leading, windowInsets.leading),
            bottom: max(geometryInsets.bottom, windowInsets.bottom),
            trailing: max(geometryInsets.trailing, windowInsets.trailing)
        )
    }

    private static var currentWindowInsets: EdgeInsets {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: {
                    $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
                }),
            let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        else {
            return EdgeInsets()
        }

        let insets = window.safeAreaInsets
        return EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}

private struct ReaderChromeBackdrop: View {
    let isVisible: Bool
    let safeAreaInsets: EdgeInsets

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.05),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.top + 88)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.bottom + 112)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .allowsHitTesting(false)
    }
}

struct ReaderChromeOverlay<TopBar: View, BottomBar: View>: View {
    let isHidden: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        VStack(spacing: 0) {
            if !isHidden {
                topBar()
                    .padding(.top, safeAreaInsets.top + ReaderChromeMetrics.topContentSpacing)
                    .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if !isHidden {
                bottomBar()
                    .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                    .padding(
                        .bottom,
                        max(safeAreaInsets.bottom, 8) + ReaderChromeMetrics.bottomContentSpacing
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }
}

private struct ReaderGlassSurface<S: Shape>: View {
    let shape: S
    let kind: ReaderGlassKind
    var shadowYOffset: CGFloat = 0

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(kind.glass, in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(kind.strokeOpacity), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(kind.shadowOpacity),
                    radius: kind.shadowRadius,
                    y: shadowYOffset
                )
        } else {
            shape
                .fill(kind.fallbackMaterial)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(kind.strokeOpacity), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(kind.shadowOpacity),
                    radius: kind.shadowRadius,
                    y: shadowYOffset
                )
        }
    }
}

struct ReaderTopBar<TrailingLabel: View>: View {
    let title: String
    let subtitle: String?
    let onBack: () -> Void
    private let onTrailingAction: (() -> Void)?
    private let isTrailingDisabled: Bool
    @ViewBuilder private let trailingLabel: () -> TrailingLabel

    init(
        title: String,
        subtitle: String?,
        onBack: @escaping () -> Void
    ) where TrailingLabel == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.onTrailingAction = nil
        self.isTrailingDisabled = false
        self.trailingLabel = { EmptyView() }
    }

    init(
        title: String,
        subtitle: String?,
        onBack: @escaping () -> Void,
        onTrailingAction: @escaping () -> Void,
        isTrailingDisabled: Bool = false,
        @ViewBuilder trailingLabel: @escaping () -> TrailingLabel
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.onTrailingAction = onTrailingAction
        self.isTrailingDisabled = isTrailingDisabled
        self.trailingLabel = trailingLabel
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                ReaderChromeButtonShell {
                    Image(systemName: "chevron.backward")
                        .font(.headline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)

            ReaderTopBarTitleCluster(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onTrailingAction {
                Button(action: onTrailingAction) {
                    ReaderChromeButtonShell {
                        trailingLabel()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isTrailingDisabled)
                .opacity(isTrailingDisabled ? 0.72 : 1)
            }
        }
        .frame(minHeight: ReaderChromeMetrics.buttonSize)
    }
}

private struct ReaderTopBarTitleCluster: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: subtitle == nil ? 0 : 2) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            ReaderGlassSurface(shape: Capsule(), kind: .label)
                .opacity(0.72)
        }
    }
}

struct ReaderTopStatusStack<Content: View>: View {
    let isChromeHidden: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            if !isChromeHidden {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, safeAreaInsets.top + ReaderChromeMetrics.statusTopOffset)
        .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isChromeHidden)
    }
}

struct ReaderChromeButtonShell<Content: View>: View {
    var size: CGFloat = ReaderChromeMetrics.buttonSize
    var showsBackground = true
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
    }

    var body: some View {
        content()
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .background {
                if showsBackground {
                    ReaderGlassSurface(shape: shape, kind: .control)
                }
            }
            .contentShape(shape)
    }
}

struct ReaderBottomDock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ReaderChromeMetrics.dockItemSpacing) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ReaderGlassSurface(shape: Capsule(), kind: .toolbar)
                .opacity(0.92)
        }
    }
}

struct ReaderPageIndicatorChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.pages")
                .font(.subheadline.weight(.semibold))

            Text(text)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            ReaderGlassSurface(shape: Capsule(), kind: .control)
                .opacity(0.92)
        }
        .contentShape(Capsule())
    }
}

struct ReaderContextNavigator: View {
    let positionText: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onGoPrevious: () -> Void
    let onGoNext: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onGoPrevious) {
                ReaderChromeButtonShell(
                    size: ReaderChromeMetrics.compactButtonSize,
                    showsBackground: false
                ) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrevious)
            .opacity(canGoPrevious ? 1 : 0.5)

            Text(positionText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .padding(.horizontal, 4)

            Button(action: onGoNext) {
                ReaderChromeButtonShell(
                    size: ReaderChromeMetrics.compactButtonSize,
                    showsBackground: false
                ) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            ReaderGlassSurface(shape: Capsule(), kind: .label)
                .opacity(0.6)
        }
    }
}

struct ReaderStatusBadge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                ReaderGlassSurface(shape: Capsule(), kind: .badge)
            }
    }
}
