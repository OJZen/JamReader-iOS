import SwiftUI
import UIKit

// MARK: - Metrics

private enum ReaderChromeMetrics {
    static let horizontalPadding: CGFloat = Spacing.md
    static let barVerticalPadding: CGFloat = Spacing.xs
    static let buttonSize: CGFloat = 44
    static let compactButtonSize: CGFloat = 28
    static let statusTopOffset: CGFloat = 78
}

// MARK: - Surface Container

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

// MARK: - Safe Area Resolution

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

// MARK: - Chrome Overlay (Top + Bottom Bars)

struct ReaderChromeOverlay<TopBar: View, BottomBar: View>: View {
    let isHidden: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        VStack(spacing: 0) {
            topBar()
                .padding(.top, safeAreaInsets.top)
                .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(isHidden ? 0 : 0.55), location: 0),
                            .init(color: .black.opacity(isHidden ? 0 : 0.25), location: 0.6),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
                .ignoresSafeArea(.container, edges: .top)

            Spacer(minLength: 0)

            bottomBar()
                .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                .padding(.bottom, max(safeAreaInsets.bottom, Spacing.xs))
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(isHidden ? 0 : 0.25), location: 0.4),
                            .init(color: .black.opacity(isHidden ? 0 : 0.55), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                )
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chromeVisibility(!isHidden)
    }
}

// MARK: - Top Bar

struct ReaderTopBar: View {
    let title: String
    let onBack: () -> Void
    let onMenu: () -> Void
    let isMenuDisabled: Bool

    init(
        title: String,
        onBack: @escaping () -> Void,
        onMenu: @escaping () -> Void,
        isMenuDisabled: Bool = false
    ) {
        self.title = title
        self.onBack = onBack
        self.onMenu = onMenu
        self.isMenuDisabled = isMenuDisabled
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: ReaderChromeMetrics.buttonSize, height: ReaderChromeMetrics.buttonSize)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(AppFont.headline())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: ReaderChromeMetrics.buttonSize, height: ReaderChromeMetrics.buttonSize)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isMenuDisabled)
            .opacity(isMenuDisabled ? 0.4 : 1)
        }
        .padding(.vertical, ReaderChromeMetrics.barVerticalPadding)
    }
}

// MARK: - Bottom Bar (Slider + Page Label)

struct ReaderBottomBar: View {
    let currentPage: Int
    let pageCount: Int
    let onPageSelected: (Int) -> Void
    let onPageIndicatorTapped: () -> Void

    @State private var sliderValue: Double

    init(
        currentPage: Int,
        pageCount: Int,
        onPageSelected: @escaping (Int) -> Void,
        onPageIndicatorTapped: @escaping () -> Void
    ) {
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.onPageSelected = onPageSelected
        self.onPageIndicatorTapped = onPageIndicatorTapped
        _sliderValue = State(initialValue: Double(currentPage))
    }

    private var clampedPage: Int {
        min(max(Int(sliderValue.rounded()), 1), max(pageCount, 1))
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if pageCount > 1 {
                Slider(
                    value: $sliderValue,
                    in: 1...Double(max(pageCount, 1)),
                    step: 1
                ) { isEditing in
                    if !isEditing {
                        onPageSelected(clampedPage)
                    }
                }
                .tint(.white)
            }

            Button(action: onPageIndicatorTapped) {
                HStack(spacing: Spacing.xs) {
                    Text("\(clampedPage) / \(max(pageCount, 1))")
                        .font(AppFont.caption(.semibold).monospacedDigit())
                        .foregroundStyle(.white)

                    if pageCount > 0 {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(progressPercent)%")
                            .font(AppFont.caption(.medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, ReaderChromeMetrics.barVerticalPadding)
        .onChange(of: currentPage) { _, newValue in
            sliderValue = Double(newValue)
        }
    }

    private var progressPercent: Int {
        guard pageCount > 0 else { return 0 }
        return Int((Double(clampedPage) / Double(pageCount) * 100).rounded())
    }
}

// MARK: - Status Stack

struct ReaderTopStatusStack<Content: View>: View {
    let isChromeHidden: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: Spacing.xs) {
            content()
        }
        .padding(.top, safeAreaInsets.top + ReaderChromeMetrics.statusTopOffset)
        .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .chromeVisibility(!isChromeHidden)
    }
}

// MARK: - Legacy Compatibility Shells

struct ReaderChromeButtonShell<Content: View>: View {
    var size: CGFloat = ReaderChromeMetrics.buttonSize
    var showsBackground = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
    }
}

struct ReaderPageIndicatorChip: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "book.pages")
                .font(AppFont.subheadline(.semibold))

            Text(text)
                .font(AppFont.footnote(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
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
        HStack(spacing: Spacing.xxs) {
            Button(action: onGoPrevious) {
                Image(systemName: "chevron.left")
                    .font(AppFont.caption(.bold))
                    .foregroundStyle(.white)
                    .frame(width: ReaderChromeMetrics.compactButtonSize, height: ReaderChromeMetrics.compactButtonSize)
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrevious)
            .opacity(canGoPrevious ? 1 : 0.5)

            Text(positionText)
                .font(AppFont.caption(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, Spacing.xxs)

            Button(action: onGoNext) {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption(.bold))
                    .foregroundStyle(.white)
                    .frame(width: ReaderChromeMetrics.compactButtonSize, height: ReaderChromeMetrics.compactButtonSize)
            }
            .buttonStyle(.plain)
            .disabled(!canGoNext)
            .opacity(canGoNext ? 1 : 0.5)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ReaderStatusBadge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ReaderBottomDock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Spacing.sm) {
            content()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
