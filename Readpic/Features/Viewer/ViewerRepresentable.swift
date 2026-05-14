import AppKit
import SwiftUI

struct ViewerRepresentable: NSViewRepresentable {
    let model: ViewerModel

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
        view.onEscape = {
            if model.showShortcutsHelp { model.showShortcutsHelp = false }
            else if model.isInfoPanelVisible { model.isInfoPanelVisible = false }
            else if model.isGridView { model.isGridView = false }
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
        let frameIndex = model.currentFrameIndex
        if model.isAnimating, let frames = model.decodedImage?.animatedFrames, frameIndex < frames.count {
            nsView.setAnimatedFrame(frames[frameIndex].image)
        } else {
            nsView.setImage(model.decodedImage?.image, zoomMode: model.zoomMode)
        }
        nsView.setProxyMaxPixelSize(model.currentProxyMaxPixelSize)
        nsView.setRotation(model.rotation, flipped: model.isFlippedHorizontally)
        nsView.scrollBehavior = model.settings.scrollBehavior
        switch model.zoomAction {
        case .zoomIn:     nsView.zoomIn()
        case .zoomOut:    nsView.zoomOut()
        case .resetZoom:  nsView.resetZoom()
        case .none:       break
        }
        if model.zoomAction != .none {
            Task { @MainActor in model.zoomAction = .none }
        }
    }
}
