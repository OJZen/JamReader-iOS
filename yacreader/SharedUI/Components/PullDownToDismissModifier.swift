import SwiftUI
import UIKit

// MARK: - View Modifier

extension View {
    /// Adds a pull-down-to-dismiss gesture similar to the Photos app.
    /// Only activates when the content is not zoomed in.
    /// - Parameter onDismiss: Called after the exit animation completes.
    ///   Wrap your `dismiss()` call in `withTransaction(Transaction(animation: .none))`
    ///   to prevent the system presentation animation from competing with ours.
    func pullDownToDismiss(
        isEnabled: Bool = true,
        isZoomed: Bool = false,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            PullDownToDismissModifier(
                isEnabled: isEnabled,
                isZoomed: isZoomed,
                onDismiss: onDismiss
            )
        )
    }
}

// MARK: - Modifier

private struct PullDownToDismissModifier: ViewModifier {
    let isEnabled: Bool
    let isZoomed: Bool
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private let dismissThreshold: CGFloat = 120
    private let velocityThreshold: CGFloat = 800

    func body(content: Content) -> some View {
        content
            .offset(y: isEnabled ? dragOffset.height : 0)
            .scaleEffect(isEnabled ? scaleForDrag : 1)
            .background(Color.black.ignoresSafeArea())
            .simultaneousGesture(isEnabled && !isZoomed ? dragGesture : nil)
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: dragOffset)
    }

    private var scaleForDrag: CGFloat {
        let progress = min(abs(dragOffset.height) / 400, 1)
        return 1 - progress * 0.15
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let translation = value.translation

                // Only respond to predominantly vertical downward drags
                guard abs(translation.height) > abs(translation.width) * 1.2 else {
                    return
                }

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
                    dragOffset = CGSize(width: 0, height: UIScreen.main.bounds.height)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                        onDismiss()
                    }
                } else {
                    dragOffset = .zero
                }
            }
    }
}
