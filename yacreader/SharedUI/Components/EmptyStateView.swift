import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var description: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .font(AppFont.title2())
        } description: {
            if let description {
                Text(description)
                    .font(AppFont.callout())
                    .foregroundStyle(Color.textSecondary)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
