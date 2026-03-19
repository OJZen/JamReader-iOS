import SwiftUI

private enum ReaderChromeMetrics {
    static let horizontalPadding: CGFloat = 14
    static let topSpacing: CGFloat = 4
    static let bottomSpacing: CGFloat = 8
    static let buttonSize: CGFloat = 40
    static let dockItemSpacing: CGFloat = 8
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
            let safeAreaInsets = proxy.safeAreaInsets

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
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }
}

private struct ReaderChromeBackdrop: View {
    let isVisible: Bool
    let safeAreaInsets: EdgeInsets

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.08),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.top + 104)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.bottom + 156)
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
                    .padding(.top, safeAreaInsets.top + ReaderChromeMetrics.topSpacing)
                    .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if !isHidden {
                bottomBar()
                    .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
                    .padding(.bottom, max(safeAreaInsets.bottom, 6) + ReaderChromeMetrics.bottomSpacing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
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

            if let onTrailingAction {
                Button(action: onTrailingAction) {
                    ReaderChromeButtonShell {
                        trailingLabel()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isTrailingDisabled)
                .opacity(isTrailingDisabled ? 0.72 : 1)
            } else {
                Color.clear
                    .frame(
                        width: ReaderChromeMetrics.buttonSize,
                        height: ReaderChromeMetrics.buttonSize
                    )
            }
        }
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

            if let subtitle {
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
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
        .padding(.top, safeAreaInsets.top + 64)
        .padding(.horizontal, ReaderChromeMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isChromeHidden)
    }
}

struct ReaderChromeButtonShell<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(
                minWidth: ReaderChromeMetrics.buttonSize,
                minHeight: ReaderChromeMetrics.buttonSize
            )
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct ReaderBottomDock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ReaderChromeMetrics.dockItemSpacing) {
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
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
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: ReaderChromeMetrics.buttonSize)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

struct ReaderStatusBadge<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
