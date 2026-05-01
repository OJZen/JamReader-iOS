import UIKit

/// UIViewControllerTransitioningDelegate that drives the reader hero transition.
///
/// `coverZoom` is used by file-manager style browsers where a stable thumbnail
/// can grow into the reader. `libraryLift` is used by library collection screens
/// where the source is often a composed SwiftUI card/row, so the animation lifts
/// the cover forward and cross-fades into the reader instead of forcing the same
/// full-screen zoom.
final class HeroTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    var sourceFrame: CGRect
    var previewImage: UIImage?
    var style: ReaderHeroTransitionStyle

    init(
        sourceFrame: CGRect,
        previewImage: UIImage? = nil,
        style: ReaderHeroTransitionStyle = .coverZoom
    ) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
        self.style = style
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroPresentTransition(
            sourceFrame: sourceFrame,
            previewImage: previewImage,
            style: style
        )
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        HeroDismissTransition(
            sourceFrame: sourceFrame,
            previewImage: previewImage,
            style: style
        )
    }
}

// MARK: - Open transition

private final class HeroPresentTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceFrame: CGRect
    private let previewImage: UIImage?
    private let style: ReaderHeroTransitionStyle

    init(
        sourceFrame: CGRect,
        previewImage: UIImage?,
        style: ReaderHeroTransitionStyle
    ) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
        self.style = style
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        if UIAccessibility.isReduceMotionEnabled {
            return 0.20
        }

        switch style {
        case .coverZoom:
            return 0.46
        case .libraryLift:
            return 0.38
        }
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

        if UIAccessibility.isReduceMotionEnabled {
            animateReducedMotion(using: ctx, container: container, toView: toView, finalFrame: finalFrame)
            return
        }

        switch style {
        case .coverZoom:
            animateCoverZoom(using: ctx, container: container, toView: toView, finalFrame: finalFrame)
        case .libraryLift:
            animateLibraryLift(using: ctx, container: container, toView: toView, finalFrame: finalFrame)
        }
    }

    private func animateCoverZoom(
        using ctx: UIViewControllerContextTransitioning,
        container: UIView,
        toView: UIView,
        finalFrame: CGRect
    ) {
        let startFrame = Self.resolvedSourceFrame(sourceFrame, in: finalFrame, container: container)
        let backdropView = Self.makeBackdropView(frame: finalFrame)

        container.addSubview(backdropView)
        container.addSubview(toView)
        toView.frame = finalFrame
        toView.alpha = 0
        toView.transform = CGAffineTransform(scaleX: 1.012, y: 1.012)

        guard let previewImage else {
            let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), dampingRatio: 0.92) {
                backdropView.alpha = 1
                toView.alpha = 1
                toView.transform = .identity
            }
            animator.addCompletion { _ in
                backdropView.removeFromSuperview()
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            animator.startAnimation()
            return
        }

        let previewView = Self.makePreviewView(from: previewImage, cornerRadius: HeroTransitionMetrics.coverCornerRadius)
        previewView.frame = startFrame
        container.addSubview(previewView)

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), dampingRatio: 0.92) {
            backdropView.alpha = 1
            previewView.frame = finalFrame
            previewView.layer.cornerRadius = 0
            toView.transform = .identity
        }
        animator.addAnimations({
            toView.alpha = 1
        }, delayFactor: 0.18)
        animator.addAnimations({
            previewView.alpha = 0
        }, delayFactor: 0.58)
        animator.addCompletion { _ in
            backdropView.removeFromSuperview()
            previewView.removeFromSuperview()
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
        animator.startAnimation()
    }

    private func animateLibraryLift(
        using ctx: UIViewControllerContextTransitioning,
        container: UIView,
        toView: UIView,
        finalFrame: CGRect
    ) {
        let startFrame = Self.resolvedSourceFrame(sourceFrame, in: finalFrame, container: container)
        let backdropView = Self.makeBackdropView(frame: finalFrame)

        container.addSubview(backdropView)
        container.addSubview(toView)
        toView.frame = finalFrame
        toView.alpha = 0
        toView.transform = Self.readerEntryTransform(from: startFrame, in: finalFrame)

        guard let previewImage else {
            let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), dampingRatio: 0.90) {
                backdropView.alpha = 1
                toView.alpha = 1
                toView.transform = .identity
            }
            animator.addCompletion { _ in
                backdropView.removeFromSuperview()
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            animator.startAnimation()
            return
        }

        let previewView = Self.makeFloatingPreviewView(
            from: previewImage,
            cornerRadius: HeroTransitionMetrics.libraryCornerRadius
        )
        previewView.frame = startFrame
        previewView.layer.shadowColor = UIColor.black.cgColor
        previewView.layer.shadowOpacity = 0
        previewView.layer.shadowRadius = 28
        previewView.layer.shadowOffset = CGSize(width: 0, height: 18)
        container.addSubview(previewView)

        let landingFrame = Self.libraryLandingFrame(
            for: previewImage,
            startFrame: startFrame,
            finalFrame: finalFrame
        )

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), dampingRatio: 0.88) {
            backdropView.alpha = 1
            previewView.frame = landingFrame
            previewView.previewCornerRadius = HeroTransitionMetrics.libraryCornerRadius
            previewView.layer.shadowOpacity = 0.32
            previewView.transform = CGAffineTransform(scaleX: 1.018, y: 1.018)
            toView.alpha = 1
            toView.transform = .identity
        }
        animator.addAnimations({
            previewView.alpha = 0
            previewView.transform = CGAffineTransform(scaleX: 1.075, y: 1.075)
        }, delayFactor: 0.56)
        animator.addCompletion { _ in
            backdropView.removeFromSuperview()
            previewView.removeFromSuperview()
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
        animator.startAnimation()
    }

    private func animateReducedMotion(
        using ctx: UIViewControllerContextTransitioning,
        container: UIView,
        toView: UIView,
        finalFrame: CGRect
    ) {
        container.addSubview(toView)
        toView.frame = finalFrame
        toView.alpha = 0

        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, options: [.curveEaseOut]) {
            toView.alpha = 1
        } completion: { _ in
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }

    fileprivate static func makeBackdropView(frame: CGRect) -> UIView {
        let backdropView = UIView(frame: frame)
        backdropView.backgroundColor = .black
        backdropView.alpha = 0
        return backdropView
    }

    fileprivate static func makePreviewView(from previewImage: UIImage, cornerRadius: CGFloat) -> UIImageView {
        let imageView = UIImageView(image: previewImage)
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .black
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = cornerRadius
        return imageView
    }

    private static func makeFloatingPreviewView(
        from previewImage: UIImage,
        cornerRadius: CGFloat
    ) -> HeroFloatingPreviewView {
        HeroFloatingPreviewView(image: previewImage, cornerRadius: cornerRadius)
    }

    fileprivate static func resolvedSourceFrame(
        _ sourceFrame: CGRect,
        in finalFrame: CGRect,
        container: UIView
    ) -> CGRect {
        let convertedFrame = sourceFrame.isUsableHeroFrame
            ? container.convert(sourceFrame, from: nil)
            : .zero

        guard convertedFrame.isUsableHeroFrame else {
            let fallbackSize = CGSize(
                width: min(max(finalFrame.width * 0.22, 80), 150),
                height: min(max(finalFrame.height * 0.18, 112), 220)
            )
            return CGRect(
                x: finalFrame.midX - fallbackSize.width / 2,
                y: finalFrame.midY - fallbackSize.height / 2,
                width: fallbackSize.width,
                height: fallbackSize.height
            )
        }

        return convertedFrame
    }

    private static func readerEntryTransform(from startFrame: CGRect, in finalFrame: CGRect) -> CGAffineTransform {
        let offsetX = (startFrame.midX - finalFrame.midX) * 0.045
        let offsetY = (startFrame.midY - finalFrame.midY) * 0.045
        return CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: 0.988, y: 0.988)
    }

    private static func libraryLandingFrame(
        for image: UIImage,
        startFrame: CGRect,
        finalFrame: CGRect
    ) -> CGRect {
        let imageAspect = image.size.width > 0 && image.size.height > 0
            ? image.size.width / image.size.height
            : max(startFrame.width / max(startFrame.height, 1), 0.1)
        let safeAspect = min(max(imageAspect, 0.45), 1.8)
        let maxWidth = min(finalFrame.width * 0.58, 380)
        let maxHeight = min(finalFrame.height * 0.62, 560)

        var width = maxWidth
        var height = width / safeAspect
        if height > maxHeight {
            height = maxHeight
            width = height * safeAspect
        }

        return CGRect(
            x: finalFrame.midX - width / 2,
            y: finalFrame.midY - height / 2 - finalFrame.height * 0.035,
            width: width,
            height: height
        )
    }
}

// MARK: - Close transition

private final class HeroDismissTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceFrame: CGRect
    private let previewImage: UIImage?
    private let style: ReaderHeroTransitionStyle

    init(
        sourceFrame: CGRect,
        previewImage: UIImage?,
        style: ReaderHeroTransitionStyle
    ) {
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
        self.style = style
    }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        if UIAccessibility.isReduceMotionEnabled {
            return 0.18
        }

        switch style {
        case .coverZoom:
            return 0.34
        case .libraryLift:
            return 0.30
        }
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        let finalBounds = container.bounds

        if let toVC = ctx.viewController(forKey: .to),
           let toView = ctx.view(forKey: .to),
           toView.superview == nil {
            toView.frame = ctx.finalFrame(for: toVC)
            container.insertSubview(toView, belowSubview: fromView)
        }

        if UIAccessibility.isReduceMotionEnabled {
            animateReducedMotion(using: ctx, fromView: fromView)
            return
        }

        let targetFrame = HeroPresentTransition.resolvedSourceFrame(sourceFrame, in: finalBounds, container: container)

        let targetPreviewView = makeTargetPreviewView(frame: targetFrame)
        let animatingView = makeSnapshot(from: fromView)
        animatingView.frame = fromView.frame
        animatingView.clipsToBounds = true
        animatingView.layer.cornerRadius = 0

        if let targetPreviewView {
            container.addSubview(targetPreviewView)
        }
        container.addSubview(animatingView)
        fromView.isHidden = true

        let snapshotTargetFrame = snapshotTargetFrame(for: targetFrame, hasPreview: targetPreviewView != nil)
        let cornerRadius = targetCornerRadius
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: ctx), dampingRatio: 0.92) {
            animatingView.frame = snapshotTargetFrame
            animatingView.layer.cornerRadius = cornerRadius
            animatingView.alpha = targetPreviewView == nil ? 0.0 : 0.08
            targetPreviewView?.alpha = 1
            targetPreviewView?.transform = .identity
        }
        animator.addCompletion { _ in
            let completed = !ctx.transitionWasCancelled
            fromView.isHidden = false
            targetPreviewView?.removeFromSuperview()
            animatingView.removeFromSuperview()
            ctx.completeTransition(completed)
        }
        animator.startAnimation()
    }

    private func animateReducedMotion(
        using ctx: UIViewControllerContextTransitioning,
        fromView: UIView
    ) {
        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, options: [.curveEaseOut]) {
            fromView.alpha = 0
        } completion: { _ in
            ctx.completeTransition(!ctx.transitionWasCancelled)
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

        let imageView = HeroPresentTransition.makePreviewView(
            from: previewImage,
            cornerRadius: targetCornerRadius
        )
        imageView.frame = frame
        imageView.alpha = 0
        imageView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        return imageView
    }

    private func snapshotTargetFrame(for targetFrame: CGRect, hasPreview: Bool) -> CGRect {
        guard hasPreview else {
            return targetFrame
        }

        switch style {
        case .coverZoom:
            return targetFrame.insetBy(dx: -10, dy: -10)
        case .libraryLift:
            return targetFrame.insetBy(dx: -16, dy: -16)
        }
    }

    private var targetCornerRadius: CGFloat {
        switch style {
        case .coverZoom:
            return HeroTransitionMetrics.coverCornerRadius
        case .libraryLift:
            return HeroTransitionMetrics.libraryCornerRadius
        }
    }
}

private enum HeroTransitionMetrics {
    static let coverCornerRadius: CGFloat = 14
    static let libraryCornerRadius: CGFloat = 18
}

private final class HeroFloatingPreviewView: UIView {
    private let imageView: UIImageView

    var previewCornerRadius: CGFloat {
        get { imageView.layer.cornerRadius }
        set {
            imageView.layer.cornerRadius = newValue
            updateShadowPath()
        }
    }

    init(image: UIImage, cornerRadius: CGFloat) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .black
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = cornerRadius
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        updateShadowPath()
    }

    private func updateShadowPath() {
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: previewCornerRadius
        ).cgPath
    }
}

private extension CGRect {
    var isUsableHeroFrame: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && width.isFinite
            && height.isFinite
            && width > 2
            && height > 2
    }
}
