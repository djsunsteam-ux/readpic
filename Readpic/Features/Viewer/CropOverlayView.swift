import AppKit
import CoreGraphics

/// AppKit overlay for interactive image cropping.
///
/// Draws a semi-transparent mask with a clear crop rectangle.
/// Handles mouse interaction for resizing, moving, and creating crop areas.
///
/// Coordinates:
/// - `normalizedCropRect` uses image space: origin.y=0 is the **top** of the
///   image, origin.y=1 is the **bottom** (matches CGImage pixel order).
/// - The NSView uses AppKit coordinates: origin at bottom-left, Y increases
///   upward.  All conversions flip the Y axis accordingly.
final class CropOverlayView: NSView {
    // MARK: - Types

    /// The type of drag operation in progress.
    private enum DragType {
        case none
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
        case top
        case right
        case bottom
        case left
        case inner
        case create
    }

    // MARK: - Constants

    /// Size of corner handle hit area (pixels).
    private static let cornerHitSize: CGFloat = 10
    /// Width of edge hit band (pixels, extends both inside and outside).
    private static let edgeHitWidth: CGFloat = 10
    /// Minimum crop rect dimension in view pixels during drag.
    private static let minCropSize: CGFloat = 40

    // MARK: - Public state

    /// Normalized crop rect (0…1, image space). Set by the model; updated on each drag.
    var normalizedCropRect: CGRect = .init(x: 0, y: 0, width: 1, height: 1) {
        didSet { needsDisplay = true }
    }
    /// The bounding rect of the image within this view (points, AppKit coords).
    var imageRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    /// Current aspect ratio constraint (nil = free).
    var cropRatio: CGFloat?
    /// Called when the crop rect changes during drag.
    var onCropRectChanged: ((CGRect) -> Void)?

    // MARK: - Private state

    private var dragType: DragType = .none
    private var dragStartViewPoint: CGPoint = .zero
    private var dragOriginalRect: CGRect = .zero // In view space
    private var isDragging = false
    /// When true, the dimension has reached minimum size and is locked against further shrinking.
    private var minSizeLockedWidth = false
    private var minSizeLockedHeight = false
    /// The rect at the moment the minimum-size lock was engaged.
    /// Used to detect "expanding" direction (vs. the drag start rect).
    private var widthLockedRect: CGRect = .zero
    private var heightLockedRect: CGRect = .zero

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Coordinate conversion

    /// Normalized image-space rect → AppKit view-space rect.
    func toView(_ norm: CGRect) -> CGRect {
        CGRect(
            x: imageRect.origin.x + norm.origin.x * imageRect.width,
            y: imageRect.maxY - (norm.origin.y + norm.height) * imageRect.height,
            width: norm.width * imageRect.width,
            height: norm.height * imageRect.height
        )
    }

    /// AppKit view-space rect → normalized image-space rect.
    func toNormalized(_ view: CGRect) -> CGRect {
        CGRect(
            x: (view.origin.x - imageRect.origin.x) / imageRect.width,
            y: (imageRect.maxY - view.origin.y - view.height) / imageRect.height,
            width: view.width / imageRect.width,
            height: view.height / imageRect.height
        )
    }

    // MARK: - Hit testing

    /// Determine what the user is clicking on.
    /// Priority: corners > edges > inner > create > none.
    private func hitTest(at viewPoint: CGPoint) -> DragType {
        let crop = toView(normalizedCropRect)
        let half = Self.cornerHitSize / 2

        // 1. Check corners (highest priority)
        // In view space: top-left of image = (minX, maxY), bottom-right = (maxX, minY)
        let corners: [(DragType, CGPoint)] = [
            (.topLeft, CGPoint(x: crop.minX, y: crop.maxY)),
            (.topRight, CGPoint(x: crop.maxX, y: crop.maxY)),
            (.bottomRight, CGPoint(x: crop.maxX, y: crop.minY)),
            (.bottomLeft, CGPoint(x: crop.minX, y: crop.minY)),
        ]

        for (type, corner) in corners {
            let hitRect = CGRect(x: corner.x - half, y: corner.y - half,
                                 width: Self.cornerHitSize, height: Self.cornerHitSize)
            if hitRect.contains(viewPoint) {
                return type
            }
        }

        // 2. Check edges
        let edgeBand = Self.edgeHitWidth

        // Top edge (image top = higher Y in view space)
        let topEdgeRect = CGRect(x: crop.minX, y: crop.maxY - edgeBand,
                                 width: crop.width, height: edgeBand * 2)
        if topEdgeRect.contains(viewPoint) { return .top }

        // Bottom edge (image bottom = lower Y in view space)
        let bottomEdgeRect = CGRect(x: crop.minX, y: crop.minY - edgeBand,
                                    width: crop.width, height: edgeBand * 2)
        if bottomEdgeRect.contains(viewPoint) { return .bottom }

        // Left edge
        let leftEdgeRect = CGRect(x: crop.minX - edgeBand, y: crop.minY,
                                  width: edgeBand * 2, height: crop.height)
        if leftEdgeRect.contains(viewPoint) { return .left }

        // Right edge
        let rightEdgeRect = CGRect(x: crop.maxX - edgeBand, y: crop.minY,
                                   width: edgeBand * 2, height: crop.height)
        if rightEdgeRect.contains(viewPoint) { return .right }

        // 3. Check inner area
        if crop.contains(viewPoint) { return .inner }

        // 4. Check if on image but outside crop (create new)
        if imageRect.contains(viewPoint) { return .create }

        // 5. Outside image
        return .none
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        dragType = hitTest(at: viewPoint)

        guard dragType != .none else {
            // Outside image — pass to responder chain
            super.mouseDown(with: event)
            return
        }

        dragStartViewPoint = viewPoint
        isDragging = true
        minSizeLockedWidth = false
        minSizeLockedHeight = false
        widthLockedRect = .zero
        heightLockedRect = .zero

        if dragType == .create {
            // Start a new crop rect from the click point
            dragOriginalRect = CGRect(origin: viewPoint, size: .zero)
        } else {
            dragOriginalRect = toView(normalizedCropRect)
        }

        // Set cursor for the drag operation
        cursorForDragType(dragType)?.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, dragType != .none else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let rawRect = calculateNewViewRect(currentPoint: currentPoint)
        let constrainedRect = applyConstraints(rawRect)

        // Update normalized rect
        normalizedCropRect = toNormalized(constrainedRect)
        onCropRectChanged?(normalizedCropRect)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }

        isDragging = false
        minSizeLockedWidth = false
        minSizeLockedHeight = false

        // Pop the drag cursor
        NSCursor.pop()

        // Validate final rect — if too small, reset to 50% of image
        let crop = toView(normalizedCropRect)
        if crop.width < Self.minCropSize || crop.height < Self.minCropSize {
            resetToDefaultRect()
        }

        dragType = .none
        needsDisplay = true

        // Update cursor for current mouse position
        if let window = window {
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            let viewPoint = convert(mouseLocation, from: nil)
            updateCursor(at: viewPoint)
        }
    }

    /// Reset crop rect to 50% of image, centered.
    private func resetToDefaultRect() {
        let ratio = cropRatio
        let imgW = imageRect.width
        let imgH = imageRect.height

        var w = imgW * 0.5
        var h = imgH * 0.5

        // Apply ratio if set
        if let ratio, ratio > 0 {
            if w / ratio > h {
                w = h * ratio
            } else {
                h = w / ratio
            }
        }

        let origin = CGPoint(
            x: imageRect.origin.x + (imgW - w) / 2,
            y: imageRect.origin.y + (imgH - h) / 2
        )
        normalizedCropRect = toNormalized(CGRect(origin: origin, size: CGSize(width: w, height: h)))
        onCropRectChanged?(normalizedCropRect)
    }

    // MARK: - Drag calculation

    /// Calculate the new crop rect in view space based on the current drag type and mouse position.
    private func calculateNewViewRect(currentPoint: CGPoint) -> CGRect {
        let orig = dragOriginalRect

        switch dragType {
        case .none:
            return orig

        case .topLeft:
            // Top-left corner: fixed point is bottom-right (maxX, minY)
            let fixed = CGPoint(x: orig.maxX, y: orig.minY)
            return normalizedRect(from: fixed, to: currentPoint)

        case .topRight:
            // Top-right corner: fixed point is bottom-left (minX, minY)
            let fixed = CGPoint(x: orig.minX, y: orig.minY)
            return normalizedRect(from: fixed, to: currentPoint)

        case .bottomRight:
            // Bottom-right corner: fixed point is top-left (minX, maxY)
            let fixed = CGPoint(x: orig.minX, y: orig.maxY)
            return normalizedRect(from: fixed, to: currentPoint)

        case .bottomLeft:
            // Bottom-left corner: fixed point is top-right (maxX, maxY)
            let fixed = CGPoint(x: orig.maxX, y: orig.maxY)
            return normalizedRect(from: fixed, to: currentPoint)

        case .top:
            // Top edge: adjust maxY, keep minY fixed
            let fixedY = orig.minY
            return CGRect(x: orig.minX, y: min(fixedY, currentPoint.y),
                          width: orig.width, height: abs(currentPoint.y - fixedY))

        case .right:
            // Right edge: adjust maxX, keep minX fixed
            return CGRect(x: orig.minX, y: orig.minY,
                          width: currentPoint.x - orig.minX, height: orig.height)

        case .bottom:
            // Bottom edge: adjust minY, keep maxY fixed
            let fixedY = orig.maxY
            return CGRect(x: orig.minX, y: min(fixedY, currentPoint.y),
                          width: orig.width, height: abs(fixedY - currentPoint.y))

        case .left:
            // Left edge: adjust minX, keep maxX fixed
            let fixedX = orig.maxX
            return CGRect(x: min(fixedX, currentPoint.x), y: orig.minY,
                          width: abs(fixedX - currentPoint.x), height: orig.height)

        case .inner:
            // Move the entire rect
            let deltaX = currentPoint.x - dragStartViewPoint.x
            let deltaY = currentPoint.y - dragStartViewPoint.y
            return CGRect(x: orig.origin.x + deltaX, y: orig.origin.y + deltaY,
                          width: orig.width, height: orig.height)

        case .create:
            // Create new rect from drag start to current point
            return normalizedRect(from: dragStartViewPoint, to: currentPoint)
        }
    }

    /// Create a normalized rect (positive width/height) from two points.
    private func normalizedRect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    // MARK: - Constraints

    /// Apply all constraints (boundary, aspect ratio, minimum size).
    /// Order matters: boundary → minimum size → aspect ratio → scale to fit.
    /// Minimum size must run BEFORE aspect ratio so that when a dimension is
    /// locked at the floor, the ratio is computed from the locked value.
    private func applyConstraints(_ rect: CGRect) -> CGRect {
        var result = rect

        // 1. Boundary — clamp to image rect first so the dragged edge
        //    never exceeds the image, regardless of aspect ratio.
        //    Inner drag (move) uses translate-only to preserve size/ratio.
        if dragType == .inner {
            result = applyBoundaryConstraintsForMove(result)
        } else {
            result = applyBoundaryConstraints(result)
        }

        // 2. Minimum size — lock at floor (runs before aspect ratio so
        //    the locked dimension feeds into the ratio calculation).
        result = applyMinimumSize(result)

        // 3. Aspect ratio — adjust the non-dragged dimension.
        if let ratio = cropRatio, ratio > 0 {
            result = applyAspectRatio(result, ratio: ratio)
            // After aspect ratio adjustment, the OTHER dimension may exceed the
            // boundary.  A plain clamp would break the ratio, so we scale both
            // dimensions down uniformly to fit while preserving the ratio.
            if dragType == .inner {
                result = applyBoundaryConstraintsForMove(result)
            } else {
                result = scaleToFitBoundary(result)
            }
        }

        return result
    }

    /// Apply aspect ratio constraint.
    private func applyAspectRatio(_ rect: CGRect, ratio: CGFloat) -> CGRect {
        switch dragType {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return applyAspectRatioForCorner(rect, ratio: ratio)

        case .top, .bottom:
            // Horizontal edge: user changes height → adjust width = height × ratio
            let newWidth = rect.height * ratio
            let newX = rect.minX - (newWidth - rect.width) / 2
            return CGRect(x: newX, y: rect.minY, width: newWidth, height: rect.height)

        case .left, .right:
            // Vertical edge: user changes width → adjust height = width ÷ ratio
            let newHeight = rect.width / ratio
            let newY = rect.minY - (newHeight - rect.height) / 2
            return CGRect(x: rect.minX, y: newY, width: rect.width, height: newHeight)

        case .inner, .create, .none:
            return rect
        }
    }

    /// Apply aspect ratio for corner drag.
    /// Uses the opposite corner as the fixed reference point.
    private func applyAspectRatioForCorner(_ rect: CGRect, ratio: CGFloat) -> CGRect {
        // Determine the fixed corner (opposite to the dragged corner)
        let fixed: CGPoint
        switch dragType {
        case .topLeft: fixed = CGPoint(x: rect.maxX, y: rect.minY) // bottom-right
        case .topRight: fixed = CGPoint(x: rect.minX, y: rect.minY) // bottom-left
        case .bottomRight: fixed = CGPoint(x: rect.minX, y: rect.maxY) // top-left
        case .bottomLeft: fixed = CGPoint(x: rect.maxX, y: rect.maxY) // top-right
        default: return rect
        }

        // Desired dimensions from fixed point to dragged corner
        let desiredWidth = abs(rect.maxX - fixed.x) + abs(rect.minX - fixed.x)
        let desiredHeight = abs(rect.maxY - fixed.y) + abs(rect.minY - fixed.y)

        // Adjust to maintain ratio — use the dimension that would make the rect smaller
        let newWidth: CGFloat
        let newHeight: CGFloat

        if desiredWidth / ratio > desiredHeight {
            newWidth = desiredWidth
            newHeight = desiredWidth / ratio
        } else {
            newHeight = desiredHeight
            newWidth = desiredHeight * ratio
        }

        // Calculate new origin based on which corner is being dragged
        let newOrigin: CGPoint
        switch dragType {
        case .topLeft:
            // Fixed is bottom-right; new rect extends left and up from fixed
            newOrigin = CGPoint(x: fixed.x - newWidth, y: fixed.y)
        case .topRight:
            // Fixed is bottom-left; new rect extends right and up from fixed
            newOrigin = CGPoint(x: fixed.x, y: fixed.y)
        case .bottomRight:
            // Fixed is top-left; new rect extends right and down from fixed
            newOrigin = CGPoint(x: fixed.x, y: fixed.y - newHeight)
        case .bottomLeft:
            // Fixed is top-right; new rect extends left and down from fixed
            newOrigin = CGPoint(x: fixed.x - newWidth, y: fixed.y - newHeight)
        default:
            newOrigin = rect.origin
        }

        return CGRect(origin: newOrigin, size: CGSize(width: newWidth, height: newHeight))
    }

    /// Constrain rect to stay within image bounds.
    private func applyBoundaryConstraints(_ rect: CGRect) -> CGRect {
        var result = rect

        // Clamp to image rect
        if result.minX < imageRect.minX {
            let diff = imageRect.minX - result.minX
            result.origin.x = imageRect.minX
            result.size.width -= diff
        }
        if result.minY < imageRect.minY {
            let diff = imageRect.minY - result.minY
            result.origin.y = imageRect.minY
            result.size.height -= diff
        }
        if result.maxX > imageRect.maxX {
            result.size.width = imageRect.maxX - result.minX
        }
        if result.maxY > imageRect.maxY {
            result.size.height = imageRect.maxY - result.minY
        }

        // Ensure non-negative size
        result.size.width = max(0, result.size.width)
        result.size.height = max(0, result.size.height)

        return result
    }

    /// Translate-only boundary constraint for inner drag (move).
    /// Pushes the rect back inside the image bounds WITHOUT changing its size.
    /// This preserves the aspect ratio during moves.
    private func applyBoundaryConstraintsForMove(_ rect: CGRect) -> CGRect {
        var result = rect

        if result.minX < imageRect.minX {
            result.origin.x = imageRect.minX
        }
        if result.minY < imageRect.minY {
            result.origin.y = imageRect.minY
        }
        if result.maxX > imageRect.maxX {
            result.origin.x = imageRect.maxX - result.width
        }
        if result.maxY > imageRect.maxY {
            result.origin.y = imageRect.maxY - result.height
        }

        return result
    }

    /// Scale rect to fit within image boundary while maintaining aspect ratio.
    /// Used after aspect ratio adjustment when the OTHER dimension may have exceeded
    /// the boundary.  Unlike `applyBoundaryConstraints` (which clamps one dimension
    /// and breaks the ratio), this scales BOTH dimensions uniformly.
    private func scaleToFitBoundary(_ rect: CGRect) -> CGRect {
        var result = rect

        // Already fits — nothing to do (check all four edges, not just dimensions)
        let fits = result.minX >= imageRect.minX
                && result.minY >= imageRect.minY
                && result.maxX <= imageRect.maxX
                && result.maxY <= imageRect.maxY
        guard !fits else { return result }

        // Determine the fixed corner / edge and available space from it.
        let fixedX: CGFloat
        let fixedY: CGFloat
        let availableW: CGFloat
        let availableH: CGFloat

        switch dragType {
        case .topLeft:
            // Fixed corner: bottom-right
            fixedX = result.maxX; fixedY = result.minY
            availableW = fixedX - imageRect.minX
            availableH = imageRect.maxY - fixedY
        case .topRight:
            // Fixed corner: bottom-left
            fixedX = result.minX; fixedY = result.minY
            availableW = imageRect.maxX - fixedX
            availableH = imageRect.maxY - fixedY
        case .bottomRight:
            // Fixed corner: top-left
            fixedX = result.minX; fixedY = result.maxY
            availableW = imageRect.maxX - fixedX
            availableH = fixedY - imageRect.minY
        case .bottomLeft:
            // Fixed corner: top-right
            fixedX = result.maxX; fixedY = result.maxY
            availableW = fixedX - imageRect.minX
            availableH = fixedY - imageRect.minY
        case .right:
            fixedX = result.minX; fixedY = result.midY
            availableW = imageRect.maxX - fixedX
            availableH = imageRect.height
        case .left:
            fixedX = result.maxX; fixedY = result.midY
            availableW = fixedX - imageRect.minX
            availableH = imageRect.height
        case .top:
            fixedX = result.midX; fixedY = result.minY
            availableW = imageRect.width
            availableH = imageRect.maxY - fixedY
        case .bottom:
            fixedX = result.midX; fixedY = result.maxY
            availableW = imageRect.width
            availableH = fixedY - imageRect.minY
        default:
            fixedX = result.midX; fixedY = result.midY
            availableW = imageRect.width
            availableH = imageRect.height
        }

        // Scale factor: the smaller one makes both dimensions fit
        let scale = min(availableW / result.width, availableH / result.height)
        let newW = result.width * scale
        let newH = result.height * scale

        // Position from the fixed corner / edge
        switch dragType {
        case .topLeft:
            result.origin = CGPoint(x: fixedX - newW, y: fixedY)
        case .topRight:
            result.origin = CGPoint(x: fixedX, y: fixedY)
        case .bottomRight:
            result.origin = CGPoint(x: fixedX, y: fixedY - newH)
        case .bottomLeft:
            result.origin = CGPoint(x: fixedX - newW, y: fixedY - newH)
        case .right:
            result.origin = CGPoint(x: fixedX, y: fixedY - newH / 2)
        case .left:
            result.origin = CGPoint(x: fixedX - newW, y: fixedY - newH / 2)
        case .top:
            result.origin = CGPoint(x: fixedX - newW / 2, y: fixedY)
        case .bottom:
            result.origin = CGPoint(x: fixedX - newW / 2, y: fixedY - newH)
        default:
            result.origin = CGPoint(x: fixedX - newW / 2, y: fixedY - newH / 2)
        }

        result.size = CGSize(width: newW, height: newH)
        return result
    }

    /// Enforce minimum size with locking behavior.
    /// Once a dimension hits minimum, it locks and only allows expanding
    /// in the direction away from the fixed edge. Dragging further toward
    /// the fixed edge has no effect (the crop box stays put).
    private func applyMinimumSize(_ rect: CGRect) -> CGRect {
        var result = rect

        // ── Width locking ──────────────────────────────────────────
        // Detect if user is still trying to shrink (moving edge toward fixed edge).
        // Compare against the LOCKED rect (not drag start) so the unlock
        // threshold is right at the lock point, not far away at the start.
        let widthTryingToShrink: Bool
        let widthRef = minSizeLockedWidth ? widthLockedRect : result
        switch dragType {
        case .topLeft, .left, .bottomLeft:
            widthTryingToShrink = result.minX >= widthRef.minX
        case .topRight, .right, .bottomRight:
            widthTryingToShrink = result.maxX <= widthRef.maxX
        default:
            widthTryingToShrink = result.width < Self.minCropSize
        }

        if result.width < Self.minCropSize {
            if !minSizeLockedWidth {
                // First time hitting minimum — record the lock position
                widthLockedRect = result
            }
            minSizeLockedWidth = true
        }
        if minSizeLockedWidth {
            let lockedWidth = Self.minCropSize
            if widthTryingToShrink {
                // Still shrinking or holding — freeze at locked state
                switch dragType {
                case .topLeft, .left, .bottomLeft:
                    result.origin.x = widthLockedRect.maxX - lockedWidth
                case .topRight, .right, .bottomRight:
                    result.origin.x = widthLockedRect.minX
                default:
                    break
                }
                result.size.width = lockedWidth
            } else {
                // Expanding away from fixed edge — allow it, clear lock
                minSizeLockedWidth = false
            }
        }

        // ── Height locking ─────────────────────────────────────────
        let heightTryingToShrink: Bool
        let heightRef = minSizeLockedHeight ? heightLockedRect : result
        switch dragType {
        case .topLeft, .top, .topRight:
            heightTryingToShrink = result.maxY <= heightRef.maxY
        case .bottomLeft, .bottom, .bottomRight:
            heightTryingToShrink = result.minY >= heightRef.minY
        default:
            heightTryingToShrink = result.height < Self.minCropSize
        }

        if result.height < Self.minCropSize {
            if !minSizeLockedHeight {
                // First time hitting minimum — record the lock position
                heightLockedRect = result
            }
            minSizeLockedHeight = true
        }
        if minSizeLockedHeight {
            let lockedHeight = Self.minCropSize
            if heightTryingToShrink {
                // Still shrinking or holding — freeze at locked state
                switch dragType {
                case .topLeft, .top, .topRight:
                    result.origin.y = heightLockedRect.minY
                case .bottomLeft, .bottom, .bottomRight:
                    result.origin.y = heightLockedRect.maxY - lockedHeight
                default:
                    break
                }
                result.size.height = lockedHeight
            } else {
                // Expanding away from fixed edge — allow it, clear lock
                minSizeLockedHeight = false
            }
        }

        return result
    }

    // MARK: - Cursor management

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard imageRect.width > 0, imageRect.height > 0 else { return }

        let crop = toView(normalizedCropRect)
        let hitHalf = Self.cornerHitSize / 2
        let edgeBand = Self.edgeHitWidth

        // Corner cursors (crosshair for diagonal resize)
        let corners: [CGPoint] = [
            CGPoint(x: crop.minX, y: crop.maxY), // top-left
            CGPoint(x: crop.maxX, y: crop.maxY), // top-right
            CGPoint(x: crop.maxX, y: crop.minY), // bottom-right
            CGPoint(x: crop.minX, y: crop.minY), // bottom-left
        ]
        for pt in corners {
            addCursorRect(CGRect(x: pt.x - hitHalf, y: pt.y - hitHalf,
                                 width: Self.cornerHitSize, height: Self.cornerHitSize),
                          cursor: .crosshair)
        }

        // Edge cursors
        addCursorRect(CGRect(x: crop.minX, y: crop.maxY - edgeBand,
                             width: crop.width, height: edgeBand * 2),
                      cursor: .resizeUpDown) // top
        addCursorRect(CGRect(x: crop.minX, y: crop.minY - edgeBand,
                             width: crop.width, height: edgeBand * 2),
                      cursor: .resizeUpDown) // bottom
        addCursorRect(CGRect(x: crop.minX - edgeBand, y: crop.minY,
                             width: edgeBand * 2, height: crop.height),
                      cursor: .resizeLeftRight) // left
        addCursorRect(CGRect(x: crop.maxX - edgeBand, y: crop.minY,
                             width: edgeBand * 2, height: crop.height),
                      cursor: .resizeLeftRight) // right

        // Inner cursor (open hand for move)
        addCursorRect(crop, cursor: .openHand)
    }

    private func updateCursor(at viewPoint: CGPoint) {
        let type = hitTest(at: viewPoint)
        switch type {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            NSCursor.crosshair.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .inner:
            NSCursor.openHand.set()
        case .create:
            NSCursor.crosshair.set()
        case .none:
            NSCursor.arrow.set()
        }
    }

    /// Get the appropriate cursor for a drag type.
    private func cursorForDragType(_ type: DragType) -> NSCursor? {
        switch type {
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            return .crosshair
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .inner:
            return .closedHand
        case .create:
            return .crosshair
        case .none:
            return nil
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }

        let crop = toView(normalizedCropRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Semi-transparent mask
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fill(bounds)

        // 2. Clear the crop area
        ctx.setBlendMode(.destinationOut)
        ctx.fill(crop)
        ctx.setBlendMode(.normal)

        // 3. Crop border — thicker during drag
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(isDragging ? 2.0 : 1.5)
        ctx.stroke(crop)

        // 4. 3×3 rule-of-thirds grid inside crop area
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1 ... 2 {
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

        // 5. Corner handles — slightly larger during drag
        let handleSize: CGFloat = isDragging ? 10 : 8
        let half = handleSize / 2
        let handles: [CGPoint] = [
            CGPoint(x: crop.minX, y: crop.minY), // bottom-left (view)
            CGPoint(x: crop.maxX, y: crop.minY), // bottom-right (view)
            CGPoint(x: crop.minX, y: crop.maxY), // top-left (view)
            CGPoint(x: crop.maxX, y: crop.maxY), // top-right (view)
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for pt in handles {
            ctx.fillEllipse(in: CGRect(x: pt.x - half, y: pt.y - half,
                                       width: handleSize, height: handleSize))
        }

        // 6. Aspect ratio indicator (bottom-right corner)
        if let ratio = cropRatio, ratio > 0 {
            let ratioText = ratioDisplayString(ratio)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            ]
            let textSize = (ratioText as NSString).size(withAttributes: attrs)
            let textPoint = CGPoint(x: crop.maxX - textSize.width - 4,
                                    y: crop.minY + 4)
            // Background pill
            let pillRect = CGRect(x: textPoint.x - 3, y: textPoint.y - 1,
                                  width: textSize.width + 6, height: textSize.height + 2)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.fill(pillRect)
            (ratioText as NSString).draw(at: textPoint, withAttributes: attrs)
        }
    }

    /// Human-readable ratio string.
    private func ratioDisplayString(_ ratio: CGFloat) -> String {
        // Check common ratios
        let common: [(CGFloat, String)] = [
            (1.0, "1:1"), (1.5, "3:2"), (2.0 / 3.0, "2:3"),
            (4.0 / 3.0, "4:3"), (0.75, "3:4"), (16.0 / 9.0, "16:9"),
            (9.0 / 16.0, "9:16"), (21.0 / 9.0, "21:9"),
        ]
        for (value, label) in common {
            if abs(ratio - value) < 0.01 { return label }
        }
        return String(format: "%.2f:1", ratio)
    }
}
