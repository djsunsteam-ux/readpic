import CoreGraphics
import QuartzCore

/// Pure geometric computation for image zoom, pan, rotation and flip.
struct ZoomGeometry {
    enum Mode: Equatable {
        case fitWindow
        case fitWidth
        case actualSize
        case custom
    }

    var imageSize: CGSize = .zero
    var viewportSize: CGSize = .zero
    /// Insets that exclude overlaid bars (toolbar, status bar, thumbnail/frame strips).
    /// `fitWindow`/`fitWidth` use the inset viewport so the initial view fits in the
    /// visible area. Pan and zoom still use the full viewport — zoomed content extends
    /// behind the bars for the frosted-glass effect.
    var visibleInsets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    var mode: Mode = .fitWindow
    var defaultMode: Mode = .fitWindow
    var zoomLevel: CGFloat = 1.0
    var panOffset: CGPoint = .zero
    var rotation: Int = 0
    var isFlipped: Bool = false

    var effectiveImageSize: CGSize {
        rotation % 180 == 0
            ? imageSize
            : CGSize(width: imageSize.height, height: imageSize.width)
    }

    var displaySize: CGSize {
        CGSize(
            width: zoomLevel * effectiveImageSize.width,
            height: zoomLevel * effectiveImageSize.height
        )
    }

    var maxPanOffset: CGPoint {
        let w2 = max((displaySize.width  - viewportSize.width)  / 2, 0)
        let h2 = max((displaySize.height - viewportSize.height) / 2, 0)
        return CGPoint(x: w2, y: h2)
    }

    var clampedPan: CGPoint {
        let maxP = maxPanOffset
        return CGPoint(
            x: max(-maxP.x, min(maxP.x, panOffset.x)),
            y: max(-maxP.y, min(maxP.y, panOffset.y))
        )
    }

    /// Visible viewport width excluding overlaid bars (left + right insets).
    private var visibleWidth: CGFloat {
        viewportSize.width - visibleInsets.left - visibleInsets.right
    }
    /// Visible viewport height excluding overlaid bars (top + bottom insets).
    private var visibleHeight: CGFloat {
        viewportSize.height - visibleInsets.top - visibleInsets.bottom
    }

    var scaleToFit: CGFloat {
        let eff = effectiveImageSize
        guard eff.width > 0, eff.height > 0 else { return 1 }
        let vw = max(visibleWidth, 1)
        let vh = max(visibleHeight, 1)
        return min(vw / eff.width, vh / eff.height)
    }

    var scaleToFitWidth: CGFloat {
        guard effectiveImageSize.width > 0 else { return 1 }
        return max(visibleWidth, 1) / effectiveImageSize.width
    }

    mutating func resetZoom() {
        let effectiveMode = mode == .custom ? defaultMode : mode
        switch effectiveMode {
        case .fitWindow:   zoomLevel = scaleToFit
        case .fitWidth:    zoomLevel = scaleToFitWidth
        case .actualSize:  zoomLevel = 1.0
        case .custom:      break
        }
        mode = effectiveMode
        panOffset = .zero
    }

    mutating func setMode(_ newMode: Mode) {
        defaultMode = newMode
        mode = newMode
        resetZoom()
    }

    mutating func zoomIn() {
        mode = .custom
        zoomLevel = min(zoomLevel * 1.25, Self.maxZoomLevel)
    }

    mutating func zoomOut() {
        mode = .custom
        zoomLevel = max(zoomLevel / 1.25, Self.minZoomLevel)
    }

    mutating func applyScrollDelta(_ delta: CGFloat) {
        mode = .custom
        let factor = exp(delta * 0.01)
        zoomLevel = min(max(zoomLevel * factor, Self.minZoomLevel), Self.maxZoomLevel)
    }

    mutating func applyMagnification(_ factor: CGFloat) {
        mode = .custom
        zoomLevel = min(max(zoomLevel * (1 + factor), Self.minZoomLevel), Self.maxZoomLevel)
    }

    mutating func viewportDidChange(to newSize: CGSize) {
        guard newSize != viewportSize, newSize.width > 0, newSize.height > 0 else { return }
        viewportSize = newSize
        if mode == .fitWindow || mode == .fitWidth {
            resetZoom()
        }
    }

    var layerTransform: CATransform3D {
        var t = CATransform3DIdentity
        if rotation != 0 {
            let rad = CGFloat(rotation) * .pi / 180
            t = CATransform3DRotate(t, rad, 0, 0, 1)
        }
        if isFlipped {
            t = CATransform3DScale(t, -1, 1, 1)
        }
        return t
    }

    static let maxZoomLevel: CGFloat = 32
    static let minZoomLevel: CGFloat = 0.01
}
