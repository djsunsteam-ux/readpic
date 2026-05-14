import AppKit
import CoreGraphics

final class ViewerNSView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onToggleZoom: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onZoomChanged: ((Int) -> Void)?
    var onDragTargetedChanged: ((Bool) -> Void)?
    var onCopyImage: (() -> Void)?
    var onCopyFile: (() -> Void)?
    var onCopyFilePath: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var onOpenExternally: (() -> Void)?
    var onMoveToTrash: (() -> Void)?
    var onRotateLeft: (() -> Void)?
    var onRotateRight: (() -> Void)?
    var onFlipHorizontal: (() -> Void)?
    var onRequestHigherRes: (() -> Void)?
    var onToggleInfoPanel: (() -> Void)?
    var onToggleGridView: (() -> Void)?
    var onToggleShortcutsHelp: (() -> Void)?
    var onToggleAnimationPause: (() -> Void)?
    var onToggleThumbnailStrip: (() -> Void)?
    var onEscape: (() -> Void)?

    private var currentProxyMaxPixelSize: CGFloat = 2048
    private var hasRequestedHigherRes = false

    var scrollBehavior: ScrollBehavior = .scrollPan

    private let imageLayer = CALayer()
    private var image: CGImage?
    private var displayImage: CGImage?
    private var zoomMode: ViewerModel.ZoomMode = .fitWindow
    private var panOffset: CGPoint = .zero
    private var zoomScale: CGFloat = 1
    private var rotation: Int = 0
    private var flippedHorizontally = false

    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        layoutImageLayer()
    }

    func setProxyMaxPixelSize(_ size: CGFloat) {
        currentProxyMaxPixelSize = size
        hasRequestedHigherRes = false
    }

    func setImage(_ image: CGImage?, zoomMode: ViewerModel.ZoomMode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let zoomModeChanged = self.zoomMode != zoomMode
        self.image = image
        self.zoomMode = zoomMode
        updateDisplayImage()
        if zoomModeChanged {
            panOffset = .zero
            zoomScale = 1
        }
        layoutImageLayer()
        CATransaction.commit()
    }

    func setAnimatedFrame(_ image: CGImage) {
        guard self.image !== image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.image = image
        updateDisplayImage()
        CATransaction.commit()
    }

    func setRotation(_ degrees: Int, flipped: Bool) {
        guard rotation != degrees || flippedHorizontally != flipped else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotation = degrees
        flippedHorizontally = flipped
        updateDisplayImage()
        panOffset = .zero
        zoomScale = 1
        layoutImageLayer()
        CATransaction.commit()
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let chars = event.characters

        switch event.keyCode {
        case 123: onPrevious?()
        case 124: onNext?()
        case 53:  onEscape?()
        case 49:  onToggleAnimationPause?()
        default:
            switch key {
            case "=", "+": zoomIn()
            case "-": zoomOut()
            case "0": resetZoom()
            case "i": onToggleInfoPanel?()
            case "g": onToggleGridView?()
            case "t": onToggleThumbnailStrip?()
            default:
                if chars == "?" { onToggleShortcutsHelp?() }
                else { super.keyDown(with: event) }
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Image")

        menu.addItem(withTitle: "Copy Image", action: #selector(doCopyImage), keyEquivalent: "")
        menu.addItem(withTitle: "Copy File", action: #selector(doCopyFile), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Path", action: #selector(doCopyFilePath), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(doRevealInFinder), keyEquivalent: "")
        menu.addItem(withTitle: "Open Externally", action: #selector(doOpenExternally), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rotate Left", action: #selector(doRotateLeft), keyEquivalent: "")
        menu.addItem(withTitle: "Rotate Right", action: #selector(doRotateRight), keyEquivalent: "")
        menu.addItem(withTitle: "Flip Horizontal", action: #selector(doFlipHorizontal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move to Trash", action: #selector(doMoveToTrash), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func doCopyImage() { onCopyImage?() }
    @objc private func doCopyFile() { onCopyFile?() }
    @objc private func doCopyFilePath() { onCopyFilePath?() }
    @objc private func doRevealInFinder() { onRevealInFinder?() }
    @objc private func doOpenExternally() { onOpenExternally?() }
    @objc private func doRotateLeft() { onRotateLeft?() }
    @objc private func doRotateRight() { onRotateRight?() }
    @objc private func doFlipHorizontal() { onFlipHorizontal?() }
    @objc private func doMoveToTrash() { onMoveToTrash?() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onToggleZoom?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            applyZoomDelta(event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY)
            return
        }

        switch scrollBehavior {
        case .zoom:
            applyZoomDelta(event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY)
        case .browse:
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                if event.scrollingDeltaX > 0 { onPrevious?() } else { onNext?() }
            } else if event.scrollingDeltaY != 0 {
                if event.scrollingDeltaY > 0 { onPrevious?() } else { onNext?() }
            }
        case .scrollPan:
            let newX = panOffset.x + event.scrollingDeltaX
            let newY = panOffset.y - event.scrollingDeltaY

            let (maxPanX, maxPanY) = maxPanOffset()

            // Check if at horizontal edges
            if maxPanX > 0 {
                if newX > maxPanX * 0.5 {
                    panOffset.x = maxPanX
                } else if newX < -maxPanX * 0.5 {
                    panOffset.x = -maxPanX
                } else {
                    panOffset.x = newX
                }
            }

            // Check if at vertical edges — if so, trigger page navigation
            if maxPanY > 0 {
                let threshold = maxPanY * 0.15
                if newY > maxPanY + threshold {
                    onNext?()
                    panOffset.y = 0
                } else if newY < -maxPanY - threshold {
                    onPrevious?()
                    panOffset.y = 0
                } else if newY > maxPanY {
                    panOffset.y = maxPanY
                } else if newY < -maxPanY {
                    panOffset.y = -maxPanY
                } else {
                    panOffset.y = newY
                }
            }

            layoutImageLayer()
        }
    }

    override func magnify(with event: NSEvent) {
        zoomScale = min(max(zoomScale * (1 + event.magnification), 0.1), 8)
        layoutImageLayer()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canRead = sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
        onDragTargetedChanged?(canRead)
        return canRead ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargetedChanged?(false)
    }

    func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 8)
        layoutImageLayer()
    }

    func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 0.1)
        layoutImageLayer()
    }

    func resetZoom() {
        zoomScale = 1
        panOffset = .zero
        layoutImageLayer()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onDragTargetedChanged?(false) }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first else {
            return false
        }
        onOpenURL?(url)
        return true
    }

    /// Returns the maximum pan offset (half the difference between image and viewport).
    /// Returns (0, 0) when the image fits entirely within the view.
    private func maxPanOffset() -> (CGFloat, CGFloat) {
        guard let displayImage else { return (0, 0) }
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }

        let imageSize = CGSize(width: displayImage.width, height: displayImage.height)

        let baseScale: CGFloat
        switch zoomMode {
        case .fitWindow:
            baseScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        case .fitWidth:
            baseScale = bounds.width / imageSize.width
        case .actualSize:
            baseScale = 1
        }

        let effectiveScale = baseScale * zoomScale
        let displayW = imageSize.width * effectiveScale
        let displayH = imageSize.height * effectiveScale

        let panX = max((displayW - bounds.width) / 2, 0)
        let panY = max((displayH - bounds.height) / 2, 0)
        return (panX, panY)
    }

    private func applyZoomDelta(_ delta: CGFloat) {
        let factor = exp(delta * 0.01)
        zoomScale = min(max(zoomScale * factor, 0.1), 8)
        layoutImageLayer()
    }

    private func layoutImageLayer() {
        guard let displayImage else {
            imageLayer.frame = .zero
            return
        }

        let imageSize = CGSize(width: displayImage.width, height: displayImage.height)
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = .zero
            return
        }

        let baseScale: CGFloat
        switch zoomMode {
        case .fitWindow:
            baseScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        case .fitWidth:
            baseScale = bounds.width / imageSize.width
        case .actualSize:
            baseScale = 1
        }

        let effectiveScale = baseScale * zoomScale
        let targetSize = CGSize(width: imageSize.width * effectiveScale, height: imageSize.height * effectiveScale)
        onZoomChanged?(Int((effectiveScale * 100).rounded()))

        imageLayer.frame = CGRect(
            x: (bounds.width - targetSize.width) / 2 + panOffset.x,
            y: (bounds.height - targetSize.height) / 2 + panOffset.y,
            width: targetSize.width,
            height: targetSize.height
        ).integral

        // Request higher resolution decode if zoomed past proxy threshold
        if !hasRequestedHigherRes {
            let displayedPixelWidth = targetSize.width
            let proxyWidth = CGFloat(displayImage.width)
            if displayedPixelWidth > proxyWidth * 1.2 {
                hasRequestedHigherRes = true
                onRequestHigherRes?()
            }
        }
    }

    private func updateDisplayImage() {
        guard let image else {
            displayImage = nil
            imageLayer.contents = nil
            return
        }
        guard rotation != 0 || flippedHorizontally else {
            displayImage = image
            imageLayer.contents = image
            return
        }

        // Create a rotated/flipped copy of the CGImage
        let radians = CGFloat(rotation) * .pi / 180
        let outputSize: CGSize
        if rotation == 90 || rotation == 270 {
            outputSize = CGSize(width: image.height, height: image.width)
        } else {
            outputSize = CGSize(width: image.width, height: image.height)
        }

        let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        )
        guard let ctx = context else { return }

        ctx.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
        if flippedHorizontally {
            ctx.scaleBy(x: -1, y: 1)
        }
        if rotation != 0 {
            ctx.rotate(by: radians)
        }
        ctx.draw(image, in: CGRect(
            x: -CGFloat(image.width) / 2,
            y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))

        displayImage = ctx.makeImage()
        imageLayer.contents = displayImage
    }
}
