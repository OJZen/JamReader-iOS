import SwiftUI
import UIKit

// MARK: - View Modifier

extension View {
    /// Adds a pull-down-to-dismiss gesture similar to the Photos app.
    /// Only activates when the content is not zoomed in.
    /// - Parameter onDismissGestureActiveChanged: Called when the dismiss drag starts/ends.
    ///   Use this to temporarily disable conflicting gestures (e.g. horizontal paging).
    /// - Parameter onDismiss: Called when the custom dismiss transition should
    ///   take over and finish the close animation.
    ///   Wrap your `dismiss()` call in `withTransaction(Transaction(animation: .none))`
    ///   to prevent the system presentation animation from competing with ours.
    func pullDownToDismiss(
        isEnabled: Bool = true,
        isZoomed: Bool = false,
        onDismissGestureActiveChanged: ((Bool) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            PullDownToDismissModifier(
                isEnabled: isEnabled,
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
    let isZoomed: Bool
    let onDismissGestureActiveChanged: ((Bool) -> Void)?
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero
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
        .offset(y: isEnabled ? dragOffset.height : 0)
        .scaleEffect(isEnabled ? scaleForDrag : 1)
        .background {
            PullDownGestureLayer(
                isEnabled: isEnabled && !isZoomed && !isCompletingDismiss,
                onDragChanged: handleDragChanged,
                onDragEnded: handleDragEnded,
                onDragCancelled: handleDragCancelled
            )
        }
        .animation(isDragging || isCompletingDismiss ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
        .onChange(of: dismissGestureState) { _, newValue in
            onDismissGestureActiveChanged?(newValue)
        }
    }

    private var contentOpacity: Double {
        guard dragOffset.height > 0 else { return 1.0 }
        let progress = min(dragOffset.height / 350, 1.0)
        return max(0, 1.0 - progress)
    }

    private var scaleForDrag: CGFloat {
        let progress = min(abs(dragOffset.height) / 400, 1)
        return 1 - progress * 0.15
    }

    private var dismissGestureState: Bool {
        isDragging || isCompletingDismiss
    }

    private func handleDragChanged(_ height: CGFloat) {
        isCompletingDismiss = false
        isDragging = true
        dragOffset = CGSize(width: 0, height: height)
    }

    private func handleDragEnded(_ height: CGFloat, _ velocity: CGFloat) {
        isDragging = false
        dragOffset = CGSize(width: 0, height: height)

        if height > dismissThreshold || velocity > velocityThreshold {
            isCompletingDismiss = true
            DispatchQueue.main.async {
                onDismiss()
            }
        } else {
            isCompletingDismiss = false
            dragOffset = .zero
        }
    }

    private func handleDragCancelled() {
        isDragging = false
        isCompletingDismiss = false
        dragOffset = .zero
    }
}

// MARK: - UIKit Gesture Layer (replaces SwiftUI DragGesture for CI compliance)

/// Installs a UIPanGestureRecognizer on a suitable ancestor view to detect
/// vertical pull-down drags. Allows simultaneous recognition with all other gestures.
private struct PullDownGestureLayer: UIViewRepresentable {
    let isEnabled: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat) -> Void
    let onDragCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            onDragCancelled: onDragCancelled
        )
    }

    func makeUIView(context: Context) -> GestureInstallerView {
        GestureInstallerView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: GestureInstallerView, context: Context) {
        context.coordinator.panRecognizer?.isEnabled = isEnabled
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.onDragCancelled = onDragCancelled
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
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: (CGFloat, CGFloat) -> Void
        var onDragCancelled: () -> Void
        weak var panRecognizer: UIPanGestureRecognizer?
        private var hasStartedVerticalDrag = false

        init(
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping (CGFloat, CGFloat) -> Void,
            onDragCancelled: @escaping () -> Void
        ) {
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
            self.onDragCancelled = onDragCancelled
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)

            switch recognizer.state {
            case .changed:
                if !hasStartedVerticalDrag {
                    // Only activate for predominantly vertical downward drags
                    guard abs(translation.y) > abs(translation.x) * 1.2,
                          translation.y > 12 else {
                        return
                    }
                    hasStartedVerticalDrag = true
                }
                onDragChanged(max(translation.y, 0))
            case .ended:
                if hasStartedVerticalDrag {
                    let velocity = recognizer.velocity(in: recognizer.view)
                    onDragEnded(max(translation.y, 0), velocity.y)
                }
                hasStartedVerticalDrag = false
            case .cancelled, .failed:
                if hasStartedVerticalDrag {
                    onDragCancelled()
                }
                hasStartedVerticalDrag = false
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
