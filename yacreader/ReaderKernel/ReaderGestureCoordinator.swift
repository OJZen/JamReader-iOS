import SwiftUI

/// Centralized gesture-to-command dispatcher for the reader.
/// Eliminates duplicated tap handling between local and remote reader views.
enum ReaderGestureCoordinator {
    /// Dispatch a tap region event through the routing configuration to the session.
    @MainActor
    static func handleTap(
        _ region: ReaderTapRegion,
        session: ReaderSessionController,
        configuration: ReaderTapRoutingConfiguration,
        onLeadingEdge: (() -> Void)? = nil,
        onTrailingEdge: (() -> Void)? = nil
    ) {
        let action = ReaderTapRouter.action(
            for: region,
            isChromeVisible: session.state.isChromeVisible,
            configuration: configuration
        )
        dispatchTapAction(action, session: session,
                          onLeadingEdge: onLeadingEdge,
                          onTrailingEdge: onTrailingEdge)
    }

    // MARK: - Chrome

    @MainActor
    static func toggleChrome(session: ReaderSessionController) {
        withAnimation(AppAnimation.chromeToggle) {
            session.apply(.toggleChrome)
        }
    }

    @MainActor
    static func hideChrome(session: ReaderSessionController) {
        guard session.state.isChromeVisible else { return }
        withAnimation(AppAnimation.chromeToggle) {
            session.apply(.hideChrome)
        }
    }

    // MARK: - Private

    @MainActor
    private static func dispatchTapAction(
        _ action: ReaderTapAction,
        session: ReaderSessionController,
        onLeadingEdge: (() -> Void)?,
        onTrailingEdge: (() -> Void)?
    ) {
        switch action {
        case .none:
            break
        case .toggleChrome:
            toggleChrome(session: session)
        case .hideChrome:
            hideChrome(session: session)
        case .invokeLeadingEdgeAction:
            onLeadingEdge?()
        case .invokeTrailingEdgeAction:
            onTrailingEdge?()
        }
    }
}
