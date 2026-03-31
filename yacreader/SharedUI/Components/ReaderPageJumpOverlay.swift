import SwiftUI
import UIKit

struct ReaderPageJumpOverlay: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isPageFieldFocused: Bool
    @State private var keyboardLift: CGFloat = 0

    init(
        pageNumberText: Binding<String>,
        currentPageNumber: Int,
        pageCount: Int,
        onCancel: @escaping () -> Void,
        onJump: @escaping () -> Void
    ) {
        self._pageNumberText = pageNumberText
        self.currentPageNumber = currentPageNumber
        self.pageCount = pageCount
        self.onCancel = onCancel
        self.onJump = onJump
    }

    private var maximumPageCount: Int {
        max(pageCount, 1)
    }

    private var clampedCurrentPage: Int {
        min(max(currentPageNumber, 1), maximumPageCount)
    }

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...maximumPageCount).contains(pageNumber)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()

            ReaderPageJumpKeyboardDismissLayer()
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                HStack {
                    Text("Page \(clampedCurrentPage) of \(maximumPageCount)")
                        .font(AppFont.footnote(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.title3())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: Spacing.sm) {
                    TextField("Go to page\u{2026}", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(AppFont.title3(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 48)
                        .background(
                            Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                                .stroke(
                                    isPageFieldFocused ? Color.white.opacity(0.8) : Color.white.opacity(0.15),
                                    lineWidth: isPageFieldFocused ? 1.5 : 1
                                )
                        )
                        .focused($isPageFieldFocused)

                    Button("Go", action: onJump)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.9))
                        .foregroundStyle(.black)
                        .controlSize(.large)
                        .disabled(!isValidPageNumber)
                        .frame(height: 48)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, Spacing.xl)
            .offset(y: -keyboardLift)
            .overlayTransition(true)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    isPageFieldFocused = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardLift(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardLift(from: notification)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func updateKeyboardLift(from notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        // Use window height for iPad multitasking (UIScreen.main.bounds is full screen)
        let windowHeight: CGFloat = {
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
               let window = windowScene.windows.first(where: \.isKeyWindow) {
                return window.bounds.height
            }
            return UIScreen.main.bounds.height
        }()
        let overlap = max(0, windowHeight - endFrame.minY)
        // Re-center the dialog in the available space above the keyboard.
        let targetLift = overlap > 0 ? overlap * 0.5 : 0
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25

        withAnimation(.easeOut(duration: duration)) {
            keyboardLift = targetLift
        }
    }
}

private struct ReaderPageJumpKeyboardDismissLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> ReaderKeyboardDismissView {
        let view = ReaderKeyboardDismissView()
        view.onBackgroundTap = {
            view.endEditing(true)
        }
        return view
    }

    func updateUIView(_ uiView: ReaderKeyboardDismissView, context: Context) {}
}

final class ReaderKeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    var onBackgroundTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleBackgroundTap() {
        onBackgroundTap?()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else {
            return true
        }

        var currentView: UIView? = touchedView
        while let view = currentView {
            if view is UIControl {
                return false
            }

            currentView = view.superview
        }

        return true
    }
}
