import Combine
import Foundation
import Network

/// Whether the device has a network path, for screens that hide actions
/// which would certainly fail offline. It cannot tell if a server is reachable.
@MainActor
final class NetworkStatusMonitor: ObservableObject {
    static let shared = NetworkStatusMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != isOnline else {
                    return
                }
                self.isOnline = isOnline
            }
        }
        monitor.start(queue: DispatchQueue(label: "JamReader.NetworkStatusMonitor", qos: .utility))
    }
}
