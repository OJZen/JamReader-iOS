import SwiftUI
import UIKit

@MainActor
@Observable
final class HeroSourceRegistry {
    static let shared = HeroSourceRegistry()

    private final class WeakViewBox {
        weak var view: UIView?
        /// The cover of a UIKit cell; SwiftUI covers use `HeroSourceCoverModifier`.
        weak var coverView: UIView?

        init(view: UIView, coverView: UIView?) {
            self.view = view
            self.coverView = coverView
        }
    }

    @ObservationIgnored private var viewsByID: [String: WeakViewBox] = [:]

    /// The cover a flying copy stands in for, hidden so it doesn't show twice.
    private(set) var hiddenSourceID: String?

    func register(view: UIView, for id: String, coverView: UIView? = nil) {
        viewsByID[id] = WeakViewBox(view: view, coverView: coverView)
        coverView?.alpha = id == hiddenSourceID ? 0 : 1
    }

    func unregister(view: UIView, for id: String) {
        guard let box = viewsByID[id], box.view === view else {
            return
        }

        box.coverView?.alpha = 1
        viewsByID[id] = nil
    }

    func frame(for id: String) -> CGRect {
        guard let view = viewsByID[id]?.view, view.window != nil else {
            viewsByID[id]?.coverView?.alpha = 1
            viewsByID[id] = nil
            return .zero
        }

        return HeroSourceFrameSanitizer.windowFrame(for: view)
    }

    func cornerRadius(for id: String) -> CGFloat {
        viewsByID[id]?.coverView?.layer.cornerRadius ?? CornerRadius.thumbnail
    }

    /// Hides one source and brings back the previous one. Pass nil to hide none.
    func hideSource(_ id: String?) {
        guard hiddenSourceID != id else {
            return
        }

        if let hiddenSourceID {
            viewsByID[hiddenSourceID]?.coverView?.alpha = 1
        }
        hiddenSourceID = id
        if let id {
            viewsByID[id]?.coverView?.alpha = 0
        }
    }
}

/// Marks a SwiftUI cover as the place the reader opens from and closes back to.
struct HeroSourceCoverModifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        content
            .opacity(id != nil && HeroSourceRegistry.shared.hiddenSourceID == id ? 0 : 1)
            .overlay {
                if let id {
                    HeroSourceAnchorView(id: id)
                        .allowsHitTesting(false)
                }
            }
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
        guard let view else { return .zero }
        return HeroSourceFrameSanitizer.windowFrame(for: view)
    }
}

enum HeroSourceFrameSanitizer {
    static func windowFrame(for view: UIView) -> CGRect {
        guard let window = view.window else {
            return .zero
        }

        window.layoutIfNeeded()
        view.superview?.layoutIfNeeded()
        view.layoutIfNeeded()

        let frame = view.convert(view.bounds, to: nil)
        return sanitized(frame, in: window.bounds)
    }

    static func sanitized(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        guard frame.isFiniteHeroFrame, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        // After scene restore UIKit can briefly report a view-sized frame at
        // the window origin before SwiftUI has committed the real placement.
        // Treat that as missing data instead of animating from the top-left.
        if abs(frame.minX) < 0.5, abs(frame.minY) < 0.5 {
            return .zero
        }

        let tolerantBounds = bounds.insetBy(dx: -2, dy: -2)
        let intersection = frame.intersection(tolerantBounds)
        guard !intersection.isNull,
              intersection.width > 2,
              intersection.height > 2 else {
            return .zero
        }

        return frame
    }
}

extension CGRect {
    var isFiniteHeroFrame: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && width.isFinite
            && height.isFinite
            && width > 2
            && height > 2
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
