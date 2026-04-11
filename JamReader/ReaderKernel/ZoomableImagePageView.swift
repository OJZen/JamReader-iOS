import UIKit

final class ZoomableImagePageView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let contentContainerView = UIView()

    var onTapRegion: ((ReaderTapRegion) -> Void)?
    var onZoomStateChanged: ((Bool) -> Void)?
    var onInteractionBegan: (() -> Void)?
    var tapEdgeRatio: CGFloat = 0.24

    var maximumZoomScale: CGFloat {
        scrollView.maximumZoomScale
    }

    var isAtPreferredZoom: Bool {
        scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
    }

    private let scrollView = ReaderTouchAwareScrollView()
    private var naturalContentSize: CGSize = .zero
    private var lastReportedZoomState: Bool?
    private var pendingZoomState: Bool?
    private var hasQueuedZoomStateFlush = false

    private lazy var doubleTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 2
        return gestureRecognizer
    }()

    private lazy var singleTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 1
        return gestureRecognizer
    }()

    /// Edge tap recognizer fires instantly (no require-to-fail delay) for responsive page turns.
    private lazy var edgeTapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
        gestureRecognizer.numberOfTapsRequired = 1
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard naturalContentSize.width > 0,
              naturalContentSize.height > 0
        else {
            return
        }

        syncContentGeometry()
    }

    func configureContentLayout(
        size: CGSize,
        fitMode: ReaderFitMode,
        resetZoomScale: Bool
    ) {
        guard size.width > 0, size.height > 0 else {
            clearContentLayout()
            return
        }

        naturalContentSize = size
        contentContainerView.frame = CGRect(origin: .zero, size: size)

        let minimumZoomScale = preferredZoomScale(
            boundsSize: scrollView.bounds.size,
            contentSize: size,
            fitMode: fitMode
        )
        let maximumZoomScale = max(minimumZoomScale * 4, 4)
        let previousMinimumZoomScale = scrollView.minimumZoomScale
        let wasAtFitZoom = scrollView.zoomScale <= previousMinimumZoomScale + 0.01

        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale

        if resetZoomScale || wasAtFitZoom {
            scrollView.zoomScale = minimumZoomScale
            scrollView.contentOffset = .zero
        } else {
            scrollView.zoomScale = min(max(scrollView.zoomScale, minimumZoomScale), maximumZoomScale)
        }

        scrollView.layoutIfNeeded()
        syncContentGeometry()
        queueZoomStateChanged(!isAtPreferredZoom)
    }

    func restorePreferredViewportState() {
        guard naturalContentSize.width > 0,
              naturalContentSize.height > 0
        else {
            return
        }

        scrollView.zoomScale = scrollView.minimumZoomScale
        scrollView.contentOffset = .zero
        scrollView.layoutIfNeeded()
        syncContentGeometry()
        queueZoomStateChanged(false)
    }

    func clearContentLayout() {
        naturalContentSize = .zero
        contentContainerView.frame = .zero
        scrollView.contentSize = .zero
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.zoomScale = 1
        scrollView.contentOffset = .zero
        scrollView.panGestureRecognizer.isEnabled = false
        queueZoomStateChanged(false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentContainerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        syncContentGeometry()
        queueZoomStateChanged(!isAtPreferredZoom)
    }

    private func configureSubviews() {
        backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.onTouchesBegan = { [weak self] in
            self?.onInteractionBegan?()
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.decelerationRate = .normal
        scrollView.isDirectionalLockEnabled = true
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        edgeTapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        singleTapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        singleTapGestureRecognizer.require(toFail: edgeTapGestureRecognizer)
        scrollView.addGestureRecognizer(edgeTapGestureRecognizer)
        scrollView.addGestureRecognizer(singleTapGestureRecognizer)
        scrollView.addGestureRecognizer(doubleTapGestureRecognizer)

        contentContainerView.backgroundColor = .black
        scrollView.addSubview(contentContainerView)

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func preferredZoomScale(
        boundsSize: CGSize,
        contentSize: CGSize,
        fitMode: ReaderFitMode
    ) -> CGFloat {
        guard boundsSize.width > 0,
              boundsSize.height > 0,
              contentSize.width > 0,
              contentSize.height > 0
        else {
            return 1
        }

        let widthScale = boundsSize.width / contentSize.width
        let heightScale = boundsSize.height / contentSize.height

        let preferredScale: CGFloat
        switch fitMode {
        case .page:
            preferredScale = min(widthScale, heightScale)
        case .width:
            preferredScale = widthScale
        case .height:
            preferredScale = heightScale
        case .originalSize:
            preferredScale = 1
        }

        return max(preferredScale, 0.01)
    }

    private func syncContentGeometry() {
        let displayedContentSize = CGSize(
            width: naturalContentSize.width * scrollView.zoomScale,
            height: naturalContentSize.height * scrollView.zoomScale
        )
        var frameToCenter = CGRect(origin: .zero, size: displayedContentSize)
        let boundsSize = scrollView.bounds.size

        frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width - 1
            ? (boundsSize.width - frameToCenter.size.width) * 0.5
            : 0
        frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height - 1
            ? (boundsSize.height - frameToCenter.size.height) * 0.5
            : 0

        contentContainerView.frame = frameToCenter
        scrollView.contentSize = displayedContentSize
        updatePanGestureAvailability()
    }

    private func updatePanGestureAvailability() {
        let contentFrame = contentContainerView.frame.size
        let hasScrollableOverflow = contentFrame.width > scrollView.bounds.width + 1
            || contentFrame.height > scrollView.bounds.height + 1
        scrollView.panGestureRecognizer.isEnabled = hasScrollableOverflow
    }

    private func queueZoomStateChanged(_ isZoomed: Bool) {
        guard lastReportedZoomState != isZoomed else {
            return
        }

        pendingZoomState = isZoomed

        guard !hasQueuedZoomStateFlush else {
            return
        }

        hasQueuedZoomStateFlush = true
        DispatchQueue.main.async { [weak self] in
            self?.flushQueuedZoomStateChanged()
        }
    }

    private func flushQueuedZoomStateChanged() {
        hasQueuedZoomStateFlush = false
        guard let pendingZoomState else {
            return
        }

        self.pendingZoomState = nil
        guard lastReportedZoomState != pendingZoomState else {
            return
        }

        lastReportedZoomState = pendingZoomState
        onZoomStateChanged?(pendingZoomState)
    }

    // MARK: - UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === edgeTapGestureRecognizer else {
            return true
        }
        return isEdgeTap(gestureRecognizer)
    }

    private func isEdgeTap(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let tapLocation = gestureRecognizer.location(in: self)
        let viewWidth = max(bounds.width, 1)
        let horizontalRatio = tapLocation.x / viewWidth
        return horizontalRatio < tapEdgeRatio || horizontalRatio > 1 - tapEdgeRatio
    }

    @objc
    private func handleEdgeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let onTapRegion else { return }
        let tapLocation = gestureRecognizer.location(in: self)
        let viewWidth = max(bounds.width, 1)
        let horizontalRatio = tapLocation.x / viewWidth

        if horizontalRatio < tapEdgeRatio {
            onTapRegion(.leading)
        } else {
            onTapRegion(.trailing)
        }
    }

    @objc
    private func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let onTapRegion else {
            return
        }

        // Edge taps are handled by edgeTapGestureRecognizer (instant, no delay).
        // This handler only processes center taps (toggle chrome / zoom state).
        onTapRegion(.center)
    }

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard naturalContentSize.width > 0,
              naturalContentSize.height > 0
        else {
            return
        }

        let minimumZoomScale = scrollView.minimumZoomScale
        let maximumZoomScale = scrollView.maximumZoomScale

        if scrollView.zoomScale > minimumZoomScale + 0.01 {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction]
            ) {
                self.scrollView.zoomScale = minimumZoomScale
            }
            return
        }

        let targetZoomScale = min(maximumZoomScale, minimumZoomScale * 2.5)
        let tapLocation = gestureRecognizer.location(in: contentContainerView)
        let zoomRectSize = CGSize(
            width: scrollView.bounds.width / targetZoomScale,
            height: scrollView.bounds.height / targetZoomScale
        )
        let zoomRect = CGRect(
            x: tapLocation.x - zoomRectSize.width * 0.5,
            y: tapLocation.y - zoomRectSize.height * 0.5,
            width: zoomRectSize.width,
            height: zoomRectSize.height
        )

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.scrollView.zoom(to: zoomRect, animated: false)
        }
    }
}

private final class ReaderTouchAwareScrollView: UIScrollView {
    var onTouchesBegan: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouchesBegan?()
        super.touchesBegan(touches, with: event)
    }
}
