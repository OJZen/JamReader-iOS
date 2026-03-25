import SwiftUI
import UIKit

struct ThumbnailView<Loader: ThumbnailLoading>: View {
    @Environment(\.displayScale) private var displayScale

    let placeholderSystemName: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let contentID: String
    let loadAction: (Loader, CGSize, CGFloat) -> Void

    @StateObject private var loader: Loader

    init(
        loader: @autoclosure @escaping () -> Loader,
        placeholderSystemName: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        contentID: String,
        loadAction: @escaping (Loader, CGSize, CGFloat) -> Void
    ) {
        _loader = StateObject(wrappedValue: loader())
        self.placeholderSystemName = placeholderSystemName
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentID = contentID
        self.loadAction = loadAction
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSystemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .task(id: requestID) {
            loadAction(loader, CGSize(width: width, height: height), displayScale)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var requestID: String {
        "\(contentID)#\(Int(width))x\(Int(height))@\(Int(displayScale * 100))"
    }
}
