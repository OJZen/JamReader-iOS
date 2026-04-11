import SwiftUI

struct LoadingStateView: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()

            if let message {
                Text(message)
                    .font(AppFont.callout())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
