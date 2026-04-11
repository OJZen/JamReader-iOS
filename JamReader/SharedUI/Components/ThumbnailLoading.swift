import UIKit

@MainActor
protocol ThumbnailLoading: ObservableObject {
    var image: UIImage? { get }
    func cancel()
}
