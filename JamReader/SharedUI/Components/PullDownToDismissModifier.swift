import SwiftUI
import UIKit

enum ReaderDismissGestureDirection: Equatable {
    case down
    case right

    private static let directionalDominanceRatio: CGFloat = 2

    func accepts(_ vector: CGPoint) -> Bool {
        let primary = primaryComponent(of: vector)
        let crossAxis = abs(crossAxisComponent(of: vector))
        return primary > 0 && primary > crossAxis * Self.directionalDominanceRatio
    }

    func distance(from translation: CGPoint) -> CGFloat {
        max(primaryComponent(of: translation), 0)
    }

    func velocity(from velocity: CGPoint) -> CGFloat {
        primaryComponent(of: velocity)
    }

    func offset(for distance: CGFloat) -> CGSize {
        switch self {
        case .down:
            return CGSize(width: 0, height: max(distance, 0))
        case .right:
            return CGSize(width: max(distance, 0), height: 0)
        }
    }

    func shouldDefer(to scrollView: UIScrollView) -> Bool {
        guard scrollView.isScrollEnabled else {
            return false
        }

        let isZoomed = scrollView.maximumZoomScale > scrollView.minimumZoomScale + 0.01
            && scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        if isZoomed {
            return true
        }

        if let flowLayout = (scrollView as? UICollectionView)?.collectionViewLayout as? UICollectionViewFlowLayout,
           !matches(flowLayout.scrollDirection) {
            return false
        }

        switch self {
        case .down:
            let contentHeight = scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
            return contentHeight > scrollView.bounds.height + 1
        case .right:
            let contentWidth = scrollView.contentSize.width
                + scrollView.adjustedContentInset.left
                + scrollView.adjustedContentInset.right
            return contentWidth > scrollView.bounds.width + 1
        }
    }

    private func matches(_ scrollDirection: UICollectionView.ScrollDirection) -> Bool {
        switch (self, scrollDirection) {
        case (.down, .vertical), (.right, .horizontal):
            return true
        default:
            return false
        }
    }

    private func primaryComponent(of point: CGPoint) -> CGFloat {
        switch self {
        case .down:
            return point.y
        case .right:
            return point.x
        }
    }

    private func crossAxisComponent(of point: CGPoint) -> CGFloat {
        switch self {
        case .down:
            return point.x
        case .right:
            return point.y
        }
    }
}

// MARK: - View Modifier

extension View {
    /// Adds an interactive directional dismissal gesture to the reader.
    /// Zoomed or scrollable content along the dismissal axis keeps ownership.
    /// - Parameter onDismissGestureActiveChanged: Called when the dismiss drag starts/ends.
    ///   Use this to temporarily disable the active reader scroller.
    /// - Parameter onDismiss: Called when the custom dismiss transition should
    ///   take over and finish the close animation.
    ///   Wrap your `dismiss()` call in `withTransaction(Transaction(animation: .none))`
    ///   to prevent the system presentation animation from competing with ours.
    func pullDownToDismiss(
        isEnabled: Bool = true,
        direction: ReaderDismissGestureDirection = .down,
        isZoomed: Bool = false,
        onDismissGestureActiveChanged: ((Bool) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            PullDownToDismissModifier(
                isEnabled: isEnabled,
                direction: direction,
                isZoomed: isZoomed,
                onDismissGestureActiveChanged: onDismissGestureActiveChanged,
                onDismiss: onDismiss
            )
        )
    }
}

// MARK: - Modifier

private struct PullDownToDismissModifier: ViewModifier {
    let isEnabled: Bool
    let direction: ReaderDismissGestureDirection
    let isZoomed: Bool
    let onDismissGestureActiveChanged: ((Bool) -> Void)?
    let onDismiss: () -> Void

    @State private var dragDistance: CGFloat = 0
    @State private var isDragging = false
    @State private var isCompletingDismiss = false

    private let dismissThreshold: CGFloat = 120
    private let velocityThreshold: CGFloat = 800

    func body(content: Content) -> some View {
        ZStack {
            // Black background travels with content as one unit.
            // The whole group fades as the user drags down, revealing
            // the browser behind (requires .overFullScreen presentation).
            Color.black.ignoresSafeArea()
            content
        }
        .opacity(isEnabled ? contentOpacity : 1)
        .offset(isEnabled ? direction.offset(for: dragDistance) : .zero)
        .background {
            PullDownGestureLayer(
                isEnabled: isEnabled && !isZoomed && !isCompletingDismiss,
                direction: direction,
                onDragChanged: handleDragChanged,
                onDragEnded: handleDragEnded,
                onDragCancelled: handleDragCancelled
            )
        }
        .animation(isDragging || isCompletingDismiss ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: dragDistance)
        .onChange(of: dismissGestureState) { _, newValue in
            onDismissGestureActiveChanged?(newValue)
        }
        .onChange(of: direction) { _, _ in
            handleDragCancelled()
        }
    }

    private var contentOpacity: Double {
        guard dragDistance > 0 else { return 1.0 }
        let progress = min(dragDistance / 350, 1.0)
        return max(0, 1.0 - progress)
    }

    private var dismissGestureState: Bool {
        isDragging || isCompletingDismiss
    }

    private func handleDragChanged(_ distance: CGFloat) {
        isCompletingDismiss = false
        isDragging = true
        dragDistance = distance
    }

    private func handleDragEnded(_ distance: CGFloat, _ velocity: CGFloat) {
        isDragging = false
        dragDistance = distance

        if distance > dismissThreshold || velocity > velocityThreshold {
            isCompletingDismiss = true
            DispatchQueue.main.async {
                onDismiss()
            }
        } else {
            isCompletingDismiss = false
            dragDistance = 0
        }
    }

    private func handleDragCancelled() {
        isDragging = false
        isCompletingDismiss = false
        dragDistance = 0
    }
}

// MARK: - UIKit Gesture Layer (replaces SwiftUI DragGesture for CI compliance)

/// Installs a UIPanGestureRecognizer on a suitable ancestor view to detect
/// directional dismissal drags. Allows simultaneous recognition with reader scrolling.
private struct PullDownGestureLayer: UIViewRepresentable {
    let isEnabled: Bool
    let direction: ReaderDismissGestureDirection
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat) -> Void
    let onDragCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            direction: direction,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onDragCancelled: onDragCancelled
        )
    }

    func makeUIView(context: Context) -> GestureInstallerView {
        GestureInstallerView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: GestureInstallerView, context: Context) {
        context.coordinator.direction = direction
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.onDragCancelled = onDragCancelled
        context.coordinator.panRecognizer?.isEnabled = isEnabled
    }

    /// Invisible UIView that installs its gesture recognizer on an ancestor view.
    /// The ancestor receives touches from the content (since UIKit delivers touches
    /// to gesture recognizers on the hit-test view and all its ancestors).
    final class GestureInstallerView: UIView {
        let coordinator: Coordinator
        private weak var gestureHost: UIView?

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
                installGestureIfNeeded()
            } else {
                removeInstalledGesture()
            }
        }

        private func installGestureIfNeeded() {
            guard coordinator.panRecognizer == nil else { return }
            guard let host = findGestureHost() else { return }
            gestureHost = host

            let pan = UIPanGestureRecognizer(
                target: coordinator,
                action: #selector(Coordinator.handlePan(_:))
            )
            pan.delegate = coordinator
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.maximumNumberOfTouches = 1
            host.addGestureRecognizer(pan)
            coordinator.panRecognizer = pan
        }

        private func removeInstalledGesture() {
            if let pan = coordinator.panRecognizer {
                gestureHost?.removeGestureRecognizer(pan)
            }
            coordinator.panRecognizer = nil
            gestureHost = nil
        }

        /// Walks up the superview chain to find the SwiftUI container that
        /// holds both the content and this background layer.
        private func findGestureHost() -> UIView? {
            var view: UIView? = self
            for _ in 0..<4 {
                guard let parent = view?.superview else { break }
                view = parent
            }
            return view
        }

        deinit {
            removeInstalledGesture()
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var direction: ReaderDismissGestureDirection
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: (CGFloat, CGFloat) -> Void
        var onDragCancelled: () -> Void
        weak var panRecognizer: UIPanGestureRecognizer?
        private var hasStartedDirectionalDrag = false

        init(
            direction: ReaderDismissGestureDirection,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping (CGFloat, CGFloat) -> Void,
            onDragCancelled: @escaping () -> Void
        ) {
            self.direction = direction
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
            self.onDragCancelled = onDragCancelled
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            let distance = direction.distance(from: translation)

            switch recognizer.state {
            case .changed:
                if !hasStartedDirectionalDrag {
                    guard direction.accepts(translation), distance > 12 else {
                        return
                    }
                    hasStartedDirectionalDrag = true
                }
                onDragChanged(distance)
            case .ended:
                if hasStartedDirectionalDrag {
                    let velocity = recognizer.velocity(in: recognizer.view)
                    onDragEnded(distance, direction.velocity(from: velocity))
                }
                hasStartedDirectionalDrag = false
            case .cancelled, .failed:
                if hasStartedDirectionalDrag {
                    onDragCancelled()
                }
                hasStartedDirectionalDrag = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }

            let velocity = panRecognizer.velocity(in: panRecognizer.view)
            guard direction.accepts(velocity) else {
                return false
            }

            return !shouldDeferToTouchedContent(for: gestureRecognizer)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func shouldDeferToTouchedContent(for gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let host = gestureRecognizer.view else {
                return false
            }

            let location = gestureRecognizer.location(in: host)
            var touchedView = host.hitTest(location, with: nil)

            while let view = touchedView {
                if view is UIControl {
                    return true
                }
                if let scrollView = view as? UIScrollView,
                   direction.shouldDefer(to: scrollView) {
                    return true
                }
                if view === host {
                    break
                }
                touchedView = view.superview
            }

            return false
        }
    }
}
