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

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 5)

                VStack(spacing: 8) {
                    Text("Go to Page")
                        .font(.headline)

                    Text("Jump directly to a page without leaving the reader.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    ReaderPageJumpContextChip(
                        title: "Current",
                        value: "\(currentPageNumber)"
                    )

                    ReaderPageJumpContextChip(
                        title: "Range",
                        value: "1-\(pageCount)"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Page Number")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Enter page", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    isPageFieldFocused ? Color.accentColor : Color.black.opacity(0.08),
                                    lineWidth: isPageFieldFocused ? 2 : 1
                                )
                        )
                        .focused($isPageFieldFocused)
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                    Button("Jump", action: onJump)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!isValidPageNumber)
                }
            }
            .padding(22)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 26, y: 14)
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

private struct ReaderPageJumpContextChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
