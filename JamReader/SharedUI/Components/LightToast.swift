import SwiftUI

struct LightToast: View {
    let message: String
    let systemImage: String?

    init(message: String, systemImage: String? = nil) {
        self.message = message
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            Text(message)
                .font(AppFont.subheadline(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .appShadow(AppShadow.md)
    }
}

// MARK: - Toast ViewModifier

private struct LightToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let systemImage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    LightToast(message: message, systemImage: systemImage)
                        .padding(.bottom, Spacing.xxl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            dismissTask?.cancel()
                            dismissTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard !Task.isCancelled else { return }
                                withAnimation(AppAnimation.standard) {
                                    isPresented = false
                                }
                            }
                        }
                        .onDisappear {
                            dismissTask?.cancel()
                            dismissTask = nil
                        }
                }
            }
            .animation(AppAnimation.standard, value: isPresented)
    }
}

extension View {
    func lightToast(
        isPresented: Binding<Bool>,
        message: String,
        systemImage: String? = nil
    ) -> some View {
        modifier(
            LightToastModifier(
                isPresented: isPresented,
                message: message,
                systemImage: systemImage
            )
        )
    }
}
