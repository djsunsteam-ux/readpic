import AppKit
import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class ViewerModel {
    enum ZoomMode: Equatable {
        case fitWindow
        case fitWidth
        case actualSize
    }

    enum ZoomAction: Equatable {
        case none
        case zoomIn
        case zoomOut
        case resetZoom
    }

    var files: [FileItem] = []
    var currentIndex: Int = 0
    var decodedImage: DecodedImage? {
        didSet {
            if oldValue?.url != decodedImage?.url {
                stopAnimation()
                startAnimation()
            }
        }
    }
    var metadata: ImageMetadata?
    var isInfoPanelVisible = false
    var showThumbnailStrip = true
    var isGridView = false
    var showShortcutsHelp = false
    var currentFrameIndex = 0
    var isAnimating = false
    var isAnimationPaused = false
    var zoomMode: ZoomMode = .fitWindow
    var zoomPercent: Int = 100
    var zoomAction: ZoomAction = .none
    var isDragTargeted = false
    var isLoading = false
    var errorMessage: String?
    var toastMessage: String?
    var toastActionTitle: String?
    var isFullScreen = false
    var cursorNearTop = false
    var cursorNearBottom = false
    var rotation: Int = 0
    var isFlippedHorizontally = false

    private let scanner = FolderScanner()
    private let decoder = ImageDecoder()
    private let metadataReader = MetadataReader()
    private let clipboardService = ClipboardService()
    private let finderService = FinderService()
    private let externalOpenService = ExternalOpenService()
    private let fileOperationService = FileOperationService()
    private var lastTrashedItem: TrashedFile?
    private var loadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?

    let settings = AppSettings()
    private var fullscreenObserver: Any?
    private var mouseMonitor: NSObjectProtocol?
    private var memorySource: DispatchSourceMemoryPressure?

    init() {
        MainActor.assumeIsolated {
            fullscreenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isFullScreen = true
                    self?.cursorNearTop = true
                    self?.startMouseMonitor()
                }
            }
            _ = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isFullScreen = false
                    self?.cursorNearTop = false
                    self?.cursorNearBottom = false
                    self?.stopMouseMonitor()
                }
            }

            let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
            source.setEventHandler { [weak self] in
                let pressure = source.data
                if pressure == .critical || pressure == .warning {
                    self?.handleMemoryWarning()
                } else if pressure == .normal {
                    self?.handleMemoryRestore()
                }
            }
            source.resume()
            memorySource = source

            // Proactive low memory mode on ≤8GB machines
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            if physicalMemory <= 8_589_934_592 { // 8 GB
                isLowMemoryMode = true
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let o = fullscreenObserver as? NSObjectProtocol {
                NotificationCenter.default.removeObserver(o)
            }
            memorySource?.cancel()
        }
    }

    private func startMouseMonitor() {
        stopMouseMonitor()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let loc = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) else { return }
                let top = screen.frame.maxY
                let bottom = screen.frame.minY
                self.cursorNearTop = loc.y >= top - 40
                self.cursorNearBottom = loc.y <= bottom + 26
            }
            return event
        }
        mouseMonitor = monitor as? NSObjectProtocol
    }

    private func handleMemoryWarning() {
        isLowMemoryMode = true
        ThumbnailCache.shared.halveCapacity()
        ImageCache.shared.clear()
        ThumbnailCache.shared.clear()
    }

    private func handleMemoryRestore() {
        guard ProcessInfo.processInfo.physicalMemory > 8_589_934_592 else { return }
        isLowMemoryMode = false
        ThumbnailCache.shared.restoreCapacity()
    }

    private func stopMouseMonitor() {
        guard let m = mouseMonitor else { return }
        NSEvent.removeMonitor(m)
        mouseMonitor = nil
    }

    var currentFile: FileItem? {
        guard files.indices.contains(currentIndex) else { return nil }
        return files[currentIndex]
    }

    var statusText: String {
        guard let currentFile else { return "" }
        let count = files.isEmpty ? 1 : files.count
        let dimensions: String
        if let decodedImage {
            dimensions = "\(Int(decodedImage.pixelSize.width)) × \(Int(decodedImage.pixelSize.height))"
        } else {
            dimensions = "Loading…"
        }
        let sizeStr = fileSizeString(currentFile.fileSize)
        return "\(currentIndex + 1) / \(count)    \(currentFile.name)    \(dimensions)    \(sizeStr)    \(zoomPercent)%"
    }

    private func fileSizeString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .jpeg, .png, .heic, .heif, .gif, .tiff, .bmp,
            UTType(filenameExtension: "webp")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if settings.rememberLastFolder, let lastURL = settings.lastFolderURL {
            panel.directoryURL = lastURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func showOpenFolderPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if settings.rememberLastFolder, let lastURL = settings.lastFolderURL {
            panel.directoryURL = lastURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func open(_ url: URL) {
        guard FolderScanner.supports(url) else {
            errorMessage = "Unsupported format"
            return
        }
        if settings.rememberLastFolder {
            settings.lastFolderURL = url.deletingLastPathComponent()
        }

        ImageCache.shared.clear()
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        currentProxyMaxPixelSize = 2048
        let mode = settings.sortMode
        loadTask = Task {
            do {
                async let scannedFiles = scanner.scanContainingFolder(for: url, sortMode: mode)
                async let decoded = Task.detached(priority: .userInitiated) {
                    try self.decoder.decode(url: url)
                }.value

                let items = try await scannedFiles
                let image = try await decoded

                guard !Task.isCancelled else { return }
                files = items.isEmpty ? [FileItem(url: url)] : items
                currentIndex = files.firstIndex { $0.url == url } ?? 0
                ImageCache.shared.set(image)
                decodedImage = image
                metadata = metadataReader.read(url: image.url, pixelSize: image.pixelSize)
                zoomMode = defaultZoomModeFromSettings
                isLoading = false
                preloadAdjacent()
            } catch {
                guard !Task.isCancelled else { return }
                files = [FileItem(url: url)]
                currentIndex = 0
                decodedImage = nil
                metadata = nil
                errorMessage = "The file is damaged and can’t be displayed"
                isLoading = false
            }
        }
    }

    func openFolder(_ url: URL) {
        if settings.rememberLastFolder {
            settings.lastFolderURL = url
        }
        currentProxyMaxPixelSize = 2048
        ImageCache.shared.clear()
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let mode = settings.sortMode
        loadTask = Task {
            do {
                let items = try await scanner.scanFolder(url, sortMode: mode)
                guard !Task.isCancelled else { return }
                guard let first = items.first else {
                    files = []
                    currentIndex = 0
                    decodedImage = nil
                    metadata = nil
                    errorMessage = "No supported images found"
                    isLoading = false
                    return
                }

                let image = try await Task.detached(priority: .userInitiated) {
                    try self.decoder.decode(url: first.url)
                }.value

                guard !Task.isCancelled else { return }
                files = items
                currentIndex = 0
                ImageCache.shared.set(image)
                decodedImage = image
                metadata = metadataReader.read(url: image.url, pixelSize: image.pixelSize)
                zoomMode = defaultZoomModeFromSettings
                isLoading = false
                preloadAdjacent()
            } catch {
                guard !Task.isCancelled else { return }
                files = []
                currentIndex = 0
                decodedImage = nil
                metadata = nil
                errorMessage = "The folder can’t be opened"
                isLoading = false
            }
        }
    }

    func showPrevious() {
        guard files.count > 1 else { return }
        currentIndex = max(currentIndex - 1, 0)
        loadCurrentImage()
    }

    func showNext() {
        guard files.count > 1 else { return }
        currentIndex = min(currentIndex + 1, files.count - 1)
        loadCurrentImage()
    }

    private func startAnimation() {
        stopAnimation()
        guard let frames = decodedImage?.animatedFrames, frames.count > 1 else { return }
        isAnimating = true
        isAnimationPaused = false
        currentFrameIndex = 0
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = frames[self.currentFrameIndex].delay
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if self.isAnimationPaused { continue }
                await MainActor.run {
                    guard !self.isAnimationPaused else { return }
                    self.currentFrameIndex = (self.currentFrameIndex + 1) % frames.count
                }
            }
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isAnimating = false
        isAnimationPaused = false
        currentFrameIndex = 0
    }

    func toggleAnimationPause() {
        guard isAnimating else { return }
        isAnimationPaused.toggle()
    }

    func selectFile(at index: Int) {
        guard files.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadCurrentImage()
    }

    func toggleZoomMode() {
        zoomMode = zoomMode == .fitWindow ? .actualSize : .fitWindow
    }

    func setFitMode() {
        zoomMode = .fitWindow
    }

    func setFitWidthMode() {
        zoomMode = .fitWidth
    }

    func setActualSizeMode() {
        zoomMode = .actualSize
    }

    func setSortMode(_ mode: SortMode) {
        settings.sortMode = mode
        guard !files.isEmpty, let first = files.first else { return }
        open(first.url)
    }

    func updateZoomPercent(_ percent: Int) {
        zoomPercent = percent
    }

    func zoomIn() { zoomAction = .zoomIn }
    func zoomOut() { zoomAction = .zoomOut }
    func resetZoom() { zoomAction = .resetZoom }

    func rotateLeft() {
        rotation = (rotation - 90 + 360) % 360
    }

    func rotateRight() {
        rotation = (rotation + 90) % 360
    }

    func flipHorizontal() {
        isFlippedHorizontally.toggle()
    }

    func resetRotation() {
        rotation = 0
        isFlippedHorizontally = false
    }

    func closeWindow() {
        NSApp.keyWindow?.close()
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    func setDragTargeted(_ isTargeted: Bool) {
        isDragTargeted = isTargeted
    }

    func toggleInfoPanel() {
        isInfoPanelVisible.toggle()
    }

    func requestHigherResolution() {
        guard let currentFile, let currentImage = decodedImage else { return }
        let currentProxy = max(currentImage.pixelSize.width, currentImage.pixelSize.height)
        // In low memory mode, cap at a moderate resolution to avoid OOM
        let higherRes = isLowMemoryMode ? min(currentProxy * 1.5, 4096) : currentProxy * 2

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, let image = try? self.decoder.decode(url: currentFile.url, maxPixelSize: higherRes) else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                ImageCache.shared.set(image)
                self.decodedImage = image
                self.currentProxyMaxPixelSize = higherRes
            }
        }
    }

    /// Tracks the proxy decode size for the current image (used by ViewerNSView adaptive zoom).
    var currentProxyMaxPixelSize: CGFloat = 2048

    func toggleThumbnailStrip() {
        showThumbnailStrip.toggle()
    }

    func toggleGridView() {
        isGridView.toggle()
        if isGridView {
            stopAnimation()
        } else {
            startAnimation()
        }
    }

    func toggleShortcutsHelp() {
        showShortcutsHelp.toggle()
    }

    func openFromGrid(at index: Int) {
        guard files.indices.contains(index) else { return }
        isGridView = false
        currentIndex = index
        loadCurrentImage()
    }

    func copyFilePath() {
        guard let url = currentFile?.url else { return }
        clipboardService.copyFilePath(url)
        showToast("Path copied")
    }

    func copyImage() {
        guard let image = decodedImage?.image else { return }
        clipboardService.copyImage(image)
        showToast("Image copied")
    }

    func copyFile() {
        guard let url = currentFile?.url else { return }
        clipboardService.copyFile(url)
        showToast("File copied")
    }

    func revealInFinder() {
        guard let url = currentFile?.url else { return }
        finderService.reveal(url)
        showToast("Revealed in Finder")
    }

    func openExternally() {
        guard let url = currentFile?.url else { return }
        externalOpenService.open(url)
    }

    func moveCurrentFileToTrash() {
        guard let currentFile else { return }

        do {
            let trashedFile = try fileOperationService.moveToTrash(currentFile.url)
            lastTrashedItem = trashedFile
            files.remove(at: currentIndex)

            if files.isEmpty {
                currentIndex = 0
                decodedImage = nil
                metadata = nil
                isLoading = false
            } else {
                currentIndex = min(currentIndex, files.count - 1)
                loadCurrentImage()
            }

            showToast("Moved to Trash", actionTitle: "Undo")
        } catch {
            showToast("Couldn’t move to Trash")
        }
    }

    func undoTrash() {
        guard let lastTrashedItem else { return }

        do {
            try fileOperationService.restore(lastTrashedItem)
            self.lastTrashedItem = nil
            showToast("Restored")
            open(lastTrashedItem.originalURL)
        } catch {
            showToast("Couldn’t restore file")
        }
    }

    func performToastAction() {
        if toastActionTitle == "Undo" {
            undoTrash()
        }
    }

    private func showToast(_ message: String, actionTitle: String? = nil) {
        toastTask?.cancel()
        toastMessage = message
        toastActionTitle = actionTitle
        toastTask = Task {
            try? await Task.sleep(for: actionTitle == nil ? .seconds(2) : .seconds(5))
            guard !Task.isCancelled else { return }
            toastMessage = nil
            toastActionTitle = nil
        }
    }

    private var defaultZoomModeFromSettings: ZoomMode {
        switch settings.defaultZoomMode {
        case .fitWindow: .fitWindow
        case .fitWidth: .fitWidth
        case .actualSize: .actualSize
        }
    }

    private func loadCurrentImage() {
        guard let currentFile else { return }
        loadTask?.cancel()

        if let cached = ImageCache.shared.get(currentFile.url) {
            decodedImage = cached
            metadata = metadataReader.read(url: cached.url, pixelSize: cached.pixelSize)
            zoomMode = defaultZoomModeFromSettings
            isLoading = false
            preloadAdjacent()
            return
        }

        currentProxyMaxPixelSize = 2048
        isLoading = true
        errorMessage = nil

        loadTask = Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try self.decoder.decode(url: currentFile.url)
                }.value

                guard !Task.isCancelled else { return }
                ImageCache.shared.set(image)
                decodedImage = image
                metadata = metadataReader.read(url: image.url, pixelSize: image.pixelSize)
                zoomMode = defaultZoomModeFromSettings
                isLoading = false
                preloadAdjacent()
            } catch {
                guard !Task.isCancelled else { return }
                decodedImage = nil
                metadata = nil
                errorMessage = "The file is damaged and can’t be displayed"
                isLoading = false
            }
        }
    }

    private func preloadAdjacent() {
        let decoder = self.decoder
        let indices = [currentIndex - 1, currentIndex + 1].filter { files.indices.contains($0) }
        for i in indices {
            let file = files[i]
            guard ImageCache.shared.get(file.url) == nil else { continue }
            Task.detached(priority: .low) {
                guard let image = try? decoder.decode(url: file.url) else { return }
                await MainActor.run { ImageCache.shared.set(image) }
            }
        }
    }
}
