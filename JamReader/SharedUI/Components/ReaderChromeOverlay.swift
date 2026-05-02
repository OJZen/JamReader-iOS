import Combine
import SwiftUI
import UIKit

// MARK: - Metrics

private enum ReaderChromeMetrics {
    static let horizontalPadding: CGFloat = Spacing.md
    static let barVerticalPadding: CGFloat = Spacing.xs
    static let buttonSize: CGFloat = 44
    static let compactButtonSize: CGFloat = 28
    static let statusTopOffset: CGFloat = 78
    static let floatingPreviewCornerRadius: CGFloat = 18
    static let floatingPreviewWidthFraction: CGFloat = 0.6
    static let floatingPreviewMinWidth: CGFloat = 220
    static let floatingPreviewMaxWidth: CGFloat = 420
}

/// Encapsulates scrubber size values so they can scale with the available reader viewport.
private struct ReaderScrubberLayout {
    let thumbnailWidth: CGFloat
    let thumbnailHeight: CGFloat
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let frameHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let itemSpacing: CGFloat
    let focusDistance: CGFloat
    let maxScale: CGFloat
    let minScale: CGFloat
    let maxLift: CGFloat
    let maxNeighborSpread: CGFloat

    var itemStride: CGFloat { itemWidth + itemSpacing }

    func scaled(by scale: CGFloat) -> ReaderScrubberLayout {
        ReaderScrubberLayout(
            thumbnailWidth: thumbnailWidth * scale,
            thumbnailHeight: thumbnailHeight * scale,
            itemWidth: itemWidth * scale,
            itemHeight: itemHeight * scale,
            frameHeight: frameHeight * scale,
            topInset: topInset * scale,
            bottomInset: bottomInset * scale,
            itemSpacing: itemSpacing * scale,
            focusDistance: focusDistance * scale,
            maxScale: maxScale,
            minScale: minScale,
            maxLift: maxLift * scale,
            maxNeighborSpread: maxNeighborSpread * scale
        )
    }

    static func adaptive(
        horizontalSizeClass: UserInterfaceSizeClass?,
        viewportSize: CGSize = ReaderViewportResolver.currentBounds.size,
        userInterfaceIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> ReaderScrubberLayout {
        if userInterfaceIdiom == .pad {
            let minimumHeight: CGFloat = 700
            let maximumHeight: CGFloat = 1_366
            let minimumScale: CGFloat = 1.24
            let maximumScale: CGFloat = 1.58
            let clampedHeight = min(max(viewportSize.height, minimumHeight), maximumHeight)
            let progress = (clampedHeight - minimumHeight) / (maximumHeight - minimumHeight)
            let scale = minimumScale + (progress * (maximumScale - minimumScale))

            return ReaderScrubberLayout.regular.scaled(by: scale)
        }

        let usesRegularLayout = horizontalSizeClass == .regular
            && viewportSize.width >= AppLayout.regularReaderLayoutMinWidth
        let baseLayout: ReaderScrubberLayout = usesRegularLayout ? .regular : .compact

        guard viewportSize.height > 0 else {
            return baseLayout
        }

        let minimumHeight: CGFloat = usesRegularLayout ? 820 : 680
        let maximumHeight: CGFloat = 1_024
        let minimumScale: CGFloat = usesRegularLayout ? 1.0 : 0.98
        let maximumScale: CGFloat = usesRegularLayout ? 1.08 : 1.02
        let clampedHeight = min(max(viewportSize.height, minimumHeight), maximumHeight)
        let progress = (clampedHeight - minimumHeight) / (maximumHeight - minimumHeight)
        let scale = minimumScale + (progress * (maximumScale - minimumScale))

        return baseLayout.scaled(by: scale)
    }

    /// iPhone / compact multitasking window.
    static let compact = ReaderScrubberLayout(
        thumbnailWidth: 40,
        thumbnailHeight: 58,
        itemWidth: 46,
        itemHeight: 76,
        frameHeight: 100,
        topInset: 18,
        bottomInset: 4,
        itemSpacing: 4,
        focusDistance: 150,
        maxScale: 1.34,
        minScale: 0.78,
        maxLift: 11,
        maxNeighborSpread: 6
    )

    /// iPad / regular horizontal size class — ~1.35× larger so thumbnails are easier to tap.
    static let regular = ReaderScrubberLayout(
        thumbnailWidth: 54,
        thumbnailHeight: 78,
        itemWidth: 62,
        itemHeight: 104,
        frameHeight: 132,
        topInset: 24,
        bottomInset: 6,
        itemSpacing: 3,
        focusDistance: 260,
        maxScale: 1.22,
        minScale: 0.88,
        maxLift: 17,
        maxNeighborSpread: 10
    )
}

// MARK: - Surface Container

struct ReaderSurface<Content: View, TopBar: View, BottomBar: View, StatusOverlay: View, ModalOverlay: View>: View {
    let isInteractionLocked: Bool
    let isChromeHidden: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let topBar: () -> TopBar
    @ViewBuilder let bottomBar: (_ viewportSize: CGSize) -> BottomBar
    @ViewBuilder let statusOverlay: () -> StatusOverlay
    @ViewBuilder let modalOverlay: () -> ModalOverlay

    @State private var windowSafeAreaInsets = EdgeInsets()

    var body: some View {
        GeometryReader { proxy in
            let safeAreaInsets = ReaderSafeAreaResolver.resolvedInsets(
                from: proxy.safeAreaInsets,
                windowInsets: windowSafeAreaInsets
            )

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
                    bottomBar(proxy.size)
                }
                .allowsHitTesting(!isInteractionLocked)

                ReaderTopStatusStack(
                    isChromeHidden: isChromeHidden,
                    safeAreaInsets: safeAreaInsets
                ) {
                    statusOverlay()
                }
                .allowsHitTesting(false)

                modalOverlay()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                ReaderSafeAreaProbe { insets in
                    guard windowSafeAreaInsets != insets else {
                        return
                    }
                    windowSafeAreaInsets = insets
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Safe Area Resolution

private enum ReaderSafeAreaResolver {
    static func resolvedInsets(from geometryInsets: EdgeInsets, windowInsets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(geometryInsets.top, windowInsets.top),
            leading: max(geometryInsets.leading, windowInsets.leading),
            bottom: max(geometryInsets.bottom, windowInsets.bottom),
            trailing: max(geometryInsets.trailing, windowInsets.trailing)
        )
    }
}

private struct ReaderSafeAreaProbe: UIViewRepresentable {
    let onChange: (EdgeInsets) -> Void

    func makeUIView(context: Context) -> SafeAreaReportingView {
        let view = SafeAreaReportingView()
        view.onInsetsChanged = onChange
        return view
    }

    func updateUIView(_ uiView: SafeAreaReportingView, context: Context) {
        uiView.onInsetsChanged = onChange
        uiView.reportInsetsIfNeeded()
    }
}

private final class SafeAreaReportingView: UIView {
    var onInsetsChanged: ((EdgeInsets) -> Void)?
    private var lastReportedInsets = EdgeInsets()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportInsetsIfNeeded()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reportInsetsIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportInsetsIfNeeded()
    }

    func reportInsetsIfNeeded() {
        let uiInsets = window?.safeAreaInsets ?? safeAreaInsets
        let edgeInsets = EdgeInsets(
            top: uiInsets.top,
            leading: uiInsets.left,
            bottom: uiInsets.bottom,
            trailing: uiInsets.right
        )

        guard edgeInsets != lastReportedInsets else {
            return
        }

        lastReportedInsets = edgeInsets
        DispatchQueue.main.async { [weak self, edgeInsets] in
            self?.onInsetsChanged?(edgeInsets)
        }
    }
}

private enum ReaderViewportResolver {
    static var currentBounds: CGRect {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: {
                    $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
                }),
            let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        else {
            // Fallback: prefer key window bounds over UIScreen for iPad multitasking
            if let keyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) {
                return keyWindow.bounds
            }
            return UIScreen.main.bounds
        }

        return window.bounds
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
    let secondarySystemImage: String?
    let secondaryAccessibilityLabel: String?
    let onSecondaryAction: (() -> Void)?
    let isSecondaryDisabled: Bool
    let onMenu: () -> Void
    let isMenuDisabled: Bool

    init(
        title: String,
        onBack: @escaping () -> Void,
        secondarySystemImage: String? = nil,
        secondaryAccessibilityLabel: String? = nil,
        onSecondaryAction: (() -> Void)? = nil,
        isSecondaryDisabled: Bool = false,
        onMenu: @escaping () -> Void,
        isMenuDisabled: Bool = false
    ) {
        self.title = title
        self.onBack = onBack
        self.secondarySystemImage = secondarySystemImage
        self.secondaryAccessibilityLabel = secondaryAccessibilityLabel
        self.onSecondaryAction = onSecondaryAction
        self.isSecondaryDisabled = isSecondaryDisabled
        self.onMenu = onMenu
        self.isMenuDisabled = isMenuDisabled
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            chromeButton(systemImage: "chevron.left", action: onBack)

            Text(title)
                .font(AppFont.headline())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondarySystemImage, let onSecondaryAction {
                chromeButton(systemImage: secondarySystemImage, action: onSecondaryAction)
                    .disabled(isSecondaryDisabled)
                    .opacity(isSecondaryDisabled ? 0.4 : 1)
                    .accessibilityLabel(secondaryAccessibilityLabel ?? "Reader Action")
            }

            chromeButton(systemImage: "ellipsis", action: onMenu)
            .disabled(isMenuDisabled)
            .opacity(isMenuDisabled ? 0.4 : 1)
        }
        .padding(.vertical, ReaderChromeMetrics.barVerticalPadding)
    }

    private func chromeButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: ReaderChromeMetrics.buttonSize, height: ReaderChromeMetrics.buttonSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom Bar (Thumbnail Scrubber + Page Label)

struct ReaderBottomBar: View {
    let document: ComicDocument
    let currentPage: Int
    let pageCount: Int
    let viewportHeight: CGFloat
    let onPageSelected: (Int) -> Void
    let onPageIndicatorTapped: () -> Void
    let onScrubberInteractionChanged: (Bool) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var scrubberCoordinator: ReaderThumbnailScrubberCoordinator
    @State private var containerWidth: CGFloat = 0

    init(
        document: ComicDocument,
        currentPage: Int,
        pageCount: Int,
        viewportHeight: CGFloat,
        onPageSelected: @escaping (Int) -> Void,
        onPageIndicatorTapped: @escaping () -> Void,
        onScrubberInteractionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.document = document
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.viewportHeight = viewportHeight
        self.onPageSelected = onPageSelected
        self.onPageIndicatorTapped = onPageIndicatorTapped
        self.onScrubberInteractionChanged = onScrubberInteractionChanged
        _scrubberCoordinator = StateObject(
            wrappedValue: ReaderThumbnailScrubberCoordinator(
                initialPageIndex: max(min(currentPage - 1, max(pageCount - 1, 0)), 0)
            )
        )
    }

    private var scrubberLayout: ReaderScrubberLayout {
        ReaderScrubberLayout.adaptive(
            horizontalSizeClass: horizontalSizeClass,
            viewportSize: CGSize(
                width: max(containerWidth, 0),
                height: max(viewportHeight, 0)
            )
        )
    }

    private var displayedPage: Int {
        min(max(scrubberCoordinator.focusedPageIndex + 1, 1), max(pageCount, 1))
    }

    private var currentPageIndex: Int {
        max(min(currentPage - 1, max(pageCount - 1, 0)), 0)
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if pageCount > 1 {
                ReaderThumbnailScrubber(
                    document: document,
                    pageCount: pageCount,
                    layout: scrubberLayout,
                    coordinator: scrubberCoordinator
                ) { pageIndex in
                    onPageSelected(pageIndex + 1)
                }
            }

            Button(action: onPageIndicatorTapped) {
                HStack(spacing: Spacing.xs) {
                    Text("\(displayedPage) / \(max(pageCount, 1))")
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
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, ReaderChromeMetrics.barVerticalPadding)
        .readContainerWidth(into: $containerWidth)
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                if scrubberCoordinator.isPreviewVisible {
                    let previewWidth = floatingPreviewWidth(for: proxy.size.width)
                    ReaderFloatingPagePreview(
                        document: document,
                        pageIndex: scrubberCoordinator.focusedPageIndex,
                        previewWidth: previewWidth
                    )
                    .frame(maxWidth: .infinity)
                    .offset(
                        y: floatingPreviewOffsetY(
                            bottomBarFrame: proxy.frame(in: .global),
                            previewCardHeight: floatingPreviewCardHeight(for: previewWidth)
                        )
                    )
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: scrubberCoordinator.isPreviewVisible)
        }
        .onChange(of: currentPage) { _, newValue in
            let pageIndex = max(min(newValue - 1, max(pageCount - 1, 0)), 0)
            DispatchQueue.main.async {
                scrubberCoordinator.syncCurrentPage(pageIndex)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                scrubberCoordinator.realign(to: currentPageIndex)
            }
        }
        .onChange(of: document.fileURL) { _, _ in
            DispatchQueue.main.async {
                scrubberCoordinator.realign(to: currentPageIndex)
            }
        }
        .onChange(of: pageCount) { _, _ in
            DispatchQueue.main.async {
                scrubberCoordinator.realign(to: currentPageIndex)
            }
        }
        .onChange(of: scrubberCoordinator.isInteracting) { _, isInteracting in
            DispatchQueue.main.async {
                onScrubberInteractionChanged(isInteracting)
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                onScrubberInteractionChanged(false)
                scrubberCoordinator.cancelPendingWork()
            }
        }
    }

    private var progressPercent: Int {
        guard pageCount > 0 else { return 0 }
        return Int((Double(displayedPage) / Double(pageCount) * 100).rounded())
    }

    private func floatingPreviewWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            max(
                availableWidth * ReaderChromeMetrics.floatingPreviewWidthFraction,
                ReaderChromeMetrics.floatingPreviewMinWidth
            ),
            ReaderChromeMetrics.floatingPreviewMaxWidth
        )
    }

    private func floatingPreviewCardHeight(for previewWidth: CGFloat) -> CGFloat {
        let previewHeight = previewWidth * 1.42
        return previewHeight + 52
    }

    private func floatingPreviewOffsetY(bottomBarFrame: CGRect, previewCardHeight: CGFloat) -> CGFloat {
        let viewportBounds = ReaderViewportResolver.currentBounds
        let viewportMidY = viewportBounds.midY
        let previewHalfHeight = previewCardHeight / 2
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let upwardBias = min(
            max(viewportBounds.height * (isPad ? 0.09 : 0.06), isPad ? 56 : 28),
            isPad ? 120 : 72
        )
        return viewportMidY - bottomBarFrame.minY - previewHalfHeight - upwardBias
    }
}

private struct ReaderThumbnailScrubber: View {
    let document: ComicDocument
    let pageCount: Int
    let layout: ReaderScrubberLayout
    @ObservedObject var coordinator: ReaderThumbnailScrubberCoordinator
    let onPageCommitted: (Int) -> Void

    private let coordinateSpaceName = "ReaderThumbnailScrubberSpace"

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = proxy.size.width
            let horizontalInset = max((viewportWidth - layout.itemWidth) / 2, 0)

            ScrollViewReader { scrollProxy in
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: layout.itemSpacing) {
                            ForEach(0..<pageCount, id: \.self) { pageIndex in
                                ReaderThumbnailScrubberItem(
                                    document: document,
                                    pageIndex: pageIndex,
                                    viewportWidth: viewportWidth,
                                    coordinateSpaceName: coordinateSpaceName,
                                    layout: layout,
                                    isFocused: pageIndex == coordinator.focusedPageIndex
                                )
                                .id(pageIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.commitTap(on: pageIndex)
                                }
                                .background {
                                    GeometryReader { itemProxy in
                                        Color.clear.preference(
                                            key: ReaderThumbnailMidpointPreferenceKey.self,
                                            value: [pageIndex: itemProxy.frame(in: .named(coordinateSpaceName)).midX]
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, layout.topInset)
                        .padding(.bottom, layout.bottomInset)
                        // Placed inside the UIScrollView's content host so that
                        // findGestureHost() reliably finds this UIScrollView as a
                        // direct superview ancestor — avoiding the .mask wrapper
                        // that previously blocked sibling detection.
                        .background {
                            TouchInteractionTracker(
                                pageCount: pageCount,
                                itemStride: layout.itemStride,
                                onBegan: { coordinator.beginInteraction() },
                                onEnded: { coordinator.endInteraction() },
                                onCenteredPageIndexChanged: { coordinator.queueNearestPageIndexUpdate($0) }
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .coordinateSpace(name: coordinateSpaceName)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            coordinator.handleAppear()
                        }
                    }
                    .onChange(of: proxy.size.width) { _, _ in
                        DispatchQueue.main.async {
                            coordinator.handleViewportChange()
                        }
                    }
                    .onPreferenceChange(ReaderThumbnailMidpointPreferenceKey.self) { midpoints in
                        if let nearestPageIndex = nearestPageIndex(
                            from: midpoints,
                            viewportWidth: viewportWidth
                        ) {
                            coordinator.queueNearestPageIndexUpdate(nearestPageIndex)
                        }
                    }
                    .onChange(of: coordinator.scrollRequest) { _, request in
                        guard let request else {
                            return
                        }

                        if request.animated {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                scrollProxy.scrollTo(request.pageIndex, anchor: .center)
                            }
                        } else {
                            scrollProxy.scrollTo(request.pageIndex, anchor: .center)
                        }
                    }
                    .onChange(of: coordinator.commitRequest) { _, request in
                        guard let request else {
                            return
                        }

                        DispatchQueue.main.async {
                            onPageCommitted(request.pageIndex)
                        }
                    }
                }
            }
        }
        .frame(height: layout.frameHeight)
    }

    private func nearestPageIndex(from midpoints: [Int: CGFloat], viewportWidth: CGFloat) -> Int? {
        guard !midpoints.isEmpty else {
            return nil
        }

        let targetMidX = viewportWidth / 2
        return midpoints.min { lhs, rhs in
            abs(lhs.value - targetMidX) < abs(rhs.value - targetMidX)
        }?.key
    }
}

private struct ReaderThumbnailScrubberItem: View {
    let document: ComicDocument
    let pageIndex: Int
    let viewportWidth: CGFloat
    let coordinateSpaceName: String
    let layout: ReaderScrubberLayout
    let isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let signedDistance = proxy.frame(in: .named(coordinateSpaceName)).midX - viewportWidth / 2
            let clampedSignedProgress = max(min(signedDistance / layout.focusDistance, 1), -1)
            let normalizedDistance = abs(clampedSignedProgress)
            let focusProgress = 1 - normalizedDistance
            let scale = layout.maxScale
                - ((layout.maxScale - layout.minScale) * normalizedDistance)
            let opacity = 1 - (normalizedDistance * 0.28)
            let shoulderLift = focusProgress * focusProgress * 0.45
            let centerLift = focusProgress * focusProgress * focusProgress * focusProgress * 0.75
            let lift = (shoulderLift + centerLift) * layout.maxLift
            // Use a continuous bell-shaped offset so nearby thumbnails get
            // extra breathing room, while the centered item stays anchored
            // and never "snaps" when crossing the midpoint.
            let lateralOffset = clampedSignedProgress
                * focusProgress
                * 4
                * layout.maxNeighborSpread

            VStack(spacing: 0) {
                ReaderPageThumbnailView(
                    document: document,
                    pageIndex: pageIndex,
                    width: layout.thumbnailWidth,
                    height: layout.thumbnailHeight,
                    cornerRadius: 13,
                    style: .scrubber
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isFocused ? .white.opacity(0.92) : .clear,
                            lineWidth: isFocused ? 1.6 : 0
                        )
                }
            }
            .frame(
                width: layout.thumbnailWidth,
                height: layout.thumbnailHeight,
                alignment: .bottom
            )
            .scaleEffect(scale, anchor: .bottom)
            .opacity(opacity)
            .offset(x: lateralOffset, y: -lift)
            .shadow(
                color: .black.opacity(isFocused ? 0.34 : 0.18),
                radius: isFocused ? 10 : 5,
                y: isFocused ? 7 : 3
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
        .frame(
            width: layout.itemWidth,
            height: layout.itemHeight
        )
    }
}

private struct ReaderFloatingPagePreview: View {
    let document: ComicDocument
    let pageIndex: Int
    let previewWidth: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            ReaderPageThumbnailView(
                document: document,
                pageIndex: pageIndex,
                width: previewWidth,
                height: previewWidth * 1.42,
                cornerRadius: ReaderChromeMetrics.floatingPreviewCornerRadius,
                style: .floatingPreview
            )

            Text("Page \(pageIndex + 1)")
                .font(AppFont.caption(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 20, y: 14)
    }
}

private struct ReaderThumbnailMidpointPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ReaderThumbnailScrollRequest: Equatable {
    let id: Int
    let pageIndex: Int
    let animated: Bool
}

private struct ReaderThumbnailCommitRequest: Equatable {
    let id: Int
    let pageIndex: Int
}

@MainActor
private final class ReaderThumbnailScrubberCoordinator: ObservableObject {
    @Published private(set) var focusedPageIndex: Int
    @Published private(set) var isInteracting = false
    @Published private(set) var isPreviewVisible = false
    @Published fileprivate var scrollRequest: ReaderThumbnailScrollRequest?
    @Published fileprivate var commitRequest: ReaderThumbnailCommitRequest?

    private var requestSequence = 0
    private var settleTask: Task<Void, Never>?
    private var previewDismissTask: Task<Void, Never>?
    private var alignmentRetryTask: Task<Void, Never>?
    private var lastCommittedPageIndex: Int
    private var isTouchActive = false
    private var pendingNearestPageIndex: Int?
    private var hasQueuedNearestPageIndexFlush = false

    init(initialPageIndex: Int) {
        self.focusedPageIndex = initialPageIndex
        self.lastCommittedPageIndex = initialPageIndex
    }

    deinit {
        settleTask?.cancel()
        previewDismissTask?.cancel()
        alignmentRetryTask?.cancel()
    }

    func handleAppear() {
        enqueueScroll(to: focusedPageIndex, animated: false)
        scheduleAlignmentRetry(to: focusedPageIndex)
    }

    func handleViewportChange() {
        guard !isInteracting else {
            return
        }

        enqueueScroll(to: focusedPageIndex, animated: false)
        scheduleAlignmentRetry(to: focusedPageIndex)
    }

    func realign(to pageIndex: Int) {
        let clampedIndex = max(pageIndex, 0)
        focusedPageIndex = clampedIndex
        lastCommittedPageIndex = clampedIndex

        guard !isInteracting else {
            return
        }

        enqueueScroll(to: clampedIndex, animated: false)
        scheduleAlignmentRetry(to: clampedIndex)
    }

    func syncCurrentPage(_ pageIndex: Int) {
        let clampedIndex = max(pageIndex, 0)
        let didChange = focusedPageIndex != clampedIndex
        focusedPageIndex = clampedIndex
        lastCommittedPageIndex = clampedIndex

        guard !isInteracting, didChange else {
            return
        }

        enqueueScroll(to: clampedIndex, animated: true)
    }

    func beginInteraction() {
        guard !(isTouchActive && isInteracting && isPreviewVisible) else {
            return
        }

        alignmentRetryTask?.cancel()
        alignmentRetryTask = nil
        settleTask?.cancel()
        settleTask = nil
        previewDismissTask?.cancel()
        previewDismissTask = nil
        if !isTouchActive {
            isTouchActive = true
        }
        if !isInteracting {
            isInteracting = true
        }
        if !isPreviewVisible {
            isPreviewVisible = true
        }
    }

    func updateNearestPageIndex(_ pageIndex: Int) {
        guard isInteracting else {
            return
        }

        guard focusedPageIndex != pageIndex else {
            return
        }

        focusedPageIndex = pageIndex

        guard !isTouchActive else {
            return
        }

        scheduleSettledCommit(for: pageIndex)
    }

    func queueNearestPageIndexUpdate(_ pageIndex: Int) {
        pendingNearestPageIndex = pageIndex

        guard !hasQueuedNearestPageIndexFlush else {
            return
        }

        hasQueuedNearestPageIndexFlush = true
        DispatchQueue.main.async { [weak self] in
            self?.flushQueuedNearestPageIndexUpdate()
        }
    }

    func endInteraction() {
        guard isInteracting else {
            return
        }

        isTouchActive = false
        scheduleSettledCommit(for: focusedPageIndex)
    }

    func commitTap(on pageIndex: Int) {
        alignmentRetryTask?.cancel()
        alignmentRetryTask = nil
        settleTask?.cancel()
        settleTask = nil
        previewDismissTask?.cancel()
        previewDismissTask = nil
        isTouchActive = false
        isInteracting = false
        isPreviewVisible = true
        focusedPageIndex = pageIndex
        enqueueScroll(to: pageIndex, animated: true)
        enqueueCommit(for: pageIndex)
        schedulePreviewDismiss(after: 0.32)
    }

    func cancelPendingWork() {
        alignmentRetryTask?.cancel()
        alignmentRetryTask = nil
        settleTask?.cancel()
        settleTask = nil
        previewDismissTask?.cancel()
        previewDismissTask = nil
        pendingNearestPageIndex = nil
        hasQueuedNearestPageIndexFlush = false
        isTouchActive = false
        isInteracting = false
        isPreviewVisible = false
    }

    private func scheduleSettledCommit(for pageIndex: Int) {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.completeSettledInteraction(at: pageIndex)
        }
    }

    private func completeSettledInteraction(at pageIndex: Int) {
        guard isInteracting, !isTouchActive else {
            return
        }

        isInteracting = false
        enqueueScroll(to: pageIndex, animated: true)
        enqueueCommit(for: pageIndex)
        schedulePreviewDismiss(after: 0.24)
    }

    private func flushQueuedNearestPageIndexUpdate() {
        hasQueuedNearestPageIndexFlush = false
        guard let pageIndex = pendingNearestPageIndex else {
            return
        }

        pendingNearestPageIndex = nil
        updateNearestPageIndex(pageIndex)
    }

    private func enqueueScroll(to pageIndex: Int, animated: Bool) {
        requestSequence += 1
        scrollRequest = ReaderThumbnailScrollRequest(
            id: requestSequence,
            pageIndex: pageIndex,
            animated: animated
        )
    }

    private func enqueueCommit(for pageIndex: Int) {
        guard pageIndex != lastCommittedPageIndex else {
            return
        }

        lastCommittedPageIndex = pageIndex
        requestSequence += 1
        commitRequest = ReaderThumbnailCommitRequest(
            id: requestSequence,
            pageIndex: pageIndex
        )
    }

    private func scheduleAlignmentRetry(to pageIndex: Int) {
        alignmentRetryTask?.cancel()
        alignmentRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard
                let self,
                !Task.isCancelled,
                !self.isInteracting
            else {
                return
            }

            self.enqueueScroll(to: pageIndex, animated: false)
        }
    }

    private func schedulePreviewDismiss(after delay: TimeInterval) {
        previewDismissTask?.cancel()
        previewDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            self?.isPreviewVisible = false
        }
    }
}

// MARK: - Status Stack

struct ReaderTopStatusStack<Content: View>: View {
    let isChromeHidden: Bool
    let safeAreaInsets: EdgeInsets
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            content()
        }
        .frame(maxWidth: 420)
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
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
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

// MARK: - UIKit Touch Tracker (replaces SwiftUI DragGesture for CI compliance)

/// Detects touch-down and touch-up using a UIKit long press recognizer with zero delay.
/// The recognizer is installed on the enclosing scroll view so the scrubber can still
/// receive horizontal pan gestures while we mirror interaction state into SwiftUI.
private struct TouchInteractionTracker: UIViewRepresentable {
    let pageCount: Int
    let itemStride: CGFloat
    let onBegan: () -> Void
    let onEnded: () -> Void
    let onCenteredPageIndexChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageCount: pageCount,
            itemStride: itemStride,
            onBegan: onBegan,
            onEnded: onEnded,
            onCenteredPageIndexChanged: onCenteredPageIndexChanged
        )
    }

    func makeUIView(context: Context) -> GestureInstallerView {
        GestureInstallerView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: GestureInstallerView, context: Context) {
        context.coordinator.pageCount = pageCount
        context.coordinator.itemStride = itemStride
        context.coordinator.onBegan = onBegan
        context.coordinator.onEnded = onEnded
        context.coordinator.onCenteredPageIndexChanged = onCenteredPageIndexChanged
        uiView.installGesturesIfNeeded()
    }

    final class GestureInstallerView: UIView {
        let coordinator: Coordinator
        private weak var gestureHost: UIScrollView?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                installGesturesIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    self?.installGesturesIfNeeded()
                }
            } else {
                removeInstalledGestures()
            }
        }

        func installGesturesIfNeeded() {
            guard let host = findGestureHost() else {
                return
            }

            guard gestureHost !== host || coordinator.pressRecognizer == nil else {
                return
            }

            removeInstalledGestures()
            gestureHost = host

            if coordinator.pressRecognizer == nil {
                let pressRecognizer = UILongPressGestureRecognizer(
                    target: coordinator,
                    action: #selector(Coordinator.handlePress(_:))
                )
                pressRecognizer.minimumPressDuration = 0
                pressRecognizer.cancelsTouchesInView = false
                pressRecognizer.delegate = coordinator
                host.addGestureRecognizer(pressRecognizer)
                coordinator.pressRecognizer = pressRecognizer
            }

            host.panGestureRecognizer.addTarget(
                coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            coordinator.panRecognizer = host.panGestureRecognizer
            coordinator.observedScrollView = host
        }

        private func removeInstalledGestures() {
            if let pressRecognizer = coordinator.pressRecognizer {
                gestureHost?.removeGestureRecognizer(pressRecognizer)
            }

            if let panRecognizer = coordinator.panRecognizer {
                panRecognizer.removeTarget(
                    coordinator,
                    action: #selector(Coordinator.handlePan(_:))
                )
            }

            coordinator.pressRecognizer = nil
            coordinator.panRecognizer = nil
            coordinator.observedScrollView = nil
            coordinator.stopScrollObservation()
            gestureHost = nil
        }

        /// Finds the thumbnail UIScrollView that owns this background helper view.
        ///
        /// `TouchInteractionTracker` is placed as `.background` of the padded `LazyHStack`,
        /// which is the *content* of the thumbnail `ScrollView`.  In UIKit terms the
        /// GestureInstallerView is a subview (potentially several levels down) inside the
        /// UIScrollView's content host.  Walking the superview chain therefore always reaches
        /// the thumbnail UIScrollView before any other scroll view — the reader's
        /// UICollectionView lives in a completely different ZStack branch.
        ///
        /// We stop at the first UIScrollView we encounter.  Sibling search is intentionally
        /// removed: when the tracker was outside the ScrollView, a .mask wrapper created a
        /// sibling UIView that hid the real UIScrollView from direct-sibling detection, causing
        /// the algorithm to escape into the reader layer and find the UICollectionView instead.
        private func findGestureHost() -> UIScrollView? {
            var candidate: UIView? = self

            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                candidate = current.superview
            }

            return nil
        }

        deinit {
            removeInstalledGestures()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var pageCount: Int
        var itemStride: CGFloat
        var onBegan: () -> Void
        var onEnded: () -> Void
        var onCenteredPageIndexChanged: (Int) -> Void
        weak var pressRecognizer: UILongPressGestureRecognizer?
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var observedScrollView: UIScrollView?
        private var isInteractionActive = false
        private var isPanActive = false
        private var displayLink: CADisplayLink?
        private var lastReportedCenteredPageIndex: Int?

        init(
            pageCount: Int,
            itemStride: CGFloat,
            onBegan: @escaping () -> Void,
            onEnded: @escaping () -> Void,
            onCenteredPageIndexChanged: @escaping (Int) -> Void
        ) {
            self.pageCount = pageCount
            self.itemStride = itemStride
            self.onBegan = onBegan
            self.onEnded = onEnded
            self.onCenteredPageIndexChanged = onCenteredPageIndexChanged
        }

        @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                beginInteractionIfNeeded()
                startScrollObservationIfNeeded()
            case .ended, .cancelled, .failed:
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isPanActive else {
                        return
                    }

                    self.endInteractionIfNeeded()
                }
            default:
                break
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isPanActive = true
                beginInteractionIfNeeded()
                startScrollObservationIfNeeded()
            case .changed:
                if !isPanActive {
                    isPanActive = true
                    beginInteractionIfNeeded()
                }
                startScrollObservationIfNeeded()
                sampleCenteredPageIndex()
            case .ended, .cancelled, .failed:
                guard isPanActive else {
                    return
                }

                isPanActive = false
                endInteractionIfNeeded()
            default:
                break
            }
        }

        func stopScrollObservation() {
            displayLink?.invalidate()
            displayLink = nil
            lastReportedCenteredPageIndex = nil
        }

        private func beginInteractionIfNeeded() {
            guard !isInteractionActive else {
                return
            }

            isInteractionActive = true
            onBegan()
        }

        private func endInteractionIfNeeded() {
            guard isInteractionActive else {
                return
            }

            isInteractionActive = false
            onEnded()
        }

        private func startScrollObservationIfNeeded() {
            sampleCenteredPageIndex()

            guard displayLink == nil else {
                return
            }

            let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        @objc private func handleDisplayLinkTick() {
            sampleCenteredPageIndex()

            guard let observedScrollView else {
                stopScrollObservation()
                return
            }

            if !observedScrollView.isDragging && !observedScrollView.isDecelerating && !isInteractionActive {
                stopScrollObservation()
            }
        }

        private func sampleCenteredPageIndex() {
            guard pageCount > 0,
                  itemStride > 0,
                  let observedScrollView else {
                return
            }

            let centeredPageIndex = min(
                max(Int(round(observedScrollView.contentOffset.x / itemStride)), 0),
                pageCount - 1
            )

            guard centeredPageIndex != lastReportedCenteredPageIndex else {
                return
            }

            lastReportedCenteredPageIndex = centeredPageIndex
            onCenteredPageIndexChanged(centeredPageIndex)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
