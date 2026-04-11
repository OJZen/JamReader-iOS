import Foundation

final class LibraryAccessSession {
    let sourceURL: URL

    private let isSecurityScoped: Bool

    init(sourceURL: URL, isSecurityScoped: Bool) {
        self.sourceURL = sourceURL
        self.isSecurityScoped = isSecurityScoped
    }

    deinit {
        if isSecurityScoped {
            sourceURL.stopAccessingSecurityScopedResource()
        }
    }
}
