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

            VStack {
                Spacer(minLength: 96)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Go to Page")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        Button("Cancel", action: onCancel)
                            .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Page")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("Page number", text: $pageNumberText)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )

                        Text("Current page: \(currentPageNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Valid range: 1-\(pageCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: onJump) {
                        Text("Jump")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidPageNumber)
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
