import AppKit
import CoreGraphics

final class ViewerNSView: NSView {
    // MARK: - Callbacks
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
    var onToggleFullScreen: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCropRectChanged: ((CGRect) -> Void)?
    var onCropConfirm: (() -> Void)?
    var onCropCancel: (() -> Void)?
    var onColorPicked: ((NSColor, CGPoint, String) -> Void)?
    var onColorPickerLockToggled: (() -> Void)?

    // MARK: - Public state
    var scrollBehavior: ScrollBehavior = .scrollPan
    var isColorPickerMode = false {
        didSet {
            guard oldValue != isColorPickerMode else { return }
            window?.invalidateCursorRects(for: self)
            updateTrackingAreas()
        }
    }
    var isColorPickerLocked = false

    // MARK: - Private state

    /// Single source of truth for all zoom / pan / rotation / flip geometry.
    private var zoom = ZoomGeometry()
    /// The current proxy image displayed in the layer (unrotated).
    /// Set as `imageLayer.contents` directly.
    private var proxyImage: CGImage?

    private let imageLayer = CALayer()

    /// Tracks the proxy decode size so we don't request upgrades more than once per proxy level.
    private var currentProxyMaxPixelSize: CGFloat = 2048
    /// Prevents re-requesting a higher-res proxy while one is already in flight.
    private var hasRequestedHigherRes = false
    /// Accumulated horizontal scroll delta for side-wheel page navigation.
    private var horizontalScrollAccumulator: CGFloat = 0

    /// Maximum stretch factor for the proxy image before requesting a higher-res decode.
    /// Avoids displaying blurry stretched pixels while the async decode is in flight.
    private static let proxyStretchLimit: CGFloat = 1.2

    // MARK: - Crop

    private let cropOverlayView = CropOverlayView(frame: .zero)
    var isCropMode = false {
        didSet { cropOverlayView.isHidden = !isCropMode; needsLayout = true }
    }
    /// Ratio to lock the crop overlay (nil = free).
    var cropLockedRatio: CGFloat? {
        get { cropOverlayView.lockedRatio }
        set { cropOverlayView.lockedRatio = newValue }
    }
    var cropImagePixelSize: CGSize {
        get { cropOverlayView.imagePixelSize }
        set { cropOverlayView.imagePixelSize = newValue }
    }

    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    // MARK: - Init

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

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)

        // Crop overlay (hidden until crop mode)
        cropOverlayView.isHidden = true
        cropOverlayView.postsFrameChangedNotifications = false
        cropOverlayView.onDragEnded = { [weak self] rect in
            self?.onCropRectChanged?(rect)
        }
        addSubview(cropOverlayView)
    }

    @objc private func handleDoubleClick() {
        onToggleZoom?()
    }

    // MARK: - Key equivalents (⌘ shortcuts)

    /// Override to handle ⌘Delete with keyCode instead of relying on the menu's
    /// `KeyEquivalent` (which may not match third-party keyboards that send varying
    /// Unicode characters for the Delete key). HID keyCode 51 is the standard
    /// Backspace/Delete scan code across all keyboards.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 51 {
            onMoveToTrash?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if bounds.size != zoom.viewportSize {
            zoom.viewportDidChange(to: bounds.size)
        }

        layoutImageLayer()

        // Crop overlay — match image layer frame
        if !cropOverlayView.isHidden {
            cropOverlayView.frame = bounds
            cropOverlayView.imageRect = imageLayer.frame
        }

        CATransaction.commit()
    }

    // MARK: - Public configuration

    func setProxyMaxPixelSize(_ size: CGFloat) {
        currentProxyMaxPixelSize = size
    }

    /// Set a new image (first load or navigation).
    /// Recomputes zoom from the current mode and native size.
    func setImage(_ image: CGImage?, zoomMode: ZoomGeometry.Mode, nativeSize: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        proxyImage = image
        imageLayer.contents = image
        zoom.imageSize = nativeSize
        zoom.viewportSize = bounds.size
        zoom.defaultMode = zoomMode
        zoom.mode = zoomMode
        zoom.rotation = 0
        zoom.isFlipped = false
        zoom.resetZoom()
        hasRequestedHigherRes = false

        imageLayer.transform = CATransform3DIdentity
        layoutImageLayer()
        CATransaction.commit()
    }

    /// Upgrade proxy resolution for the same image — preserves zoom level and mode.
    /// No-ops when the CGImage and native size are unchanged (avoids redundant
    /// layout passes triggered by unrelated @Observable updates like color picker).
    func upgradeImage(_ image: CGImage, nativeSize: CGSize) {
        guard proxyImage !== image || zoom.imageSize != nativeSize else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        proxyImage = image
        imageLayer.contents = image
        zoom.imageSize = nativeSize
        // Proxy just arrived — allow re-requesting a higher one if still needed.
        hasRequestedHigherRes = false
        // zoomLevel, mode, pan, rotation, flip all preserved
        layoutImageLayer()
        CATransaction.commit()
    }

    /// Update the displayed frame during animation playback.
    /// Only swaps the layer contents — `proxyImage` is deliberately NOT updated
    /// because individual GIF frames may be smaller than the canvas, which would
    /// trigger a false proxy cap in `layoutImageLayer`.
    func setAnimatedFrame(_ image: CGImage) {
        guard imageLayer.contents != nil, (imageLayer.contents as! CGImage) !== image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }

    /// Update rotation and flip — applied as CATransform3D on the imageLayer,
    /// no bitmap copy needed.
    func setRotation(_ degrees: Int, flipped: Bool) {
        guard zoom.rotation != degrees || zoom.isFlipped != flipped else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoom.rotation = degrees
        zoom.isFlipped = flipped
        zoom.panOffset = .zero
        layoutImageLayer()
        CATransaction.commit()
    }

    /// Update zoom mode from the model (menu / toolbar action).
    func applyZoomMode(_ mode: ZoomGeometry.Mode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoom.setMode(mode)
        layoutImageLayer()
        CATransaction.commit()
    }

    /// Set visible insets that exclude overlaid bars / panels for fit-window calculations.
    /// When bars are hidden (fullscreen) the insets become zero, so the image fills the full viewport.
    func setBarInsets(isFullScreen: Bool, cursorNearTop: Bool, cursorNearBottom: Bool,
                      showFrameStrip: Bool, frameStripVisible: Bool,
                      showThumbnailStrip: Bool, thumbnailStripVisible: Bool,
                      showStatusBar: Bool, statusBarVisible: Bool,
                      infoPanelWidth: CGFloat = 0) {
        let barsHidden = isFullScreen && !cursorNearTop && !cursorNearBottom
        let top: CGFloat = barsHidden ? 0 : 40
        let right = infoPanelWidth
        let bottom: CGFloat
        if barsHidden {
            bottom = 0
        } else {
            bottom = (frameStripVisible ? 56 : 0)
                   + (thumbnailStripVisible ? 64 : 0)
                   + (statusBarVisible ? 26 : 0)
        }
        let newInsets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: right)
        let oldInsets = zoom.visibleInsets
        guard newInsets.top != oldInsets.top || newInsets.bottom != oldInsets.bottom || newInsets.right != oldInsets.right else { return }
        zoom.visibleInsets = newInsets
        if zoom.mode == .fitWindow || zoom.mode == .fitWidth {
            zoom.resetZoom()
        }
        layoutImageLayer()
    }

    // MARK: - Keyboard & context menu (unchanged)

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()

        // When crop mode is active, Return and Escape are handled by SwiftUI
        // button .keyboardShortcut to avoid double-firing applyCrop/cancelCrop.
        guard !isCropMode || (event.keyCode != 36 && event.keyCode != 53) else {
            return
        }

        switch event.keyCode {
        case 123: onPrevious?()
        case 124: onNext?()
        case 53:  onEscape?()
        case 49:
            // Slideshow uses Space for pause — handled by ViewerView key monitor
            guard onToggleAnimationPause != nil else { fallthrough }
            onToggleAnimationPause?()
        default:
            switch key {
            case "=", "+": zoomIn()
            case "-": zoomOut()
            case "0": resetZoom()
            default:
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - Color Picker

    private func sampleColor(at viewPoint: CGPoint) {
        guard let proxyImage else { return }

        // Convert view → unrotated layer space (CATransform3D inverse handled by CALayer)
        let layerPoint = imageLayer.convert(viewPoint, from: self.layer)
        let lb = imageLayer.bounds
        let imgW = CGFloat(proxyImage.width)
        let imgH = CGFloat(proxyImage.height)

        guard lb.width > 0, lb.height > 0, imgW > 0, imgH > 0,
              layerPoint.x >= 0, layerPoint.x <= lb.width,
              layerPoint.y >= 0, layerPoint.y <= lb.height else { return }

        // Map to image pixel coordinates (layer Y-up → CGImage Y-down)
        let px = max(0, min(Int((layerPoint.x / lb.width) * imgW), proxyImage.width - 1))
        let py = max(0, min(Int(((lb.height - layerPoint.y) / lb.height) * imgH), proxyImage.height - 1))

        guard let color = proxyImage.colorAt(x: px, y: py) else { return }

        let hex = String(format: "#%02X%02X%02X",
                         Int(color.redComponent * 255),
                         Int(color.greenComponent * 255),
                         Int(color.blueComponent * 255))

        onColorPicked?(color, CGPoint(x: px, y: py), hex)
    }

    // MARK: - Tracking area (color picker mouse tracking)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = isColorPickerMode
            ? [.mouseMoved, .activeInKeyWindow]
            : []
        if !options.isEmpty {
            addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if isColorPickerMode { NSCursor.crosshair.set() }
        guard isColorPickerMode, !isColorPickerLocked else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        sampleColor(at: viewPoint)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isColorPickerMode {
            NSCursor.crosshair.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isColorPickerMode {
            onColorPickerLockToggled?()
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isColorPickerMode {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Image".localized)

        menu.addItem(withTitle: "Copy Image".localized, action: #selector(doCopyImage), keyEquivalent: "")
        menu.addItem(withTitle: "Copy File".localized, action: #selector(doCopyFile), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Path".localized, action: #selector(doCopyFilePath), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder".localized, action: #selector(doRevealInFinder), keyEquivalent: "")
        menu.addItem(withTitle: "Open Externally".localized, action: #selector(doOpenExternally), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rotate Left".localized, action: #selector(doRotateLeft), keyEquivalent: "")
        menu.addItem(withTitle: "Rotate Right".localized, action: #selector(doRotateRight), keyEquivalent: "")
        menu.addItem(withTitle: "Flip Horizontal".localized, action: #selector(doFlipHorizontal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move to Trash".localized, action: #selector(doMoveToTrash), keyEquivalent: "")

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

    // MARK: - Scroll wheel

    override func scrollWheel(with event: NSEvent) {
        // Side-scroll wheel (MX Master 3S etc.): pure horizontal → accumulate + page nav
        // Pure horizontal scroll (side-wheel etc.): accumulate + page nav
        if event.scrollingDeltaY == 0, abs(event.scrollingDeltaX) > 0.5 {
            horizontalScrollAccumulator += event.scrollingDeltaX
            let threshold: CGFloat = 45
            if abs(horizontalScrollAccumulator) >= threshold {
                if horizontalScrollAccumulator > 0 { onPrevious?() } else { onNext?() }
                horizontalScrollAccumulator = 0
            }
            return
        }
        // Non-horizontal scroll resets accumulator so a stale partial doesn't
        // trigger a premature page-turn on the next horizontal event.
        horizontalScrollAccumulator = 0

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
            let maxPan = zoom.maxPanOffset
            let newX = zoom.panOffset.x + event.scrollingDeltaX
            let newY = zoom.panOffset.y - event.scrollingDeltaY

            zoom.panOffset.x = clampPanAxis(newX, limit: maxPan.x)
            zoom.panOffset.y = clampPanAxis(newY, limit: maxPan.y,
                                            overflowNext: { self.onNext?() },
                                            overflowPrevious: { self.onPrevious?() })

            layoutImageLayer()
        }
    }

    override func magnify(with event: NSEvent) {
        zoom.applyMagnification(event.magnification)
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

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onDragTargetedChanged?(false) }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first else {
            return false
        }
        onOpenURL?(url)
        return true
    }

    // MARK: - Crop

    func getCropRect() -> CGRect { cropOverlayView.normalizedCropRect }
    func setCropRect(_ rect: CGRect) { cropOverlayView.normalizedCropRect = rect }

    // MARK: - Zoom actions

    func zoomIn() {
        zoom.zoomIn()
        layoutImageLayer()
    }

    func zoomOut() {
        zoom.zoomOut()
        layoutImageLayer()
    }

    func resetZoom() {
        zoom.resetZoom()
        layoutImageLayer()
    }

    // MARK: - Layout

    /// Core layout routine.
    ///
    /// **Geometry vs. proxy cap separation:**
    /// - `zoom` computes the ideal display size from pure geometry (native size × zoomLevel,
    ///   accounting for rotation).
    /// - This method applies a proxy stretch cap so the proxy CGImage is never stretched
    ///   beyond `proxyStretchLimit` × its pixel dimensions, preventing blur while a
    ///   higher-res decode is in flight.
    /// - **Pan bounds always use the ideal (uncapped) size** so they don't jump when the
    ///   proxy upgrades.
    private func layoutImageLayer() {
        guard let proxyImage else {
            imageLayer.frame = .zero
            return
        }

        let proxySize = CGSize(width: proxyImage.width, height: proxyImage.height)
        guard proxySize.width > 0, proxySize.height > 0, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = .zero
            return
        }

        // Ensure zoom sees the latest viewport size
        zoom.viewportSize = bounds.size

        // ── Proxy cap ──────────────────────────────────────────────
        // The layer's bounds are in the UNROTATED coordinate frame
        // (the CATransform3D handles rotation visually).
        let idealDisplay = zoom.displaySize
        let unrotatedIdeal: CGSize
        if zoom.rotation % 180 == 0 {
            unrotatedIdeal = idealDisplay
        } else {
            unrotatedIdeal = CGSize(width: idealDisplay.height, height: idealDisplay.width)
        }

        // When the proxy already covers the full native resolution, skip the stretch cap.
        // The image will get pixelated at high zoom — that's expected and standard.
        // EXIF orientation may swap dimensions (e.g. 4032×3024 image with orientation=6
        // produces a 3024×4032 CGImage), so we check both orderings.
        let imageW = zoom.imageSize.width
        let imageH = zoom.imageSize.height
        let isAtNativeRes = (proxySize.width >= imageW && proxySize.height >= imageH)
                         || (proxySize.width >= imageH && proxySize.height >= imageW)

        let displaySize: CGSize
        if isAtNativeRes {
            displaySize = unrotatedIdeal
        } else {
            let maxStretch = CGSize(
                width:  proxySize.width  * Self.proxyStretchLimit,
                height: proxySize.height * Self.proxyStretchLimit
            )
            displaySize = CGSize(
                width:  min(unrotatedIdeal.width,  maxStretch.width),
                height: min(unrotatedIdeal.height, maxStretch.height)
            )
        }

        // ── Pan ────────────────────────────────────────────────────
        // Pan bounds use IDEAL (uncapped) size for stability across proxy upgrades.
        let pan = zoom.clampedPan

        // ── Position ───────────────────────────────────────────────
        imageLayer.bounds = CGRect(origin: .zero, size: displaySize)
        // Center in the VISIBLE area (between bars / beside panel) instead of
        // the full viewport. The image starts out fitting within the insets,
        // but pan/zoom content can extend behind the overlaid bars and panel.
        let visibleLeft = zoom.visibleInsets.left
        let visibleRight = zoom.visibleInsets.right
        let xCenter = (bounds.width - visibleLeft - visibleRight) / 2 + visibleLeft
        let yCenter = bounds.midY + (zoom.visibleInsets.bottom - zoom.visibleInsets.top) / 2
        imageLayer.position = CGPoint(x: xCenter + pan.x, y: yCenter + pan.y)
        imageLayer.transform = zoom.layerTransform

        // ── Report zoom ────────────────────────────────────────────
        onZoomChanged?(Int((zoom.zoomLevel * 100).rounded()))

        // ── Request higher-res proxy if needed ─────────────────────
        // Only request when a) proxy is NOT at native res and b) either dimension is stretched beyond limit.
        if !isAtNativeRes, !hasRequestedHigherRes {
            let neededProxyWidth  = unrotatedIdeal.width  / Self.proxyStretchLimit
            let neededProxyHeight = unrotatedIdeal.height / Self.proxyStretchLimit
            if proxySize.width < neededProxyWidth || proxySize.height < neededProxyHeight {
                hasRequestedHigherRes = true
                onRequestHigherRes?()
            }
        }

        // ── Sync crop overlay after zoom/pan ───────────────────────
        // layout() only fires on view-system-initiated layout passes, but every
        // zoom/pan action calls layoutImageLayer() directly. Update the overlay
        // here so its imageRect stays in sync with imageLayer.frame.
        if !cropOverlayView.isHidden {
            cropOverlayView.imageRect = imageLayer.frame
        }
    }

    // MARK: - Helpers

    private func applyZoomDelta(_ delta: CGFloat) {
        zoom.applyScrollDelta(delta)
        layoutImageLayer()
    }

    /// Clamp a single pan axis with optional overflow page navigation.
    /// - `limit`: the max absolute offset on this axis (from `maxPanOffset`).
    /// - `overflowNext`: triggered when panning past the positive edge.
    /// - `overflowPrevious`: triggered when panning past the negative edge.
    private func clampPanAxis(
        _ desired: CGFloat,
        limit: CGFloat,
        overflowNext: (() -> Void)? = nil,
        overflowPrevious: (() -> Void)? = nil
    ) -> CGFloat {
        guard limit > 0 else { return 0 }

        let threshold = limit * 0.15

        if desired > limit + threshold {
            overflowNext?()
            return 0
        } else if desired < -limit - threshold {
            overflowPrevious?()
            return 0
        } else if desired > limit {
            return limit
        } else if desired < -limit {
            return -limit
        } else {
            return desired
        }
    }
}

// MARK: - Pixel color reading

private extension CGImage {
    /// Read the color of a single pixel at (x, y) in the image's own coordinate system.
    /// Fast path reads bytes directly from the data provider; exotic formats fall
    /// back to a 1×1 CGContext render.
    func colorAt(x: Int, y: Int) -> NSColor? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        // Fast path: read raw bytes directly (O(1), common ImageIO formats)
        if let color = fastColorAt(x: x, y: y) { return color }

        // Exotic format — render a 1×1 crop into a known-format context
        return slowColorAt(x: x, y: y)
    }

    private func fastColorAt(x: Int, y: Int) -> NSColor? {
        guard let provider = dataProvider,
              let data = CFDataGetBytePtr(provider.data) else { return nil }

        let bpp = bitsPerPixel / 8
        let offset = y * bytesPerRow + x * bpp
        guard offset >= 0, offset + bpp <= CFDataGetLength(provider.data) else { return nil }

        let ptr = data + offset
        let ai = alphaInfo
        let bi = bitmapInfo

        // BGRA — most common on Apple Silicon (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)
        if ai == .premultipliedFirst, bi.contains(.byteOrder32Little) {
            return NSColor(red: CGFloat(ptr[2])/255, green: CGFloat(ptr[1])/255, blue: CGFloat(ptr[0])/255, alpha: 1)
        }
        // RGBA (big-endian or default)
        if ai == .premultipliedLast || ai == .last {
            if bi.contains(.byteOrder32Little) {
                // ABGR
                return NSColor(red: CGFloat(ptr[3])/255, green: CGFloat(ptr[2])/255, blue: CGFloat(ptr[1])/255, alpha: 1)
            }
            return NSColor(red: CGFloat(ptr[0])/255, green: CGFloat(ptr[1])/255, blue: CGFloat(ptr[2])/255, alpha: 1)
        }
        // RGB — no alpha (24-bit)
        if ai == .none || ai == .noneSkipLast {
            return NSColor(red: CGFloat(ptr[0])/255, green: CGFloat(ptr[1])/255, blue: CGFloat(ptr[2])/255, alpha: 1)
        }

        return nil
    }

    private func slowColorAt(x: Int, y: Int) -> NSColor? {
        guard let cropped = self.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(red: CGFloat(pixel[0])/255, green: CGFloat(pixel[1])/255, blue: CGFloat(pixel[2])/255, alpha: 1)
    }
}
