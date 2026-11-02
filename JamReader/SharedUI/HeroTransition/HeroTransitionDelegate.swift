import UIKit

/// Opens and closes the reader around one flying copy of the comic,
/// `ReaderHeroView`: the cover on the way in, the current page on the way out.
/// Everything else only fades behind it, so the black of the reader never
/// moves on screen as a card and the comic never shows twice.
@MainActor
final class HeroTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    private let context: ReaderHeroContext

    init(context: ReaderHeroContext) {
        self.context = context
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroPresentTransition(context: context)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroDismissTransition(context: context)
    }

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        ReaderFullscreenPresentationController(
            presentedViewController: presented,
            presenting: presenting ?? source
        )
    }
}

private final class ReaderFullscreenPresentationController: UIPresentationController {
    override var frameOfPresentedViewInContainerView: CGRect {
        containerView?.bounds ?? .zero
    }

    override var shouldPresentInFullscreen: Bool {
        true
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        applyFullscreenFrame()
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        applyFullscreenFrame()
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        applyFullscreenFrame()
    }

    private func applyFullscreenFrame() {
        guard let presentedView else {
            return
        }

        presentedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        presentedView.frame = frameOfPresentedViewInContainerView
    }
}

private enum HeroTransitionTiming {
    static let flight: TimeInterval = 0.42
    /// The cover dissolving into the reader once it has landed.
    static let handoff: TimeInterval = 0.16
    /// No flight: without a source, or with Reduce Motion.
    static let fade: TimeInterval = 0.22
    /// The reader's black clears well before the page lands.
    static let backdropClear: TimeInterval = 0.18
    /// SwiftUI brings a cover back in its next update, one or two frames later.
    static let sourceReveal: TimeInterval = 0.05
}

// MARK: - Open transition

@MainActor
private final class HeroPresentTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let context: ReaderHeroContext

    init(context: ReaderHeroContext) {
        self.context = context
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        HeroTransitionTiming.flight + HeroTransitionTiming.handoff
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard
            let toVC = ctx.viewController(forKey: .to),
            let toView = ctx.view(forKey: .to)
        else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        let finalFrame = ctx.finalFrame(for: toVC)
        toView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        toView.frame = finalFrame
        toView.alpha = 0
        container.addSubview(toView)

        guard !UIAccessibility.isReduceMotionEnabled,
              let cover = context.coverImage,
              let startFrame = context.openingFrame(in: container) else {
            UIView.animate(
                withDuration: HeroTransitionTiming.fade,
                delay: 0,
                options: [.curveEaseOut]
            ) {
                toView.alpha = 1
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            return
        }

        let backdropView = UIView(frame: finalFrame)
        backdropView.backgroundColor = .black
        backdropView.alpha = 0
        container.insertSubview(backdropView, belowSubview: toView)

        let heroView = ReaderHeroView(cover: cover)
        heroView.frame = startFrame
        heroView.layer.cornerRadius = context.sourceCornerRadius
        container.addSubview(heroView)
        heroView.layoutIfNeeded()
        context.hideSource()

        let landingFrame = context.landingFrame(in: finalFrame)
        let animator = UIViewPropertyAnimator(
            duration: HeroTransitionTiming.flight,
            dampingRatio: 1
        ) {
            backdropView.alpha = 1
            heroView.frame = landingFrame
            heroView.layoutIfNeeded()
            heroView.layer.cornerRadius = 0
        }
        animator.addCompletion { _ in
            // The reader draws this same cover here, or already the page.
            toView.alpha = 1
            backdropView.removeFromSuperview()
            HeroSourceRegistry.shared.hideSource(nil)

            UIView.animate(
                withDuration: HeroTransitionTiming.handoff,
                delay: 0,
                options: [.curveEaseOut]
            ) {
                heroView.alpha = 0
            } completion: { _ in
                heroView.removeFromSuperview()
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
        animator.startAnimation()
    }
}

// MARK: - Close transition

@MainActor
private final class HeroDismissTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private static let coverFadeDelayFactor: CGFloat = 0.3
    private static let lostSourceScale: CGFloat = 0.92

    private let context: ReaderHeroContext

    init(context: ReaderHeroContext) {
        self.context = context
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        HeroTransitionTiming.flight
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        if let toVC = ctx.viewController(forKey: .to),
           let toView = ctx.view(forKey: .to),
           toView.superview == nil {
            toView.frame = ctx.finalFrame(for: toVC)
            container.insertSubview(toView, belowSubview: fromView)
        }

        let reducesMotion = UIAccessibility.isReduceMotionEnabled
        let heroView = context.takeDragHero()
            ?? (reducesMotion ? nil : context.makeHero(from: fromView, in: container))
        let targetFrame = reducesMotion
            ? nil
            : context.closingFrame.map { container.convert($0, from: nil) }

        guard let heroView, let targetFrame else {
            fadeOut(fromView, heroView: heroView, reducesMotion: reducesMotion, using: ctx)
            return
        }

        context.hideSource()
        let cornerRadius = context.sourceCornerRadius
        let animator = UIViewPropertyAnimator(
            duration: HeroTransitionTiming.flight,
            dampingRatio: 1
        ) {
            heroView.frame = targetFrame
            heroView.layoutIfNeeded()
            heroView.layer.cornerRadius = cornerRadius
        }
        animator.addAnimations({
            heroView.showsCover = true
        }, delayFactor: Self.coverFadeDelayFactor)
        UIView.animate(
            withDuration: HeroTransitionTiming.backdropClear,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            fromView.alpha = 0
        }
        animator.addCompletion { _ in
            HeroSourceRegistry.shared.hideSource(nil)
            // The copy flies above the tab bar; a cover partly under it has to
            // come back smoothly, not with the bar popping in on top.
            UIView.animate(
                withDuration: HeroTransitionTiming.handoff,
                delay: HeroTransitionTiming.sourceReveal,
                options: [.curveEaseOut]
            ) {
                heroView.alpha = 0
            } completion: { _ in
                heroView.removeFromSuperview()
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
        animator.startAnimation()
    }

    /// The cover scrolled away, or the reader is on another comic by now.
    private func fadeOut(
        _ fromView: UIView,
        heroView: ReaderHeroView?,
        reducesMotion: Bool,
        using ctx: UIViewControllerContextTransitioning
    ) {
        UIView.animate(
            withDuration: HeroTransitionTiming.fade,
            delay: 0,
            options: [.curveEaseOut]
        ) {
            fromView.alpha = 0
            heroView?.alpha = 0
            if !reducesMotion {
                heroView?.transform = CGAffineTransform(
                    scaleX: Self.lostSourceScale,
                    y: Self.lostSourceScale
                )
            }
        } completion: { _ in
            heroView?.removeFromSuperview()
            HeroSourceRegistry.shared.hideSource(nil)
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }
}
