import UIKit

/// UIViewControllerTransitioningDelegate that drives the hero zoom transition
/// when the reader is opened from a comic cell.
///
/// - Present: zooms from the tapped cell rect to full screen.
/// - Dismiss: shrinks the current reader snapshot back into the source rect.
final class HeroTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    var sourceFrame: CGRect
    var previewImage: UIImage?

    init(sourceFrame: CGRect, previewImage: UIImage? = nil) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroPresentTransition(sourceFrame: sourceFrame, previewImage: previewImage)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroDismissTransition(sourceFrame: sourceFrame, previewImage: previewImage)
    }
}

// MARK: - Open transition

private final class HeroPresentTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceFrame: CGRect
    private let previewImage: UIImage?

    init(sourceFrame: CGRect, previewImage: UIImage?) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.45
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
        let startFrame = Self.resolvedSourceFrame(sourceFrame, in: finalFrame)
        let backdropView = UIView(frame: finalFrame)
        backdropView.backgroundColor = .black
        backdropView.alpha = 0

        container.addSubview(backdropView)
        container.addSubview(toView)
        toView.frame = finalFrame
        toView.alpha = 0
        toView.transform = CGAffineTransform(scaleX: 1.015, y: 1.015)

        if let previewImage {
            let previewView = makePreviewView(from: previewImage)
            previewView.frame = startFrame
            previewView.alpha = 1
            previewView.clipsToBounds = true
            previewView.layer.cornerRadius = 14
            container.addSubview(previewView)

            UIView.animate(
                withDuration: transitionDuration(using: ctx),
                delay: 0,
                usingSpringWithDamping: 0.92,
                initialSpringVelocity: 0.08,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                backdropView.alpha = 1
                previewView.frame = finalFrame
                previewView.layer.cornerRadius = 0
                toView.transform = .identity
            }

            UIView.animate(
                withDuration: 0.24,
                delay: 0.10,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                toView.alpha = 1
            }

            UIView.animate(
                withDuration: 0.18,
                delay: 0.20,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                previewView.alpha = 0
            } completion: { _ in
                backdropView.removeFromSuperview()
                previewView.removeFromSuperview()
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            return
        }

        UIView.animate(
            withDuration: transitionDuration(using: ctx),
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.08,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            backdropView.alpha = 1
            toView.alpha = 1
            toView.transform = .identity
        } completion: { _ in
            backdropView.removeFromSuperview()
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }

    private func makePreviewView(from previewImage: UIImage) -> UIView {
        let imageView = UIImageView(image: previewImage)
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .black
        return imageView
    }

    fileprivate static func resolvedSourceFrame(_ sourceFrame: CGRect, in finalFrame: CGRect) -> CGRect {
        guard sourceFrame != .zero else {
            let cx = finalFrame.midX
            let cy = finalFrame.midY
            return CGRect(x: cx - 40, y: cy - 56, width: 80, height: 112)
        }

        return sourceFrame
    }
}

// MARK: - Close transition

private final class HeroDismissTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceFrame: CGRect
    private let previewImage: UIImage?

    init(sourceFrame: CGRect, previewImage: UIImage?) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.36
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        let finalBounds = container.bounds
        let targetFrame = HeroPresentTransition.resolvedSourceFrame(sourceFrame, in: finalBounds)

        if let toVC = ctx.viewController(forKey: .to),
           let toView = ctx.view(forKey: .to),
           toView.superview == nil {
            toView.frame = ctx.finalFrame(for: toVC)
            container.insertSubview(toView, belowSubview: fromView)
        }

        let targetPreviewView = makeTargetPreviewView(frame: targetFrame)
        let animatingView = makeSnapshot(from: fromView)
        animatingView.frame = fromView.frame
        animatingView.clipsToBounds = true
        animatingView.layer.cornerRadius = 0
        let snapshotTargetFrame = targetPreviewView == nil
            ? targetFrame
            : targetFrame.insetBy(dx: -10, dy: -10)

        if let targetPreviewView {
            container.addSubview(targetPreviewView)
        }
        container.addSubview(animatingView)
        fromView.isHidden = true

        UIView.animate(
            withDuration: transitionDuration(using: ctx),
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.08,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            animatingView.frame = snapshotTargetFrame
            animatingView.layer.cornerRadius = 14
            animatingView.alpha = targetPreviewView == nil ? 0.96 : 0.10
        } completion: { _ in
            let completed = !ctx.transitionWasCancelled
            fromView.isHidden = false
            targetPreviewView?.removeFromSuperview()
            animatingView.removeFromSuperview()
            ctx.completeTransition(completed)
        }

        if let targetPreviewView {
            UIView.animate(
                withDuration: 0.22,
                delay: 0.10,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                targetPreviewView.alpha = 1
                targetPreviewView.transform = .identity
            }
        }
    }

    private func makeSnapshot(from view: UIView) -> UIView {
        if let snapshot = view.snapshotView(afterScreenUpdates: false) {
            return snapshot
        }

        let fallback = UIView(frame: view.bounds)
        fallback.backgroundColor = .black
        return fallback
    }

    private func makeTargetPreviewView(frame: CGRect) -> UIView? {
        guard let previewImage else {
            return nil
        }

        let imageView = UIImageView(image: previewImage)
        imageView.frame = frame
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 14
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .black
        return imageView
    }
}
