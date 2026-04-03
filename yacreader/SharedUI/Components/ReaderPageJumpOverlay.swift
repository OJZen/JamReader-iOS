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
    @State private var sliderPageNumber: Double = 1

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

    private var selectedPageNumber: Int {
        min(max(Int(sliderPageNumber.rounded()), 1), maximumPageCount)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            ReaderPageJumpKeyboardDismissLayer()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Go to Page")
                        .font(AppFont.headline())
                        .foregroundStyle(.primary)

                    Text("Page \(clampedCurrentPage) of \(maximumPageCount)")
                        .font(AppFont.footnote(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                TextField("Page", text: $pageNumberText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(AppFont.title3(.semibold).monospacedDigit())
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .stroke(
                                isPageFieldFocused ? Color.accentColor.opacity(0.5) : Color.black.opacity(0.08),
                                lineWidth: isPageFieldFocused ? 1.5 : 1
                            )
                    )
                    .focused($isPageFieldFocused)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text("Selected")
                            .font(AppFont.footnote(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(selectedPageNumber) / \(maximumPageCount)")
                            .font(AppFont.footnote(.medium).monospacedDigit())
                            .foregroundStyle(.primary)
                    }

                    Slider(
                        value: $sliderPageNumber,
                        in: 1...Double(maximumPageCount),
                        step: 1
                    ) { editing in
                        if editing {
                            isPageFieldFocused = false
                        }
                    }
                    .tint(.accentColor)
                    .onChange(of: sliderPageNumber) { _, newValue in
                        let pageNumber = min(max(Int(newValue.rounded()), 1), maximumPageCount)
                        let updatedText = "\(pageNumber)"
                        guard pageNumberText != updatedText else {
                            return
                        }

                        pageNumberText = updatedText
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                    Button("OK", action: onJump)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!isValidPageNumber)
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
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, Spacing.xl)
            .offset(y: -keyboardLift)
            .overlayTransition(true)
            .onAppear {
                synchronizeSliderSelection(with: pageNumberText)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    isPageFieldFocused = true
                }
            }
            .onChange(of: pageNumberText) { _, newValue in
                synchronizeSliderSelection(with: newValue)
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

    private func synchronizeSliderSelection(with text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmedText), (1...maximumPageCount).contains(pageNumber) else {
            return
        }

        let targetValue = Double(pageNumber)
        guard sliderPageNumber != targetValue else {
            return
        }

        sliderPageNumber = targetValue
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
