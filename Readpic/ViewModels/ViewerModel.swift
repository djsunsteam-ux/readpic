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
                showFrameStrip = false
            }
            stopAnimation()
            startAnimation()
        }
    }
    var metadata: ImageMetadata?
    var isInfoPanelVisible = false
    var showThumbnailStrip = true
    var isGridView = false
    var selectedGridIndices: Set<Int> = []
    var lastGridClickedIndex: Int = 0
    /// Saved before bulk operations (Select All / Invert) so we can restore
    /// the scroll anchor when deselected.
    private var selectionAnchorIndex: Int = 0
    var showShortcutsHelp = false
    var currentFrameIndex = 0
    var isAnimating = false
    var isAnimationPaused = false
    var zoomMode: ZoomMode = .fitWindow
    var zoomPercent: Int = 100
    var zoomAction: ZoomAction = .none
    var isDragTargeted = false
    var isLoading = false
    var toastMessage: String?
    var toastActionTitle: String?
    var isFullScreen = false
    var cursorNearTop = false
    var cursorNearBottom = false
    var rotation: Int = 0
    var isFlippedHorizontally = false
    var needsCanvasFocus = false
    var showFrameStrip = false
    var showExportPanel = false
    var showBatchExportPanel = false

    weak var window: NSWindow?

    private let scanner = FolderScanner()
    private let decoder = ImageDecoder()
    private let metadataReader = MetadataReader()
    private let clipboardService = ClipboardService()
    private let finderService = FinderService()
    private let externalOpenService = ExternalOpenService()
    private let fileOperationService = FileOperationService()
    private var lastTrashRecord: (file: TrashedFile, index: Int)?
    private var loadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    /// Background preload chain for higher-resolution proxies of the current image.
    private var preloadTask: Task<Void, Never>?

    /// Serializes decodes — only one runs at a time regardless of navigation speed.
    /// This bounds concurrent memory to a single decode's buffer.
    private let decodeQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

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
        preloadTask?.cancel()
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

    /// Whether the current file is marked as a favorite.
    var isCurrentFileFavorite: Bool {
        guard let url = currentFile?.url else { return false }
        return FavoritesManager.shared.isFavorite(url)
    }

    /// Current file's rating (0 = unrated, 1-5 = stars).
    var currentFileRating: Int {
        guard let url = currentFile?.url else { return 0 }
        return FavoritesManager.shared.rating(for: url)
    }

    /// Status text shown in the bottom status bar.
    /// - Grid mode with selection: shows selection count.
    /// - Viewer mode: shows file info as before.
    var statusText: String {
        if isGridView {
            if selectedGridIndices.isEmpty {
                return "\(files.count) images"
            } else {
                return "\(selectedGridIndices.count) of \(files.count) selected"
            }
        }
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
            UTType(filenameExtension: "ico")!,
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
            showToast("Unsupported format")
            return
        }
        if settings.rememberLastFolder {
            settings.lastFolderURL = url.deletingLastPathComponent()
        }

        ImageCache.shared.clear()
        loadTask?.cancel()
        preloadTask?.cancel()
        isGridView = false
        isLoading = true
        currentProxyMaxPixelSize = 2048
        loadTask = Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try self.decoder.decode(url: url)
                }.value

                guard !Task.isCancelled else { return }
                files = [FileItem(url: url)]
                fileListVersion &+= 1
                currentIndex = 0
                ImageCache.shared.set(image)
                decodedImage = image
                metadata = metadataReader.read(url: image.url, pixelSize: image.pixelSize)
                zoomMode = defaultZoomModeFromSettings
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                files = [FileItem(url: url)]
                fileListVersion &+= 1
                currentIndex = 0
                decodedImage = nil
                metadata = nil
                showToast("The file is damaged and can’t be displayed")
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
        preloadTask?.cancel()
        isLoading = true
        let mode = settings.sortMode
        loadTask = Task {
            do {
                let items = try await scanner.scanFolder(url, sortMode: mode)
                guard !Task.isCancelled else { return }
                guard let first = items.first else {
                    files = []
                    fileListVersion &+= 1
                    currentIndex = 0
                    decodedImage = nil
                    metadata = nil
                    showToast("No supported images found")
                    isLoading = false
                    return
                }

                let image = try await Task.detached(priority: .userInitiated) {
                    try self.decoder.decode(url: first.url)
                }.value

                guard !Task.isCancelled else { return }
                files = items
                fileListVersion &+= 1
                isGridView = items.count > 1
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
                fileListVersion &+= 1
                currentIndex = 0
                decodedImage = nil
                metadata = nil
                showToast("The folder can’t be opened")
                isLoading = false
            }
        }
    }

    func showPrevious() {
        guard files.count > 1 else { return }
        currentIndex = max(currentIndex - 1, 0)
        resetRotation()
        loadCurrentImage()
    }

    func showNext() {
        guard files.count > 1 else { return }
        currentIndex = min(currentIndex + 1, files.count - 1)
        resetRotation()
        loadCurrentImage()
        needsCanvasFocus = true
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

    func selectFrame(at index: Int) {
        guard let frames = decodedImage?.animatedFrames, frames.indices.contains(index) else { return }
        isAnimationPaused = true
        currentFrameIndex = index
    }

    func selectFile(at index: Int) {
        guard files.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        resetRotation()
        loadCurrentImage()
        needsCanvasFocus = true
    }

    func toggleZoomMode() {
        zoomMode = zoomMode == .fitWindow ? .actualSize : .fitWindow
    }

    func setFitMode() {
        zoomMode = .fitWindow
        zoomAction = .resetZoom
    }

    func setFitWidthMode() {
        zoomMode = .fitWidth
        zoomAction = .resetZoom
    }

    func setActualSizeMode() {
        zoomMode = .actualSize
        zoomAction = .resetZoom
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
        rotation = (rotation + 90) % 360
    }

    func rotateRight() {
        rotation = (rotation - 90 + 360) % 360
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
        (window ?? NSApp.keyWindow)?.toggleFullScreen(nil)
    }

    func setDragTargeted(_ isTargeted: Bool) {
        isDragTargeted = isTargeted
    }

    func toggleInfoPanel() {
        isInfoPanelVisible.toggle()
    }

    func requestHigherResolution() {
        guard let currentFile, let currentDecoded = decodedImage else { return }
        // Animated images are already at their native resolution — frames don't benefit
        // from upscaling, and re-decoding would lose animatedFrames.
        guard currentDecoded.animatedFrames == nil else { return }

        let nativeMax = max(currentDecoded.pixelSize.width, currentDecoded.pixelSize.height)
        let nextRes = min(currentProxyMaxPixelSize * 2, nativeMax)
        guard nextRes > currentProxyMaxPixelSize else { return }

        // Preloaded version already sitting in cache?
        if let cached = ImageCache.shared.get(currentFile.url),
           cached.animatedFrames == nil {
            let cachedMax = max(cached.pixelSize.width, cached.pixelSize.height)
            if cachedMax >= nextRes {
                decodedImage = cached
                currentProxyMaxPixelSize = nextRes
                return
            }
        }

        // Fall back to on-demand decode
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, let image = try? self.decoder.decode(url: currentFile.url, maxPixelSize: nextRes) else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                ImageCache.shared.set(image)
                self.decodedImage = image
                self.currentProxyMaxPixelSize = nextRes
            }
        }
    }

    /// Tracks the proxy decode size for the current image (used by ViewerNSView adaptive zoom).
    var currentProxyMaxPixelSize: CGFloat = 2048
    /// Incremented whenever `files` changes to force thumbnail strip / grid rebuild.
    var fileListVersion: UInt = 0

    func toggleThumbnailStrip() {
        showThumbnailStrip.toggle()
    }

    func toggleFrameStrip() {
        showFrameStrip.toggle()
    }

    /// Whether the current image has animation frames (GIF etc.)
    var hasAnimatedFrames: Bool {
        guard let frames = decodedImage?.animatedFrames else { return false }
        return frames.count > 1
    }

    func toggleGridView() {
        isGridView.toggle()
        if isGridView {
            selectedGridIndices.removeAll()
            stopAnimation()
        } else {
            selectedGridIndices.removeAll()
            startAnimation()
        }
    }

    func toggleShortcutsHelp() {
        showShortcutsHelp.toggle()
    }

    func selectInGrid(at index: Int) {
        guard files.indices.contains(index) else { return }
        selectedGridIndices = [index]
        lastGridClickedIndex = index
        let file = files[index]
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let meta = self.metadataReader.read(url: file.url, pixelSize: .zero)
            await MainActor.run {
                guard self.selectedGridIndices.contains(index) else { return }
                self.metadata = meta
            }
        }
    }

    func gridSelectPrevious() {
        let idx = selectedGridIndices.first ?? currentIndex
        guard idx > 0 else { return }
        selectInGrid(at: idx - 1)
    }

    func gridSelectNext() {
        let idx = selectedGridIndices.first ?? currentIndex
        guard idx < files.count - 1 else { return }
        selectInGrid(at: idx + 1)
    }

    func gridSelectUp(columns: Int) {
        let idx = selectedGridIndices.first ?? currentIndex
        let target = idx - columns
        if files.indices.contains(target) {
            selectInGrid(at: target)
        }
    }

    func gridSelectDown(columns: Int) {
        let idx = selectedGridIndices.first ?? currentIndex
        let target = idx + columns
        if files.indices.contains(target) {
            selectInGrid(at: target)
        }
    }

    func openFromGrid(at index: Int) {
        guard files.indices.contains(index) else { return }
        selectedGridIndices.removeAll()
        isGridView = false
        currentIndex = index
        resetRotation()
        loadCurrentImage()
        needsCanvasFocus = true
    }

    // MARK: - Multi-Select

    func toggleGridSelection(at index: Int) {
        guard files.indices.contains(index) else { return }
        if selectedGridIndices.contains(index) {
            selectedGridIndices.remove(index)
        } else {
            selectedGridIndices.insert(index)
        }
        lastGridClickedIndex = index
        // Update metadata preview for the last interacted item
        updateMetadataForLastSelection()
    }

    func selectGridRange(from: Int, to: Int) {
        let lower = min(from, to)
        let upper = max(from, to)
        let range = (lower...upper).filter { files.indices.contains($0) }
        selectedGridIndices.formUnion(range)
        lastGridClickedIndex = to
        updateMetadataForLastSelection()
    }

    /// Toggle select all / deselect all.
    /// If all files are already selected -> deselect all (restoring the scroll
    /// anchor to the last single-selected index before the bulk operation).
    /// Otherwise -> select all.
    func selectAllGrid() {
        if selectedGridIndices.count == files.count {
            selectedGridIndices.removeAll()
            // Restore selection to the anchor so the grid scrolls back
            selectedGridIndices.insert(selectionAnchorIndex)
            lastGridClickedIndex = selectionAnchorIndex
            updateMetadataForLastSelection()
        } else {
            // Save anchor before bulk-selecting
            selectionAnchorIndex = selectedGridIndices.sorted().first ?? currentIndex
            selectedGridIndices = Set(files.indices)
            if let last = files.indices.last {
                lastGridClickedIndex = last
            }
            updateMetadataForLastSelection()
        }
    }

    func deselectAllGrid() {
        selectedGridIndices.removeAll()
        metadata = nil
    }

    /// Invert current selection.
    func invertGridSelection() {
        // Save anchor before inverting
        if let first = selectedGridIndices.sorted().first {
            selectionAnchorIndex = first
        } else {
            selectionAnchorIndex = currentIndex
        }
        let all = Set(files.indices)
        selectedGridIndices = all.subtracting(selectedGridIndices)
        if let first = selectedGridIndices.sorted().first {
            lastGridClickedIndex = first
            updateMetadataForLastSelection()
        } else {
            // Restore anchor if inversion left nothing selected
            selectedGridIndices.insert(selectionAnchorIndex)
            lastGridClickedIndex = selectionAnchorIndex
            updateMetadataForLastSelection()
        }
    }

    private func updateMetadataForLastSelection() {
        guard let lastIdx = selectedGridIndices.sorted().last,
              files.indices.contains(lastIdx) else {
            metadata = nil
            return
        }
        let file = files[lastIdx]
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let meta = self.metadataReader.read(url: file.url, pixelSize: .zero)
            await MainActor.run {
                guard self.selectedGridIndices.contains(lastIdx) else { return }
                self.metadata = meta
            }
        }
    }

    private var activeFile: FileItem? {
        if isGridView, let first = selectedGridIndices.sorted().first, files.indices.contains(first) {
            return files[first]
        }
        return currentFile
    }

    /// All selected files in grid mode (for multi-select operations).
    var selectedFiles: [FileItem] {
        guard isGridView else {
            return currentFile.map { [$0] } ?? []
        }
        return selectedGridIndices.sorted().compactMap { files.indices.contains($0) ? files[$0] : nil }
    }

    func copyFilePath() {
        guard let url = activeFile?.url else { return }
        clipboardService.copyFilePath(url)
        showToast("Path copied")
    }

    func exportMetadata() {
        guard let meta = metadata else { return }
        let content = meta.exportText

        let panel = NSSavePanel()
        panel.title = "Export Metadata"
        panel.nameFieldStringValue = "\(meta.name).metadata.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            showToast("Metadata exported")
        } catch {
            showToast("Failed to export")
        }
    }

    // MARK: - Favorites & Ratings

    func toggleFavorite() {
        guard let url = currentFile?.url else { return }
        FavoritesManager.shared.toggleFavorite(url)
        // Trigger Observation update by notifying all key paths
        // that depend on the current file's favorite status.
        showToast(FavoritesManager.shared.isFavorite(url) ? "Added to Favorites" : "Removed from Favorites")
    }

    func rateCurrentFile(_ rating: Int) {
        guard let url = currentFile?.url else { return }
        FavoritesManager.shared.setRating(rating, for: url)
        if rating > 0 {
            showToast("Rated \(rating) ★")
        } else {
            showToast("Rating cleared")
        }
    }

    // MARK: - Export / Save Changes

    /// URL of the file to export — respects grid selection, falls back to current file.
    var exportFileURL: URL? {
        if isGridView {
            if let first = selectedGridIndices.sorted().first,
               files.indices.contains(first) {
                return files[first].url
            }
            // No explicit selection — use the current file (highlighted in grid)
            return currentFile?.url
        }
        return currentFile?.url
    }

    func showExport() {
        guard exportFileURL != nil else {
            showToast("No image to export")
            return
        }
        showExportPanel = true
    }

    func showBatchExport() {
        guard isGridView, selectedGridIndices.count >= 2 else {
            showToast("Select at least 2 files")
            return
        }
        showBatchExportPanel = true
    }

    func saveChanges() {
        guard let decodedImage, let currentFile else {
            showToast("No image to save")
            return
        }

        guard rotation != 0 || isFlippedHorizontally else {
            showToast("No changes to save")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save changes to original file?"
        alert.informativeText = "This will overwrite \"\(currentFile.name)\" with the rotated/flipped version."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let image = await MainActor.run { decodedImage.image }
            let rot = await MainActor.run { self.rotation }
            let flip = await MainActor.run { self.isFlippedHorizontally }
            let url = await MainActor.run { currentFile.url }
            let fmt = ImageWriter.SaveFormat.from(url: url)

            guard let transformed = ImageWriter.applyTransform(
                to: image, rotation: rot, isFlipped: flip
            ) else {
                await MainActor.run { self.showToast("Failed to process image") }
                return
            }

            guard ImageWriter.write(transformed, to: url, format: fmt) else {
                await MainActor.run { self.showToast("Failed to save changes") }
                return
            }

            await MainActor.run {
                // Invalidate all caches so the rewritten file is re-decoded fresh
                ImageCache.shared.remove(url)
                ThumbnailCache.shared.remove(url)
                ThumbnailDiskCache.shared.remove(key: ThumbnailCacheKey(url: url))

                self.rotation = 0
                self.isFlippedHorizontally = false
                self.fileListVersion &+= 1  // force grid / strip rebuild
                self.loadCurrentImage()
                self.showToast("Changes saved")
            }
        }
    }

    // MARK: - Clipboard

    func copyImage() {
        guard let image = decodedImage?.image else { return }
        clipboardService.copyImage(image)
        showToast("Image copied")
    }

    func copyFile() {
        guard let url = activeFile?.url else { return }
        clipboardService.copyFile(url)
        showToast("File copied")
    }

    func revealInFinder() {
        guard let url = activeFile?.url else { return }
        finderService.reveal(url)
        showToast("Revealed in Finder")
    }

    func openExternally() {
        guard let url = activeFile?.url else { return }
        externalOpenService.open(url)
    }

    func moveCurrentFileToTrash() {
        guard let file = activeFile, let idx = files.firstIndex(where: { $0.url == file.url }) else { return }

        do {
            let trashedFile = try fileOperationService.moveToTrash(file.url)
            lastTrashRecord = (trashedFile, idx)
            files.remove(at: idx)
            fileListVersion &+= 1

            if isGridView {
                if files.isEmpty {
                    selectedGridIndices.removeAll()
                    metadata = nil
                } else {
                    // Adjust selection after deletion
                    if !selectedGridIndices.isEmpty {
                        let sorted = selectedGridIndices.sorted()
                        let newSet = Set(sorted.map { min($0, files.count - 1) }.filter { files.indices.contains($0) })
                        selectedGridIndices = newSet
                        if let first = selectedGridIndices.sorted().first {
                            selectInGrid(at: first)
                        }
                    }
                }
            } else {
                if files.isEmpty {
                    currentIndex = 0
                    decodedImage = nil
                    metadata = nil
                    isLoading = false
                } else {
                    currentIndex = min(currentIndex, files.count - 1)
                    loadCurrentImage()
                }
            }

            showToast("Moved to Trash", actionTitle: "Undo")
        } catch {
            showToast("Couldn’t move to Trash")
        }
    }

    func undoTrash() {
        guard let record = lastTrashRecord else { return }

        do {
            try fileOperationService.restore(record.file)
            lastTrashRecord = nil

            // Re-insert the file into the folder list and re-sort
            let restoredItem = FileItem(url: record.file.originalURL)
            files.append(restoredItem)
            files = FileSorter.sort(files, by: settings.sortMode)
            fileListVersion &+= 1

            if let newIdx = files.firstIndex(where: { $0.url == record.file.originalURL }) {
                currentIndex = newIdx
                loadCurrentImage()
            }

            showToast("Restored")

            // Pre-cache thumbnail so ThumbnailStripView finds it immediately
            // even if LazyHStack recycles a cell without re-firing .task.
            Task.detached(priority: .utility) {
                _ = await ThumbnailLoader.load(url: record.file.originalURL)
            }
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
        preloadTask?.cancel()

        if let cached = ImageCache.shared.get(currentFile.url) {
            decodedImage = cached
            metadata = metadataReader.read(url: cached.url, pixelSize: cached.pixelSize)
            zoomMode = defaultZoomModeFromSettings
            isLoading = false
            preloadAdjacent()
            preloadHigherResolutions()
            return
        }

        currentProxyMaxPixelSize = 2048
        isLoading = true
        // Cancel any pending decode — the serial queue bounds concurrent memory.
        decodeQueue.cancelAllOperations()

        loadTask = Task {
            let image: DecodedImage
            do {
                image = try await withCheckedThrowingContinuation { continuation in
                    let op = BlockOperation {
                        do {
                            let result = try self.decoder.decode(url: currentFile.url)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    decodeQueue.addOperation(op)
                }
            } catch {
                guard !Task.isCancelled else { return }
                decodedImage = nil
                metadata = nil
                showToast("The file is damaged and can’t be displayed")
                isLoading = false
                return
            }

            guard !Task.isCancelled else { return }
            ImageCache.shared.set(image)
            decodedImage = image
            metadata = metadataReader.read(url: image.url, pixelSize: image.pixelSize)
            zoomMode = defaultZoomModeFromSettings
            isLoading = false
            preloadAdjacent()
            preloadHigherResolutions()
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

    /// Start background preloading higher-resolution proxies for the current image.
    ///
    /// Each step doubles the proxy resolution and stores the result in `ImageCache`
    /// (replacing the previous entry for the same URL). When the user zooms past the
    /// stretch cap, `requestHigherResolution()` finds the pre-decoded level in cache
    /// instantly — no decode-induced stutter during zoom.
    private func preloadHigherResolutions() {
        guard let currentFile, let currentDecoded = decodedImage else { return }
        // Preloading animated images is destructive: re-decoding loses animatedFrames.
        // GIF/APNG frames are already at their native resolution.
        guard currentDecoded.animatedFrames == nil else { return }

        let nativeMax = max(currentDecoded.pixelSize.width, currentDecoded.pixelSize.height)
        let startSize = currentProxyMaxPixelSize

        preloadTask?.cancel()
        preloadTask = Task.detached(priority: .low) { [weak self] in
            var size = startSize
            // Low memory: only 1 level ahead. Normal: up to 3 levels (2×, 4×, 8×).
            let maxLevels = isLowMemoryMode ? 1 : 3
            let url = currentFile.url
            let decoder = self?.decoder

            for _ in 0..<maxLevels {
                guard !Task.isCancelled else { break }

                let nextSize = min(size * 2, nativeMax)
                guard nextSize > size else { break }

                guard let d = decoder,
                      let image = try? d.decode(url: url, maxPixelSize: nextSize)
                else { break }

                let proceed = await MainActor.run {
                    guard let self, !Task.isCancelled else { return false }
                    // Only store if still viewing the same image
                    guard self.currentFile?.url == url else { return false }
                    ImageCache.shared.set(image)
                    return true
                }

                guard proceed else { break }
                size = nextSize
            }
        }
    }
}
