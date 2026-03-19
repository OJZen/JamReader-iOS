import SwiftUI

struct ReaderPageJumpOverlay: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isPageFieldFocused: Bool

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...pageCount).contains(pageNumber)
    }

    private var clampedCurrentPage: Int {
        min(max(currentPageNumber, 1), max(pageCount, 1))
    }

    private var progressValue: Double {
        guard pageCount > 0 else {
            return 0
        }

        return Double(clampedCurrentPage) / Double(pageCount)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
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

                        Text("Jump without leaving the page.")
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

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Progress")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.8))

                        Spacer()

                        Text("Page \(clampedCurrentPage) / \(max(pageCount, 1))")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    ProgressView(value: progressValue)
                        .tint(.white)
                        .progressViewStyle(.linear)

                    Text("\(Int((progressValue * 100).rounded()))% complete")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                HStack(spacing: 10) {
                    TextField("Page", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isPageFieldFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.16),
                                    lineWidth: isPageFieldFocused ? 1.5 : 1
                                )
                        )
                        .focused($isPageFieldFocused)

                    Button("Jump", action: onJump)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.92))
                        .foregroundStyle(.black)
                        .controlSize(.large)
                        .disabled(!isValidPageNumber)
                }

                Text("Valid range: 1-\(pageCount)")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(20)
            .frame(maxWidth: 332)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        isPageFieldFocused = false
                    }
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    isPageFieldFocused = true
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
