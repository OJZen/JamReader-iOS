import SwiftUI

struct ReaderPageJumpOverlay: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isFocused: Bool

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...pageCount).contains(pageNumber)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.38))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    HStack {
                        Button("Cancel", action: onCancel)
                            .font(.body)

                        Spacer(minLength: 12)

                        Text("Go to Page")
                            .font(.headline)

                        Spacer(minLength: 12)

                        Button("Jump", action: onJump)
                            .font(.body.weight(.semibold))
                            .disabled(!isValidPageNumber)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                    Divider()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Page")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("Page number", text: $pageNumberText)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .font(.system(size: 34, weight: .semibold, design: .default))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current page: \(currentPageNumber)")
                            Text("Valid range: 1-\(pageCount)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(uiColor: .systemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
