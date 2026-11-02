import UIKit

/// The current page as the hero transition sees it.
struct ReaderHeroPage {
    /// Fills the reader's viewport and draws the page, without the reader's bars.
    let view: UIView
    /// The part of `view` the page covers; the rest is letterbox.
    let contentRect: CGRect
}

@MainActor
protocol ReaderHeroPageSource: AnyObject {
    var heroPage: ReaderHeroPage? { get }
}

/// What the reader has on screen to lift out when it closes.
enum ReaderHeroContent {
    case openingState
    case document
    /// Opening failed; the page is only black and text, so it just fades.
    case nothing
}

enum ReaderHeroGeometry {
    private static let dragFadeDistance: CGFloat = 350
    private static let dragMinimumScale: CGFloat = 0.72

    /// Where a cover sits once it fills the reader the way a page does: fitted
    /// and centered, or full width from `topInset` in a continuous reader.
    static func landingFrame(
        for imageSize: CGSize,
        in bounds: CGRect,
        topInset: CGFloat?
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        if let topInset {
            return CGRect(
                x: bounds.minX,
                y: bounds.minY + topInset,
                width: bounds.width,
                height: bounds.width * imageSize.height / imageSize.width
            )
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Center and scale that make `contentRect` of a viewport-sized snapshot
    /// fill `bounds` while keeping its proportions.
    static func snapshotPlacement(
        viewportSize: CGSize,
        contentRect: CGRect,
        filling bounds: CGRect
    ) -> (center: CGPoint, scale: CGFloat) {
        guard contentRect.width > 0, contentRect.height > 0 else {
            return (CGPoint(x: bounds.midX, y: bounds.midY), 1)
        }

        let scale = max(bounds.width / contentRect.width, bounds.height / contentRect.height)
        return (
            CGPoint(
                x: bounds.midX + (viewportSize.width / 2 - contentRect.midX) * scale,
                y: bounds.midY + (viewportSize.height / 2 - contentRect.midY) * scale
            ),
            scale
        )
    }

    static func dragProgress(distance: CGFloat) -> CGFloat {
        min(max(distance / dragFadeDistance, 0), 1)
    }

    /// The page under the finger: it follows the drag and shrinks as it leaves.
    static func dragFrame(from frame: CGRect, offset: CGSize, progress: CGFloat) -> CGRect {
        let scale = 1 - (1 - dragMinimumScale) * progress
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(
            x: frame.midX + offset.width - size.width / 2,
            y: frame.midY + offset.height - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// The one copy of the comic that flies between the list and the reader. Its
/// content keeps its own proportions whatever the frame; the frame only clips.
final class ReaderHeroView: UIView {
    private let pageSnapshot: UIView?
    private let viewportSize: CGSize
    private let contentRect: CGRect
    private let coverView: UIImageView?

    var showsCover: Bool {
        get { (coverView?.alpha ?? 0) > 0 }
        set { coverView?.alpha = newValue ? 1 : 0 }
    }

    convenience init(cover: UIImage) {
        self.init(pageSnapshot: nil, viewportSize: .zero, contentRect: .zero, cover: cover)
        showsCover = true
    }

    init(pageSnapshot: UIView?, viewportSize: CGSize, contentRect: CGRect, cover: UIImage?) {
        self.pageSnapshot = pageSnapshot
        self.viewportSize = viewportSize
        self.contentRect = contentRect
        self.coverView = cover.map(UIImageView.init(image:))
        super.init(frame: .zero)

        clipsToBounds = true
        layer.cornerCurve = .continuous
        if let pageSnapshot {
            addSubview(pageSnapshot)
        }
        if let coverView {
            coverView.contentMode = .scaleAspectFill
            coverView.alpha = 0
            addSubview(coverView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        coverView?.frame = bounds
        guard let pageSnapshot else {
            return
        }

        let placement = ReaderHeroGeometry.snapshotPlacement(
            viewportSize: viewportSize,
            contentRect: contentRect,
            filling: bounds
        )
        pageSnapshot.center = placement.center
        pageSnapshot.transform = CGAffineTransform(scaleX: placement.scale, y: placement.scale)
    }
}

/// Ties one presented reader to the transition that opens and closes it, and
/// lets a pull-down drag start the flight the close animation finishes.
@MainActor
final class ReaderHeroContext {
    let sourceID: String?
    let sourceFrame: CGRect
    let coverImage: UIImage?
    /// A continuous reader shows the first page from the top, not centered.
    let landsAtTop: Bool

    weak var pageSource: ReaderHeroPageSource?
    weak var presentedView: UIView?
    /// False once the reader moved on to another comic: the source and the
    /// cover belong to the first one.
    var isShowingOpenedComic = true
    var content = ReaderHeroContent.openingState

    private var isDragging = false
    private var dragHero: ReaderHeroView?
    private var dragStartFrame: CGRect = .zero
    private var settleAnimator: UIViewPropertyAnimator?
    private weak var hiddenPageView: UIView?

    init(sourceID: String?, sourceFrame: CGRect, coverImage: UIImage?, landsAtTop: Bool) {
        self.sourceID = sourceID
        self.sourceFrame = sourceFrame
        self.coverImage = coverImage
        self.landsAtTop = landsAtTop
    }

    var sourceCornerRadius: CGFloat {
        sourceID.map(HeroSourceRegistry.shared.cornerRadius(for:)) ?? CornerRadius.thumbnail
    }

    /// Shared by the flying cover and the opening state, so they meet exactly.
    func landingFrame(in bounds: CGRect) -> CGRect {
        ReaderHeroGeometry.landingFrame(
            for: coverImage?.size ?? bounds.size,
            in: bounds,
            topInset: landsAtTop
                ? VerticalReaderZoomGeometry.verticalSectionInset(
                    viewportWidth: bounds.width,
                    scale: VerticalReaderZoomGeometry.minimumScale
                )
                : nil
        )
    }

    /// Where the cover starts from, or nil without a position to trust.
    func openingFrame(in container: UIView) -> CGRect? {
        guard sourceFrame.isFiniteHeroFrame else {
            return nil
        }

        let frame = HeroSourceFrameSanitizer.sanitized(
            container.convert(sourceFrame, from: nil),
            in: container.bounds
        )
        return frame.isFiniteHeroFrame ? frame : nil
    }

    /// Where the cover is now, in window coordinates. The stored frame is only
    /// used without an id: rotating or resizing in the reader outdates it.
    var closingFrame: CGRect? {
        guard isShowingOpenedComic else {
            return nil
        }

        let frame = sourceID.map(HeroSourceRegistry.shared.frame(for:)) ?? sourceFrame
        return frame.isFiniteHeroFrame ? frame : nil
    }

    func hideSource() {
        HeroSourceRegistry.shared.hideSource(isShowingOpenedComic ? sourceID : nil)
    }

    /// Lifts the current page out of the reader, leaving the rest to fade.
    func makeHero(from readerView: UIView, in container: UIView) -> ReaderHeroView? {
        guard let page = pageSource?.heroPage ?? contentPage(in: readerView),
              !page.contentRect.isEmpty,
              let snapshot = page.view.snapshotView(afterScreenUpdates: false) else {
            return nil
        }

        let hero = ReaderHeroView(
            pageSnapshot: snapshot,
            viewportSize: page.view.bounds.size,
            contentRect: page.contentRect,
            cover: isShowingOpenedComic ? coverImage : nil
        )
        hero.frame = container.convert(page.contentRect, from: page.view)
        container.addSubview(hero)
        hero.layoutIfNeeded()

        if page.view !== readerView {
            page.view.isHidden = true
            hiddenPageView = page.view
        }
        return hero
    }

    /// Without a page view: the cover of the opening state, or a whole
    /// document such as an EPUB, which has no letterbox to leave behind.
    private func contentPage(in readerView: UIView) -> ReaderHeroPage? {
        switch content {
        case .openingState:
            guard isShowingOpenedComic, coverImage != nil else {
                return nil
            }
            return ReaderHeroPage(
                view: readerView,
                contentRect: landingFrame(in: readerView.bounds).intersection(readerView.bounds)
            )
        case .document:
            return ReaderHeroPage(view: readerView, contentRect: readerView.bounds)
        case .nothing:
            return nil
        }
    }

    // MARK: - Pull-down drag

    func updateDrag(offset: CGSize, distance: CGFloat) {
        settleAnimator?.stopAnimation(true)
        settleAnimator = nil

        guard let presentedView, let container = presentedView.superview else {
            return
        }

        isDragging = true
        if dragHero == nil {
            dragHero = makeHero(from: presentedView, in: container)
            dragStartFrame = dragHero?.frame ?? .zero
            if dragHero != nil {
                hideSource()
            }
        }

        let progress = ReaderHeroGeometry.dragProgress(distance: distance)
        dragHero?.frame = ReaderHeroGeometry.dragFrame(
            from: dragStartFrame,
            offset: offset,
            progress: progress
        )
        presentedView.alpha = 1 - progress
    }

    /// Also called when no drag is going on, as when the gesture direction
    /// changes while a document loads; the opening transition must not notice.
    func cancelDrag() {
        guard isDragging else {
            return
        }

        isDragging = false
        settleAnimator?.stopAnimation(true)
        let startFrame = dragStartFrame
        let animator = UIViewPropertyAnimator(
            duration: 0.35,
            dampingRatio: 0.86
        ) { [presentedView, dragHero] in
            dragHero?.frame = startFrame
            dragHero?.layoutIfNeeded()
            presentedView?.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            self?.finishCancelledDrag()
        }
        settleAnimator = animator
        animator.startAnimation()
    }

    /// Hands the page under the finger to the close animation.
    func takeDragHero() -> ReaderHeroView? {
        settleAnimator?.stopAnimation(true)
        settleAnimator = nil
        isDragging = false
        defer { dragHero = nil }
        return dragHero
    }

    private func finishCancelledDrag() {
        settleAnimator = nil
        dragHero?.removeFromSuperview()
        dragHero = nil
        hiddenPageView?.isHidden = false
        hiddenPageView = nil
        HeroSourceRegistry.shared.hideSource(nil)
    }
}
