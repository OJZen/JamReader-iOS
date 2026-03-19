import SwiftUI
import UIKit

struct ReaderPageJumpOverlay: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isPageFieldFocused: Bool
    @State private var selectedPageNumber: Double
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

        let normalizedMaximum = max(pageCount, 1)
        let initialSelection = Int(pageNumberText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? currentPageNumber
        _selectedPageNumber = State(initialValue: Double(min(max(initialSelection, 1), normalizedMaximum)))
    }

    private var maximumPageCount: Int {
        max(pageCount, 1)
    }

    private var clampedCurrentPage: Int {
        min(max(currentPageNumber, 1), maximumPageCount)
    }

    private var clampedSelectedPage: Int {
        min(max(Int(selectedPageNumber.rounded()), 1), maximumPageCount)
    }

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...maximumPageCount).contains(pageNumber)
    }

    private var progressValue: Double {
        Double(clampedSelectedPage) / Double(maximumPageCount)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .ignoresSafeArea()

            ReaderPageJumpKeyboardDismissLayer()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))

                        Image(systemName: "book.pages")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Go to Page")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Pick a page and keep reading.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.78))
                    }

                    Spacer(minLength: 0)

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Selected")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.8))

                        Spacer()

                        Text("Page \(clampedSelectedPage) of \(maximumPageCount)")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Slider(
                        value: $selectedPageNumber,
                        in: 1...Double(maximumPageCount),
                        step: 1
                    )
                    .tint(.white)

                    HStack {
                        Text("1")
                        Spacer()
                        Text("\(maximumPageCount)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.72))

                    Text("\(Int((progressValue * 100).rounded()))% complete")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Page Number")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.72))

                        TextField("Page", text: $pageNumberText)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        isPageFieldFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.16),
                                        lineWidth: isPageFieldFocused ? 1.5 : 1
                                    )
                            )
                            .focused($isPageFieldFocused)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Jump", action: onJump)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.92))
                        .foregroundStyle(.black)
                        .controlSize(.large)
                        .disabled(!isValidPageNumber)
                        .frame(height: 46)
                }

                HStack(spacing: 10) {
                    ReaderPageJumpMetaChip(
                        systemImage: "location",
                        text: "Current \(clampedCurrentPage)"
                    )

                    ReaderPageJumpMetaChip(
                        systemImage: "arrow.left.and.right",
                        text: "Range 1-\(maximumPageCount)"
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: 332)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
            .padding(.horizontal, 24)
            .offset(y: -keyboardLift)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    isPageFieldFocused = true
                }
            }
            .onChange(of: selectedPageNumber) { _, _ in
                pageNumberText = "\(clampedSelectedPage)"
            }
            .onChange(of: pageNumberText) { _, _ in
                synchronizeSelectionFromText()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardLift(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardLift(from: notification)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func synchronizeSelectionFromText() {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...maximumPageCount).contains(pageNumber)
        else {
            return
        }

        let normalizedSelection = Double(pageNumber)
        guard abs(selectedPageNumber - normalizedSelection) > 0.001 else {
            return
        }

        selectedPageNumber = normalizedSelection
    }

    private func updateKeyboardLift(from notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - endFrame.minY)
        let targetLift = overlap > 0 ? min(140, overlap * 0.36) : 0
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25

        withAnimation(.easeOut(duration: duration)) {
            keyboardLift = targetLift
        }
    }
}

private struct ReaderPageJumpMetaChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))

            Text(text)
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(Color.white.opacity(0.76))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1), in: Capsule())
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
