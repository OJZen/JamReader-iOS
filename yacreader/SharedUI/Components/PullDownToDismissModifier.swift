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
        .simultaneousGesture(isEnabled && !isZoomed && !isCompletingDismiss ? dragGesture : nil)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let translation = value.translation

                // Only respond to predominantly vertical downward drags
                guard abs(translation.height) > abs(translation.width) * 1.2 else {
                    return
                }

                isCompletingDismiss = false
                isDragging = true
                // Clamp upward drags to zero — no upward offset
                dragOffset = CGSize(
                    width: 0,
                    height: max(translation.height, 0)
                )
            }
            .onEnded { value in
                isDragging = false
                let verticalVelocity = value.predictedEndTranslation.height - value.translation.height

                if dragOffset.height > dismissThreshold || verticalVelocity > velocityThreshold {
                    isCompletingDismiss = true
                    DispatchQueue.main.async {
                        onDismiss()
                    }
                } else {
                    isCompletingDismiss = false
                    dragOffset = .zero
                }
            }
    }
}
