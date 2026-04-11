import Combine
import SwiftUI
import UIKit
import WebKit

struct EPUBReaderContainerView: View {
    let document: EBookComicDocument
    let onReaderTap: (ReaderTapRegion) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var stateModel = EPUBReaderContainerStateModel()

    var body: some View {
        Group {
            switch stateModel.phase {
            case .idle, .loading:
                ReaderFallbackStateView(
                    title: "Opening EPUB",
                    systemImage: nil,
                    message: "Preparing the book for the new reader.",
                    showsProgress: true
                )
            case .ready(let preparedDocument, let initialLocation):
                EPUBWebReaderView(
                    preparedDocument: preparedDocument,
                    initialLocation: initialLocation,
                    colorScheme: colorScheme,
                    onReaderTap: onReaderTap,
                    onLocationChanged: { location in
                        EPUBReadingLocationStore.shared.saveLocation(location, for: document)
                    },
                    onLoadFailed: { message in
                        stateModel.fail(with: message)
                    }
                )
            case .failed(let message):
                ReaderFallbackStateView(
                    title: "Failed to Open EPUB",
                    systemImage: "exclamationmark.triangle",
                    message: message
                )
            }
        }
        .task(id: document.documentID) {
            stateModel.prepare(document: document)
        }
        .onDisappear {
            stateModel.cancel()
        }
    }
}

@MainActor
private final class EPUBReaderContainerStateModel: ObservableObject {
    enum Phase {
        case idle
        case loading
        case ready(EPUBPreparedDocument, initialLocation: String?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var prepareTask: Task<Void, Never>?
    private var currentDocumentID: String?

    func prepare(document: EBookComicDocument) {
        guard currentDocumentID != document.documentID || !isReady else {
            return
        }

        cancel()
        currentDocumentID = document.documentID
        phase = .loading

        prepareTask = Task { [document] in
            do {
                let preparedDocument = try await EPUBDocumentPreparationService.shared.prepare(document: document)
                guard !Task.isCancelled else {
                    return
                }

                let initialLocation = EPUBReadingLocationStore.shared.location(for: document)
                await MainActor.run {
                    self.phase = .ready(preparedDocument, initialLocation: initialLocation)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        prepareTask?.cancel()
        prepareTask = nil
    }

    func fail(with message: String) {
        phase = .failed(message)
    }

    private var isReady: Bool {
        if case .ready = phase {
            return true
        }
        return false
    }
}

private struct EPUBWebReaderView: UIViewRepresentable {
    let preparedDocument: EPUBPreparedDocument
    let initialLocation: String?
    let colorScheme: ColorScheme
    let onReaderTap: (ReaderTapRegion) -> Void
    let onLocationChanged: (String?) -> Void
    let onLoadFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReaderTap: onReaderTap,
            onLocationChanged: onLocationChanged,
            onLoadFailed: onLoadFailed
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(context.coordinator, name: Coordinator.locationChangedMessageName)
        controller.add(context.coordinator, name: Coordinator.errorMessageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        context.coordinator.load(
            preparedDocument: preparedDocument,
            initialLocation: initialLocation,
            colorScheme: colorScheme
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onReaderTap = onReaderTap
        context.coordinator.onLocationChanged = onLocationChanged
        context.coordinator.onLoadFailed = onLoadFailed
        context.coordinator.load(
            preparedDocument: preparedDocument,
            initialLocation: initialLocation,
            colorScheme: colorScheme
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.locationChangedMessageName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.errorMessageName
        )
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate {
        static let locationChangedMessageName = "epubLocationChanged"
        static let errorMessageName = "epubReaderError"
        private static let updateThemeFunction = "__yacreaderUpdateTheme"

        var onReaderTap: (ReaderTapRegion) -> Void
        var onLocationChanged: (String?) -> Void
        var onLoadFailed: (String) -> Void

        private weak var webView: WKWebView?
        private var currentLoadKey: String?
        private var desiredTheme: String?
        private var appliedTheme: String?
        private var latestLocation: String?

        init(
            onReaderTap: @escaping (ReaderTapRegion) -> Void,
            onLocationChanged: @escaping (String?) -> Void,
            onLoadFailed: @escaping (String) -> Void
        ) {
            self.onReaderTap = onReaderTap
            self.onLocationChanged = onLocationChanged
            self.onLoadFailed = onLoadFailed
        }

        func attach(to webView: WKWebView) {
            self.webView = webView

            let tapGestureRecognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handleTap(_:))
            )
            tapGestureRecognizer.cancelsTouchesInView = false
            tapGestureRecognizer.delegate = self
            webView.addGestureRecognizer(tapGestureRecognizer)
        }

        func load(
            preparedDocument: EPUBPreparedDocument,
            initialLocation: String?,
            colorScheme: ColorScheme
        ) {
            guard let webView else {
                return
            }

            let theme = colorScheme == .dark ? "dark" : "light"
            let loadKey = [
                preparedDocument.documentID,
                preparedDocument.readerHTMLURL.path,
                preparedDocument.packageRelativePath
            ].joined(separator: "|")

            desiredTheme = theme

            if currentLoadKey == loadKey {
                updateThemeIfNeeded(theme, in: webView)
                return
            }

            let requestURL = requestURL(
                for: preparedDocument,
                initialLocation: initialLocation,
                theme: theme
            )

            currentLoadKey = loadKey
            appliedTheme = nil
            latestLocation = initialLocation
            webView.loadFileURL(requestURL, allowingReadAccessTo: preparedDocument.readAccessRootURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.locationChangedMessageName:
                if let location = message.body as? String {
                    latestLocation = location
                    onLocationChanged(location)
                } else {
                    latestLocation = nil
                    onLocationChanged(nil)
                }
            case Self.errorMessageName:
                if let errorMessage = message.body as? String, !errorMessage.isEmpty {
                    onLoadFailed(errorMessage)
                } else {
                    onLoadFailed("The EPUB reader could not render this book.")
                }
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.isFileURL {
                decisionHandler(.allow)
                return
            }

            if let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            _ = navigation

            if let desiredTheme {
                updateThemeIfNeeded(desiredTheme, in: webView)
            }
        }

        @objc
        private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended else {
                return
            }

            onReaderTap(.center)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func requestURL(
            for preparedDocument: EPUBPreparedDocument,
            initialLocation: String?,
            theme: String
        ) -> URL {
            var components = URLComponents(url: preparedDocument.readerHTMLURL, resolvingAgainstBaseURL: false)
            let effectiveLocation = latestLocation ?? initialLocation
            var queryItems = [
                URLQueryItem(name: "opf", value: preparedDocument.packageRelativePath),
                URLQueryItem(name: "theme", value: theme)
            ]
            if let effectiveLocation, !effectiveLocation.isEmpty {
                queryItems.append(URLQueryItem(name: "loc", value: effectiveLocation))
            }
            components?.queryItems = queryItems
            return components?.url ?? preparedDocument.readerHTMLURL
        }

        private func updateThemeIfNeeded(_ theme: String, in webView: WKWebView) {
            desiredTheme = theme

            guard appliedTheme != theme else {
                return
            }

            let escapedTheme = theme.replacingOccurrences(of: "'", with: "\\'")
            let script = "window.\(Self.updateThemeFunction)?.('\(escapedTheme)');"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error == nil else {
                    return
                }

                self?.appliedTheme = theme
            }
        }
    }
}
