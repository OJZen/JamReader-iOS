import SwiftUI

// MARK: - Chrome Toggle

extension View {
    /// Fades reader chrome (top/bottom bars) in and out with consistent animation.
    func chromeVisibility(_ isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .animation(AppAnimation.chromeToggle, value: isVisible)
            .allowsHitTesting(isVisible)
    }
}

// MARK: - Sheet Transition

extension View {
    /// Applies a slide + fade transition for bottom sheets and overlays.
    func sheetTransition(_ isPresented: Bool, edge: Edge = .bottom) -> some View {
        self
            .transition(.move(edge: edge).combined(with: .opacity))
            .animation(AppAnimation.sheetPresent, value: isPresented)
    }
}

// MARK: - Overlay Pop

extension View {
    /// Scale-and-fade pop transition for contextual overlays (page jump, thumbnails).
    func overlayTransition(_ isVisible: Bool) -> some View {
        self
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
            .animation(AppAnimation.overlayPop, value: isVisible)
    }
}

// MARK: - Skeleton Loading

struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var cornerRadius: CGFloat = CornerRadius.md

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .overlay {
                if !accessibilityReduceMotion {
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.6)
                        .offset(x: shimmerOffset * width)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.2)
                                .repeatForever(autoreverses: false)
                            ) {
                                shimmerOffset = 1.4
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Overlays a shimmer skeleton when loading; reveals content when done.
    func skeleton(isLoading: Bool) -> some View {
        self
            .opacity(isLoading ? 0 : 1)
            .overlay(
                Group {
                    if isLoading {
                        SkeletonView()
                    }
                }
            )
            .animation(AppAnimation.standard, value: isLoading)
    }
}
