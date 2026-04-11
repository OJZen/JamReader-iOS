import Foundation

enum ReaderTapRegion {
    case leading
    case center
    case trailing
}

enum ReaderTapAction: Equatable {
    case none
    case toggleChrome
    case hideChrome
    case invokeLeadingEdgeAction
    case invokeTrailingEdgeAction
}

struct ReaderTapRoutingConfiguration {
    let hiddenLeadingAction: ReaderTapAction
    let hiddenCenterAction: ReaderTapAction
    let hiddenTrailingAction: ReaderTapAction
    let visibleLeadingAction: ReaderTapAction
    let visibleCenterAction: ReaderTapAction
    let visibleTrailingAction: ReaderTapAction

    static func localLibrary(
        canOpenLeadingEdge: Bool,
        canOpenTrailingEdge: Bool
    ) -> ReaderTapRoutingConfiguration {
        ReaderTapRoutingConfiguration(
            hiddenLeadingAction: canOpenLeadingEdge ? .invokeLeadingEdgeAction : .none,
            hiddenCenterAction: .toggleChrome,
            hiddenTrailingAction: canOpenTrailingEdge ? .invokeTrailingEdgeAction : .none,
            visibleLeadingAction: .hideChrome,
            visibleCenterAction: .toggleChrome,
            visibleTrailingAction: .hideChrome
        )
    }

    static let remoteSingleComic = ReaderTapRoutingConfiguration(
        hiddenLeadingAction: .toggleChrome,
        hiddenCenterAction: .toggleChrome,
        hiddenTrailingAction: .toggleChrome,
        visibleLeadingAction: .toggleChrome,
        visibleCenterAction: .toggleChrome,
        visibleTrailingAction: .toggleChrome
    )
}

enum ReaderTapRouter {
    static func action(
        for region: ReaderTapRegion,
        isChromeVisible: Bool,
        configuration: ReaderTapRoutingConfiguration
    ) -> ReaderTapAction {
        switch (isChromeVisible, region) {
        case (false, .leading):
            configuration.hiddenLeadingAction
        case (false, .center):
            configuration.hiddenCenterAction
        case (false, .trailing):
            configuration.hiddenTrailingAction
        case (true, .leading):
            configuration.visibleLeadingAction
        case (true, .center):
            configuration.visibleCenterAction
        case (true, .trailing):
            configuration.visibleTrailingAction
        }
    }
}
