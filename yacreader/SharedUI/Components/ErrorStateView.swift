import SwiftUI

struct ErrorStateView: View {
    let error: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.title2())
                .foregroundStyle(Color.appDanger)
        } description: {
            Text(error)
                .font(AppFont.callout())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        } actions: {
            if let retryAction {
                Button {
                    retryAction()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
