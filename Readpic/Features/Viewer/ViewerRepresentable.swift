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
        view.onEscape = {
            if model.showShortcutsHelp { model.showShortcutsHelp = false }
            else if model.isInfoPanelVisible { model.isInfoPanelVisible = false }
            else { model.closeWindow() }
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
        let nativeSize = model.decodedImage?.pixelSize ?? .zero
        let zoomMode = ZoomGeometry.Mode(from: model.zoomMode)

        // ── Animation frame ──────────────────────────────────────
        if model.isAnimating, let frames = model.decodedImage?.animatedFrames,
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
                thumbnailStripVisible: model.files.count > 1 && model.showThumbnailStrip && !model.isGridView,
                showStatusBar: model.settings.showStatusBar,
                statusBarVisible: model.settings.showStatusBar && !model.statusText.isEmpty,
                infoPanelWidth: model.isInfoPanelVisible ? 300 : 0
            )
            return
        }

        guard let displayImage = model.decodedImage?.image else {
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
            thumbnailStripVisible: model.files.count > 1 && model.showThumbnailStrip && !model.isGridView,
            showStatusBar: model.settings.showStatusBar,
            statusBarVisible: model.settings.showStatusBar && !model.statusText.isEmpty,
            infoPanelWidth: model.isInfoPanelVisible ? 300 : 0
        )

        // Reclaim first responder after thumbnail/grid tap
        if model.needsCanvasFocus, let window = nsView.window, window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
            model.needsCanvasFocus = false
        }
    }
}
