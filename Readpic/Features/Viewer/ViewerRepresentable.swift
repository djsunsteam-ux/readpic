import AppKit
import SwiftUI

extension ZoomGeometry.Mode {
    init(from modelMode: ViewerModel.ZoomMode) {
        switch modelMode {
        case .fitWindow:  self = .fitWindow
        case .fitWidth:   self = .fitWidth
        case .actualSize: self = .actualSize
        }
    }
}

struct ViewerRepresentable: NSViewRepresentable {
    let model: ViewerModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var currentImageURL: URL?
        var currentZoomMode: ViewerModel.ZoomMode?
    }

    func makeNSView(context: Context) -> ViewerNSView {
        let view = ViewerNSView()
        view.onPrevious = { model.showPrevious() }
        view.onNext = { model.showNext() }
        view.onToggleZoom = { model.toggleZoomMode() }
        view.onZoomChanged = { percent in model.updateZoomPercent(percent) }
        view.onDragTargetedChanged = { isTargeted in model.setDragTargeted(isTargeted) }
        view.onCopyImage = { model.copyImage() }
        view.onCopyFile = { model.copyFile() }
        view.onCopyFilePath = { model.copyFilePath() }
        view.onRevealInFinder = { model.revealInFinder() }
        view.onOpenExternally = { model.openExternally() }
        view.onRotateLeft = { model.rotateLeft() }
        view.onRotateRight = { model.rotateRight() }
        view.onFlipHorizontal = { model.flipHorizontal() }
        view.onMoveToTrash = { model.moveCurrentFileToTrash() }
        view.onRequestHigherRes = { model.requestHigherResolution() }
        view.onToggleInfoPanel = { model.toggleInfoPanel() }
        view.onToggleGridView = { model.toggleGridView() }
        view.onToggleShortcutsHelp = { model.toggleShortcutsHelp() }
        view.onToggleAnimationPause = { model.toggleAnimationPause() }
        view.onToggleThumbnailStrip = { model.toggleThumbnailStrip() }
        view.onToggleFullScreen = { model.toggleFullScreen() }
        view.onCropConfirm = { model.applyCrop() }
        view.onCropCancel = { model.cancelCrop() }
        view.onCrop = { model.enterCropMode() }
        view.onCropRectChanged = { rect in model.cropRect = rect }
        view.onEscape = {
            if model.isCropMode { model.cancelCrop() }
            else if model.showShortcutsHelp { model.showShortcutsHelp = false }
            else if model.isInfoPanelVisible { model.isInfoPanelVisible = false }
            else { model.closeWindow() }
        }
        view.onColorPicked = { color, point, hex in
            guard model.isColorPickerMode, !model.isColorPickerLocked else { return }
            model.pickedColor = (color, point, hex)
        }
        view.onColorPickerLockToggled = {
            model.toggleColorPickerLock()
        }
        view.onOpenURL = { url in
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                model.openFolder(url)
            } else {
                model.open(url)
            }
        }
        return view
    }

    func updateNSView(_ nsView: ViewerNSView, context: Context) {
        // Use actual CGImage dimensions so zoom/layout matches the displayed pixels.
        // pixelSize from ImageIO properties may have swapped W/H for EXIF-oriented HEIC.
        let nativeSize: CGSize
        if let img = model.decodedImage {
            nativeSize = CGSize(width: img.image.width, height: img.image.height)
        } else {
            nativeSize = .zero
        }
        let zoomMode = ZoomGeometry.Mode(from: model.zoomMode)

        // ── Animation frame ──────────────────────────────────────
        // Also enter this path in crop mode so the user can select frames
        // via the frame strip (paused display, not auto-advancing).
        let shouldShowFrame = model.isAnimating
        if shouldShowFrame, let frames = model.decodedImage?.animatedFrames,
           model.currentFrameIndex < frames.count
        {
            let frame = frames[model.currentFrameIndex].image
            let zoomModeChanged = model.zoomMode != context.coordinator.currentZoomMode
            context.coordinator.currentZoomMode = model.zoomMode
            if zoomModeChanged {
                nsView.setImage(frame, zoomMode: zoomMode, nativeSize: nativeSize)
            } else {
                nsView.setAnimatedFrame(frame)
            }
            // Apply rotation/flip and bar insets even for animated frames
            nsView.setRotation(model.rotation, flipped: model.isFlippedHorizontally)
            nsView.setBarInsets(
                isFullScreen: model.isFullScreen,
                cursorNearTop: model.cursorNearTop,
                cursorNearBottom: model.cursorNearBottom,
                showFrameStrip: model.showFrameStrip,
                frameStripVisible: model.showFrameStrip && model.hasAnimatedFrames,
                showThumbnailStrip: model.showThumbnailStrip,
                thumbnailStripVisible: model.navigableFiles.count > 1 && model.showThumbnailStrip && !model.isGridView,
                showStatusBar: model.settings.showStatusBar,
                statusBarVisible: model.settings.showStatusBar && !model.statusText.isEmpty,
                infoPanelWidth: model.isInfoPanelVisible ? 300 : 0
            )
            // Crop mode must be set even for animated images.
            syncCropMode(nsView: nsView, model: model)
            return
        }

        // Determine which image to display
        let displayImage: CGImage
        if let frameImg = model.cropFrameImage {
            displayImage = frameImg
        } else if let img = model.decodedImage?.image {
            displayImage = img
        } else {
            nsView.setImage(nil, zoomMode: zoomMode, nativeSize: .zero)
            context.coordinator.currentImageURL = nil
            context.coordinator.currentZoomMode = nil
            return
        }

        // ── Image / mode / action routing ────────────────────────
        let decodedURL = model.decodedImage?.url
        let isSameImage = decodedURL != nil && decodedURL == context.coordinator.currentImageURL
        let zoomModeChanged = model.zoomMode != context.coordinator.currentZoomMode
        context.coordinator.currentImageURL = decodedURL
        context.coordinator.currentZoomMode = model.zoomMode

        if isSameImage {
            // Same image — preserve zoom/pan/rotation state, just upgrade proxy if available
            nsView.upgradeImage(displayImage, nativeSize: nativeSize)
            if zoomModeChanged {
                nsView.applyZoomMode(zoomMode)
            }
        } else {
            // New image — full set (resets zoom/pan/rotation)
            nsView.setImage(displayImage, zoomMode: zoomMode, nativeSize: nativeSize)
        }

        // ── Zoom action commands ─────────────────────────────────
        switch model.zoomAction {
        case .zoomIn:     nsView.zoomIn()
        case .zoomOut:    nsView.zoomOut()
        case .resetZoom:  nsView.applyZoomMode(zoomMode)
        case .none:       break
        }
        if model.zoomAction != .none {
            Task { @MainActor in model.zoomAction = .none }
        }

        // ── Rotation / flip / proxy / scroll / bar insets ────────
        nsView.setRotation(model.rotation, flipped: model.isFlippedHorizontally)
        nsView.setProxyMaxPixelSize(model.currentProxyMaxPixelSize)
        nsView.scrollBehavior = model.settings.scrollBehavior
        nsView.setBarInsets(
            isFullScreen: model.isFullScreen,
            cursorNearTop: model.cursorNearTop,
            cursorNearBottom: model.cursorNearBottom,
            showFrameStrip: model.showFrameStrip,
            frameStripVisible: model.showFrameStrip && model.hasAnimatedFrames,
            showThumbnailStrip: model.showThumbnailStrip,
            thumbnailStripVisible: model.navigableFiles.count > 1 && model.showThumbnailStrip && !model.isGridView,
            showStatusBar: model.settings.showStatusBar,
            statusBarVisible: model.settings.showStatusBar && !model.statusText.isEmpty,
            infoPanelWidth: model.isInfoPanelVisible ? 300 : 0
        )

        // ── Color picker mode ────────────────────────────────────
        nsView.isColorPickerMode = model.isColorPickerMode
        nsView.isColorPickerLocked = model.isColorPickerLocked

        // ── Crop mode — shared between animation and normal paths ──
        // Sync crop state from model to NSView (shared by animation and normal paths).
        syncCropMode(nsView: nsView, model: model)

        // Reclaim first responder after thumbnail/grid tap
        if model.needsCanvasFocus, let window = nsView.window, window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
            model.needsCanvasFocus = false
        }
    }

    /// Push crop state from the model to the NSView (shared by animation + normal paths).
    private func syncCropMode(nsView: ViewerNSView, model: ViewerModel) {
        nsView.isCropMode = model.isCropMode
        guard model.isCropMode else { return }
        nsView.cropLockedRatio = model.cropPreset.ratio
        if let img = model.decodedImage {
            nsView.cropImagePixelSize = CGSize(width: img.image.width, height: img.image.height)
        }
        // Sync crop rect from model → view (e.g. when preset changes)
        let viewRect = nsView.getCropRect()
        if abs(viewRect.origin.x - model.cropRect.origin.x) > 0.001 ||
           abs(viewRect.origin.y - model.cropRect.origin.y) > 0.001 ||
           abs(viewRect.width  - model.cropRect.width)  > 0.001 ||
           abs(viewRect.height - model.cropRect.height) > 0.001
        {
            nsView.setCropRect(model.cropRect)
        }
    }
}
