import SwiftUI
import UIKit

@MainActor
final class HeroSourceRegistry {
    static let shared = HeroSourceRegistry()

    private final class WeakViewBox {
        weak var view: UIView?

        init(view: UIView) {
            self.view = view
        }
    }

    private var viewsByID: [String: WeakViewBox] = [:]

    func register(view: UIView, for id: String) {
        viewsByID[id] = WeakViewBox(view: view)
    }

    func unregister(view: UIView, for id: String) {
        guard let registeredView = viewsByID[id]?.view, registeredView === view else {
            return
        }

        viewsByID[id] = nil
    }

    func frame(for id: String) -> CGRect {
        guard let view = viewsByID[id]?.view, view.window != nil else {
            viewsByID[id] = nil
            return .zero
        }

        return view.convert(view.bounds, to: nil)
    }
}

/// Holds a weak reference to a UIView so we can query its current frame in
/// window coordinates at any time — including during scroll, when SwiftUI's
/// GeometryReader does NOT update.
final class FrameAnchor {
    weak var view: UIView?

    /// The view's current frame in window (screen) coordinates, or .zero if
    /// the view is not in a window.
    var windowFrame: CGRect {
        guard let view, view.window != nil else { return .zero }
        return view.convert(view.bounds, to: nil)
    }
}

@MainActor
struct HeroSourceAnchorView: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = id
        HeroSourceRegistry.shared.register(view: view, for: id)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = id
        HeroSourceRegistry.shared.register(view: uiView, for: id)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        HeroSourceRegistry.shared.unregister(view: uiView, for: uiView.accessibilityIdentifier ?? "")
    }
}

/// A Button-like view that reports its current frame in window coordinates to
/// the action closure at the exact moment of the tap — reliably even when
/// inside a ScrollView.
///
/// ```swift
/// HeroTapButton { frame in
///     heroSourceFrame = frame
///     presentedComic = ...
/// } label: {
///     LibraryComicCard(...)
/// }
/// ```
struct HeroTapButton<Label: View>: View {
    let action: (CGRect) -> Void
    @ViewBuilder let label: () -> Label

    @State private var anchor = FrameAnchor()

    var body: some View {
        Button {
            action(anchor.windowFrame)
        } label: {
            label()
        }
        .background(_FrameAnchorView(anchor: anchor))
    }
}

// MARK: - UIKit anchor view

private struct _FrameAnchorView: UIViewRepresentable {
    let anchor: FrameAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the anchor updated in case SwiftUI reuses the UIView instance.
        anchor.view = uiView
    }
}
