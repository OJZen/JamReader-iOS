import SwiftUI

struct LibraryImportProgressView: View {
    let progress: ImportedComicsImportProgress?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            progressIndicator

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(progress?.title ?? String(localized: "Preparing Import"))
                    .font(AppFont.footnote(.semibold))

                if let detailLine = progress?.detailLine {
                    Text(detailLine)
                        .font(AppFont.caption())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel", role: .cancel, action: onCancel)
                .font(AppFont.footnote(.semibold))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let fractionCompleted = progress?.fractionCompleted {
            ProgressView(value: fractionCompleted)
                .progressViewStyle(.circular)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}
