import Foundation

final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated private static let lock = NSLock()

    nonisolated static func setHandler(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            requests = []
        }
    }

    nonisolated static func reset() {
        lock.withLock {
            handler = nil
            requests = []
        }
    }

    nonisolated static func recordedRequests() -> [URLRequest] {
        lock.withLock {
            requests
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestHandler: Handler? = Self.lock.withLock {
            Self.requests.append(request)
            return Self.handler
        }

        guard let requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
