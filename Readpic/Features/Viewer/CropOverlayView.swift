import AppKit
import CoreGraphics

/// AppKit overlay for interactive image cropping.
///
/// Draws a semi-transparent mask with a clear crop rectangle. Handles mouse
/// drag to move or resize the crop area, with optional aspect-ratio locking.
///
/// Coordinates: all rects are in the view's own coordinate system (points).
/// The model's `cropRect` is normalized 0…1; this view converts to/from pixels.
final class CropOverlayView: NSView {
    /// Normalized crop rect (0…1). Set by the model; updated on each drag.
    var normalizedCropRect: CGRect = .init(x: 0, y: 0, width: 1, height: 1) {
        didSet { needsDisplay = true }
    }
    /// The pixel size of the source image (for pixel-space ratio calculations).
    var imagePixelSize: CGSize = .zero
    /// Fires on mouseUp after a drag, so the model can read the final rect.
    var onDragEnded: ((CGRect) -> Void)?
    /// The bounding rect of the image within this view (points).
    var imageRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    /// Aspect ratio to lock (nil = free).
    var lockedRatio: CGFloat? = nil {
        didSet { needsDisplay = true }
    }

    // MARK: - Drag state

    private enum DragHandle {
        case inside, topLeft, topRight, bottomLeft, bottomRight
        case top, left, bottom, right
        case none
    }
    private var dragHandle: DragHandle = .none
    private var dragStartPoint: NSPoint = .zero
    private var dragStartRect: CGRect = .zero

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        // Convert normalized rect to view coordinates
        let crop = CGRect(
            x: imageRect.origin.x + normalizedCropRect.origin.x * imageRect.width,
            y: imageRect.origin.y + normalizedCropRect.origin.y * imageRect.height,
            width:  normalizedCropRect.width  * imageRect.width,
            height: normalizedCropRect.height * imageRect.height
        )

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Semi-transparent mask
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)

        // 2. Clear the crop area
        ctx.setBlendMode(.destinationOut)
        ctx.fill(crop)
        ctx.setBlendMode(.normal)

        // 3. Crop border
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(crop)

        // 4. 3×3 rule-of-thirds grid inside crop area
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let x = crop.origin.x + CGFloat(i) * crop.width / 3
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: crop.minY))
            ctx.addLine(to: CGPoint(x: x, y: crop.maxY))
            ctx.strokePath()

            let y = crop.origin.y + CGFloat(i) * crop.height / 3
            ctx.beginPath()
            ctx.move(to: CGPoint(x: crop.minX, y: y))
            ctx.addLine(to: CGPoint(x: crop.maxX, y: y))
            ctx.strokePath()
        }

        // 5. Corner handles
        let handleSize: CGFloat = 8
        let half = handleSize / 2
        let handles: [CGPoint] = [
            CGPoint(x: crop.minX, y: crop.minY), // bottom-left
            CGPoint(x: crop.maxX, y: crop.minY), // bottom-right
            CGPoint(x: crop.minX, y: crop.maxY), // top-left
            CGPoint(x: crop.maxX, y: crop.maxY), // top-right
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for pt in handles {
            ctx.fillEllipse(in: CGRect(x: pt.x - half, y: pt.y - half, width: handleSize, height: handleSize))
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragHandle = hitTestHandle(pt)
        dragStartPoint = pt
        dragStartRect = normalizedCropRect
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragHandle != .none else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let dx = (pt.x - dragStartPoint.x) / imageRect.width
        let dy = (pt.y - dragStartPoint.y) / imageRect.height

        var newRect = dragStartRect

        switch dragHandle {
        case .inside:
            newRect.origin.x = clamp(dragStartRect.origin.x + dx, 0, 1 - dragStartRect.width)
            newRect.origin.y = clamp(dragStartRect.origin.y + dy, 0, 1 - dragStartRect.height)

        case .topLeft:
            newRect.origin.x = clamp(dragStartRect.origin.x + dx, 0, dragStartRect.maxX - minSize)
            newRect.size.width = dragStartRect.maxX - newRect.origin.x
            newRect.size.height = dragStartRect.maxY - (dragStartRect.origin.y + dy)
            newRect.origin.y = dragStartRect.origin.y + dy
            applyRatioIfNeeded(&newRect, fixedCorner: .topLeft)

        case .topRight:
            newRect.size.width = clamp(dragStartRect.width + dx, minSize, 1 - dragStartRect.origin.x)
            newRect.size.height = dragStartRect.maxY - (dragStartRect.origin.y + dy)
            newRect.origin.y = dragStartRect.origin.y + dy
            applyRatioIfNeeded(&newRect, fixedCorner: .topRight)

        case .bottomLeft:
            newRect.origin.x = clamp(dragStartRect.origin.x + dx, 0, dragStartRect.maxX - minSize)
            newRect.size.width = dragStartRect.maxX - newRect.origin.x
            newRect.size.height = clamp(dragStartRect.height - dy, minSize, 1 - dragStartRect.origin.y)
            newRect.origin.y = dragStartRect.maxY - (newRect.origin.y + newRect.size.height)
            applyRatioIfNeeded(&newRect, fixedCorner: .bottomLeft)

        case .bottomRight:
            newRect.size.width = clamp(dragStartRect.width + dx, minSize, 1 - dragStartRect.origin.x)
            newRect.size.height = clamp(dragStartRect.height - dy, minSize, 1 - dragStartRect.origin.y)
            newRect.origin.y = dragStartRect.maxY - (newRect.origin.y + newRect.size.height)
            applyRatioIfNeeded(&newRect, fixedCorner: .bottomRight)

        case .top:
            newRect.size.height = dragStartRect.maxY - (dragStartRect.origin.y + dy)
            newRect.origin.y = dragStartRect.origin.y + dy
            applyRatioIfNeeded(&newRect, fixedCorner: .topLeft)

        case .bottom:
            newRect.size.height = clamp(dragStartRect.height - dy, minSize, 1 - dragStartRect.origin.y)
            applyRatioIfNeeded(&newRect, fixedCorner: .bottomLeft)

        case .left:
            newRect.origin.x = clamp(dragStartRect.origin.x + dx, 0, dragStartRect.maxX - minSize)
            newRect.size.width = dragStartRect.maxX - newRect.origin.x
            applyRatioIfNeeded(&newRect, fixedCorner: .topLeft)

        case .right:
            newRect.size.width = clamp(dragStartRect.width + dx, minSize, 1 - dragStartRect.origin.x)
            applyRatioIfNeeded(&newRect, fixedCorner: .topRight)

        case .none: break
        }

        // Ensure within image bounds
        newRect.origin.x = clamp(newRect.origin.x, 0, 1 - newRect.width)
        newRect.origin.y = clamp(newRect.origin.y, 0, 1 - newRect.height)
        newRect.size.width = clamp(newRect.size.width, minSize, 1 - newRect.origin.x)
        newRect.size.height = clamp(newRect.size.height, minSize, 1 - newRect.origin.y)

        normalizedCropRect = newRect
    }

    override func mouseUp(with event: NSEvent) {
        dragHandle = .none
        onDragEnded?(normalizedCropRect)
    }

    // MARK: - Hit testing

    private let handleRadius: CGFloat = 6
    private let edgeThickness: CGFloat = 10
    private let minSize: CGFloat = 0.05

    private func hitTestHandle(_ pt: NSPoint) -> DragHandle {
        let crop = rectInView
        guard crop.contains(pt) else { return .none }

        // Corner hit test
        let corners: [(CGRect, DragHandle)] = [
            (handleRect(center: CGPoint(x: crop.minX, y: crop.minY)), .bottomLeft),
            (handleRect(center: CGPoint(x: crop.maxX, y: crop.minY)), .bottomRight),
            (handleRect(center: CGPoint(x: crop.minX, y: crop.maxY)), .topLeft),
            (handleRect(center: CGPoint(x: crop.maxX, y: crop.maxY)), .topRight),
        ]
        for (r, handle) in corners {
            if r.contains(pt) { return handle }
        }

        // Edge hit test
        let inset = crop.insetBy(dx: edgeThickness, dy: edgeThickness)
        let topEdge = CGRect(x: inset.minX, y: crop.maxY - edgeThickness, width: inset.width, height: edgeThickness)
        let bottomEdge = CGRect(x: inset.minX, y: crop.minY, width: inset.width, height: edgeThickness)
        let leftEdge = CGRect(x: crop.minX, y: inset.minY, width: edgeThickness, height: inset.height)
        let rightEdge = CGRect(x: crop.maxX - edgeThickness, y: inset.minY, width: edgeThickness, height: inset.height)

        if topEdge.contains(pt) { return .top }
        if bottomEdge.contains(pt) { return .bottom }
        if leftEdge.contains(pt) { return .left }
        if rightEdge.contains(pt) { return .right }

        return .inside
    }

    private var rectInView: CGRect {
        CGRect(
            x: imageRect.origin.x + normalizedCropRect.origin.x * imageRect.width,
            y: imageRect.origin.y + normalizedCropRect.origin.y * imageRect.height,
            width:  normalizedCropRect.width  * imageRect.width,
            height: normalizedCropRect.height * imageRect.height
        )
    }

    private func handleRect(center: CGPoint) -> CGRect {
        CGRect(x: center.x - handleRadius, y: center.y - handleRadius,
               width: handleRadius * 2, height: handleRadius * 2)
    }

    // MARK: - Ratio lock

    /// Fits the rect to `lockedRatio` (pixel-space) while keeping `fixedCorner` stationary.
    /// Works in pixel space so the ratio comparison is correct regardless of
    /// the image's own aspect ratio.
    private func applyRatioIfNeeded(_ rect: inout CGRect, fixedCorner: DragHandle) {
        guard let ratio = lockedRatio else { return }
        let imgW = max(1, imagePixelSize.width)
        let imgH = max(1, imagePixelSize.height)

        // Current pixel-space aspect
        let pw = rect.width * imgW
        let ph = rect.height * imgH
        let pixelAspect = pw / ph
        guard abs(pixelAspect - ratio) > 0.001 else { return }

        // We'll adjust the rect in normalized space to achieve the target pixel ratio.
        // pixelRatio = (normW * imgW) / (normH * imgH)  =>  normW / normH = ratio * imgH / imgW
        let targetNormRatio = ratio * imgH / imgW

        switch fixedCorner {
        case .bottomRight, .right, .topRight:
            rect.size.height = rect.width / targetNormRatio
        case .bottomLeft, .left:
            rect.size.height = rect.width / targetNormRatio
            rect.origin.y = rect.maxY - rect.height
            if rect.origin.y < 0 {
                rect.origin.y = 0
                rect.size.height = rect.maxY
                rect.size.width = rect.height * targetNormRatio
            }
        case .top:
            rect.size.height = rect.width / targetNormRatio
        case .topLeft:
            let bottomY = rect.maxY
            rect.size.height = rect.width / targetNormRatio
            rect.origin.y = bottomY - rect.height
            if rect.origin.y < 0 {
                rect.origin.y = 0
                rect.size.height = bottomY
                rect.size.width = rect.height * targetNormRatio
            }
            if rect.origin.x < 0 {
                rect.origin.x = 0
                rect.size.width = rect.width
            }
        case .bottom:
            rect.size.width = rect.height * targetNormRatio
        case .inside, .none:
            break
        }
    }

    // MARK: - Helper

    private func clamp(_ val: CGFloat, _ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(val, min), max)
    }
}
