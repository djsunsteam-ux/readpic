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

    enum DateFilter: String, CaseIterable, Sendable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case thisYear = "This Year"

        func matches(_ date: Date?) -> Bool {
            guard self != .all, let date else { return false }
            let cal = Calendar.current
            switch self {
            case .today:
                return cal.isDateInToday(date)
            case .thisWeek:
                return cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
            case .thisMonth:
                return cal.isDate(date, equalTo: Date(), toGranularity: .month)
            case .thisYear:
                return cal.isDate(date, equalTo: Date(), toGranularity: .year)
            case .all:
                return true
            }
        }
    }

    enum FileFormatFilter: String, CaseIterable, Sendable {
        case all = "All"
        case jpeg = "JPEG"
        case png  = "PNG"
        case heic = "HEIC"
        case webp = "WebP"
        case gif  = "GIF"
        case tiff = "TIFF"
        case bmp  = "BMP"
        case ico  = "ICO"
        case raw  = "RAW"
        case avif = "AVIF"
        case jxl  = "JPEG XL"
        case svg  = "SVG"
        case psd  = "PSD"

        func matches(_ url: URL) -> Bool {
            guard self != .all else { return true }
            let ext = url.pathExtension.lowercased()
            switch self {
            case .jpeg: return ["jpg", "jpeg"].contains(ext)
            case .tiff: return ["tif", "tiff"].contains(ext)
            case .heic: return ["heic", "heif"].contains(ext)
            case .ico:  return ext == "ico"
            case .raw:  return ["cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf", "srw", "pef", "srf", "sr2", "3fr", "fff", "x3f", "mef", "mos"].contains(ext)
            case .avif: return ext == "avif"
            case .jxl:  return ext == "jxl"
            case .svg:  return ext == "svg"
            case .psd:  return ["psd", "psb"].contains(ext)
            default:    return ext == rawValue.lowercased()
            }
        }
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
    /// Total pixel height of bottom bars (frame-strip + thumbnail-strip + status-bar).
    /// Returns 0 when bars are hidden (fullscreen with cursor not near bottom).
    /// Used by both ViewerNSView (bar insets) and InfoPanelView (scroll padding).
    var bottomBarsTotalHeight: CGFloat {
        guard !(isFullScreen && !cursorNearTop && !cursorNearBottom) else { return 0 }
        var height: CGFloat = 0
        if showFrameStrip && hasAnimatedFrames && !isGridView { height += 56 }
        if showThumbnailStrip && files.count > 1 && !isGridView { height += 64 }
        if settings.showStatusBar && !statusText.isEmpty { height += 26 }
        return height
    }
    var rotation: Int = 0
    var isFlippedHorizontally = false
    var needsCanvasFocus = false
    var needsGridScroll: UInt = 0
    var showFrameStrip = false
    var searchText = ""
    var formatFilter: FileFormatFilter = .all
    var dateFilter: DateFilter = .all
    /// Files matching current search text and format filter.
    var filteredFiles: [FileItem] {
        var result = files
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if formatFilter != .all {
            result = result.filter { formatFilter.matches($0.url) }
        }
        if dateFilter != .all {
            result = result.filter { dateFilter.matches($0.modificationDate) }
        }
        return result
    }
    var isFilterActive: Bool {
        !searchText.isEmpty || formatFilter != .all || dateFilter != .all
    }
    /// Indices into `files` that match the current filter.
    var filteredIndices: [Int] {
        files.indices.filter { i in
            let f = files[i]
            if !searchText.isEmpty, !f.name.localizedCaseInsensitiveContains(searchText) { return false }
            if formatFilter != .all, !formatFilter.matches(f.url) { return false }
            if dateFilter != .all, !dateFilter.matches(f.modificationDate) { return false }
            return true
        }
    }
    /// Files available for navigation — filtered list when filter active, full list otherwise.
    var navigableFiles: [FileItem] {
        isFilterActive ? filteredFiles : files
    }
    /// Current index within `navigableFiles`.
    var navigableIndex: Int {
        guard let url = currentFile?.url else { return 0 }
        return navigableFiles.firstIndex(where: { $0.url == url }) ?? 0
    }
    var showExportPanel = false
    var showBatchExportPanel = false
    var showBatchRenamePanel = false
    var isSlideshowActive = false
    var slideshowInterval: TimeInterval = 3.0
    var slideshowTransition: SlideshowTransition = .dissolve
    private var slideshowTask: Task<Void, Never>?
    private var wasThumbnailStripVisibleBeforeSlideshow = true
    var isCropMode = false
    /// Normalized crop rect in image pixel space (0…1).
    var cropRect: CGRect = .init(x: 0, y: 0, width: 1, height: 1)
    var cropPreset: CropPreset = .free
    /// When cropping a GIF, the selected frame to display (nil = use proxy).
    var cropFrameImage: CGImage?
    /// Remembered thumbnail strip state for restore on crop exit.
    private var wasThumbnailStripVisibleBeforeCrop = true
    /// Remembered grid mode state — restore on crop cancel.
    private var wasInGridViewBeforeCrop = false

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
                    if self?.isGridView == true { self?.needsGridScroll &+= 1 }
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
            let filteredCount = filteredIndices.count
            let totalCount = files.count
            let filterSuffix = isFilterActive ? " (filtered from \(totalCount))" : ""
            if selectedGridIndices.isEmpty {
                return "\(filteredCount) images\(filterSuffix)"
            } else {
                return "\(selectedGridIndices.count) of \(filteredCount) selected\(filterSuffix)"
            }
        }
        guard let currentFile else { return "" }
        let nav = navigableFiles
        let count = nav.isEmpty ? 1 : nav.count
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
                // Serialise through decodeQueue so concurrent opens don't blow memory
                let image: DecodedImage
                do {
                    image = try await withCheckedThrowingContinuation { continuation in
                        let urlCopy = url
                        let op = BlockOperation {
                            do {
                                let result = try self.decoder.decode(url: urlCopy)
                                continuation.resume(returning: result)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                        decodeQueue.addOperation(op)
                    }
                } catch {
                    throw error
                }

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

    /// Rescan the folder containing the current files, preserving the current selection.
    func rescanCurrentFolder() {
        guard let first = files.first else { return }
        let folderURL = first.url.deletingLastPathComponent()
        openFolder(folderURL)
    }

    func openFolder(_ url: URL) {
        settings.addRecentFolder(url)
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

                // Serialise through decodeQueue so concurrent opens don't blow memory
                let image: DecodedImage
                do {
                    let firstURL = first.url
                    image = try await withCheckedThrowingContinuation { continuation in
                        let op = BlockOperation {
                            do {
                                let result = try self.decoder.decode(url: firstURL)
                                continuation.resume(returning: result)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                        decodeQueue.addOperation(op)
                    }
                } catch {
                    throw error
                }

                guard !Task.isCancelled else { return }
                files = items
                fileListVersion &+= 1
                isGridView = items.count > 1
                currentIndex = 0
                selectedGridIndices = [0]
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
        let nav = navigableFiles
        guard nav.count > 1, let url = currentFile?.url,
              let idx = nav.firstIndex(where: { $0.url == url }), idx > 0 else { return }
        guard let targetIdx = files.firstIndex(where: { $0.url == nav[idx - 1].url }) else { return }
        currentIndex = targetIdx
        resetRotation()
        loadCurrentImage()
    }

    func showNext() {
        let nav = navigableFiles
        guard nav.count > 1, let url = currentFile?.url,
              let idx = nav.firstIndex(where: { $0.url == url }), idx < nav.count - 1 else { return }
        guard let targetIdx = files.firstIndex(where: { $0.url == nav[idx + 1].url }) else { return }
        currentIndex = targetIdx
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

    /// Resume animation from the current frame index (does not reset to frame 0).
    private func resumeAnimation() {
        guard let frames = decodedImage?.animatedFrames, frames.count > 1 else { return }
        animationTask?.cancel()
        animationTask = nil
        let startIndex = min(currentFrameIndex, frames.count - 1)
        isAnimating = true
        isAnimationPaused = false
        currentFrameIndex = startIndex
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

    func selectFrame(at index: Int) {
        guard let frames = decodedImage?.animatedFrames, frames.indices.contains(index) else { return }
        isAnimationPaused = true
        currentFrameIndex = index
        if isCropMode {
            cropFrameImage = frames[index].image
        }
    }

    func selectFile(at index: Int) {
        let nav = navigableFiles
        guard nav.indices.contains(index) else { return }
        let targetFile = nav[index]
        guard let targetIdx = files.firstIndex(where: { $0.url == targetFile.url }), targetIdx != currentIndex else { return }
        currentIndex = targetIdx
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
        if isCropMode { reapplyCropPreset() }
    }

    func rotateRight() {
        rotation = (rotation - 90 + 360) % 360
        if isCropMode { reapplyCropPreset() }
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
            selectedGridIndices = [currentIndex]
            stopAnimation()
        } else {
            // Switch to the grid-selected file
            if let first = selectedGridIndices.sorted().first, files.indices.contains(first) {
                currentIndex = first
            }
            selectedGridIndices.removeAll()
            resetRotation()
            loadCurrentImage()
            needsCanvasFocus = true
            startAnimation()
        }
    }

    func toggleShortcutsHelp() {
        showShortcutsHelp.toggle()
    }

    // MARK: - Slideshow

    func startSlideshow() {
        guard navigableFiles.count > 1 else {
            showToast("Need at least 2 images for slideshow")
            return
        }
        // Sync currentIndex with grid selection so slideshow starts on the selected file
        if isGridView, let first = selectedGridIndices.sorted().first, files.indices.contains(first) {
            currentIndex = first
        }
        if let url = currentFile?.url, url.pathExtension.lowercased() == "gif" {
            showToast("GIF animations can't be used in slideshow, select another image")
            return
        }
        // Save thumbnail strip state, then hide it
        wasThumbnailStripVisibleBeforeSlideshow = showThumbnailStrip
        showThumbnailStrip = false
        if isInfoPanelVisible { isInfoPanelVisible = false }

        isSlideshowActive = true
        slideshowTask?.cancel()
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.slideshowInterval ?? 3))
                guard let self, !Task.isCancelled, isSlideshowActive else { break }
                // When paused, skip advance but keep the loop alive
                if isAnimationPaused { continue }
                await MainActor.run {
                    guard !Task.isCancelled, isSlideshowActive, !isAnimationPaused else { return }
                    slideshowNext()
                }
            }
        }
    }

    func stopSlideshow() {
        isSlideshowActive = false
        slideshowTask?.cancel()
        slideshowTask = nil
        // Sync grid selection with the last viewed image
        if isGridView { selectedGridIndices = [currentIndex] }
        // Restore thumbnail strip if it was visible before
        if wasThumbnailStripVisibleBeforeSlideshow { showThumbnailStrip = true }
        showToast("Slideshow stopped")
    }

    func toggleSlideshow() {
        if isSlideshowActive { stopSlideshow() }
        else { startSlideshow() }
    }

    /// Internal: navigate next, skipping animated formats like GIF.
    private func slideshowNext() {
        let nav = navigableFiles
        guard nav.count > 1, let currentURL = currentFile?.url,
              var idx = nav.firstIndex(where: { $0.url == currentURL })
        else { return }
        let startIdx = idx
        repeat {
            idx = (idx + 1) % nav.count
            let ext = nav[idx].url.pathExtension.lowercased()
            if ext != "gif" { break }
        } while idx != startIdx
        guard idx != startIdx, let targetIdx = files.firstIndex(where: { $0.url == nav[idx].url }) else { return }
        currentIndex = targetIdx
        resetRotation()
        loadCurrentImage()
        needsCanvasFocus = true
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
        let filtered = filteredIndices
        guard let pos = filtered.firstIndex(of: idx), pos > 0 else { return }
        selectInGrid(at: filtered[pos - 1])
    }

    func gridSelectNext() {
        let idx = selectedGridIndices.first ?? currentIndex
        let filtered = filteredIndices
        guard let pos = filtered.firstIndex(of: idx), pos < filtered.count - 1 else { return }
        selectInGrid(at: filtered[pos + 1])
    }

    func gridSelectUp(columns: Int) {
        let idx = selectedGridIndices.first ?? currentIndex
        let filtered = filteredIndices
        guard let pos = filtered.firstIndex(of: idx) else { return }
        let targetPos = pos - columns
        guard filtered.indices.contains(targetPos) else { return }
        selectInGrid(at: filtered[targetPos])
    }

    func gridSelectDown(columns: Int) {
        let idx = selectedGridIndices.first ?? currentIndex
        let filtered = filteredIndices
        guard let pos = filtered.firstIndex(of: idx) else { return }
        let targetPos = pos + columns
        guard filtered.indices.contains(targetPos) else { return }
        selectInGrid(at: filtered[targetPos])
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

    // MARK: - Crop

    enum CropPreset: String, CaseIterable, Sendable {
        case free = "Free"
        case r1v1  = "1:1"
        case r3v2  = "3:2"
        case r2v3  = "2:3"
        case r4v3  = "4:3"
        case r3v4  = "3:4"
        case r16v9 = "16:9"
        case r9v16 = "9:16"
        case r21v9 = "21:9"

        var ratio: CGFloat? {
            switch self {
            case .free: nil
            case .r1v1:  1
            case .r3v2:  3.0 / 2.0
            case .r2v3:  2.0 / 3.0
            case .r4v3:  4.0 / 3.0
            case .r3v4:  3.0 / 4.0
            case .r16v9: 16.0 / 9.0
            case .r9v16: 9.0 / 16.0
            case .r21v9: 21.0 / 9.0
            }
        }
    }

    func enterCropMode() {
        if isGridView {
            // Determine target file: explicit selection → grid highlight → first file
            let targetIdx = selectedGridIndices.sorted().first ?? currentIndex
            guard files.indices.contains(targetIdx) else { return }
            let file = files[targetIdx]

            // Exit grid view so ViewerNSView becomes visible for the crop overlay
            wasInGridViewBeforeCrop = true
            isGridView = false
            selectedGridIndices.removeAll()
            currentIndex = targetIdx
            needsCanvasFocus = true

            if decodedImage?.url == file.url {
                // Already decoded — enter crop directly
                enterCropModeDirect()
            } else {
                // Decode first, then enter crop
                isLoading = true
                loadTask?.cancel()
                loadTask = Task {
                    do {
                        let image = try await Task.detached(priority: .userInitiated) {
                            try self.decoder.decode(url: file.url)
                        }.value
                        guard !Task.isCancelled else { return }
                        ImageCache.shared.set(image)
                        decodedImage = image
                        metadata = self.metadataReader.read(url: image.url, pixelSize: image.pixelSize)
                        rotation = 0
                        isFlippedHorizontally = false
                        isLoading = false
                        enterCropModeDirect()
                    } catch {
                        isLoading = false
                        showToast("The file is damaged and can’t be displayed")
                    }
                }
            }
        } else {
            wasInGridViewBeforeCrop = false
            enterCropModeDirect()
        }
    }

    private func enterCropModeDirect() {
        guard decodedImage != nil else { return }
        stopAnimation()
        if hasAnimatedFrames { isAnimationPaused = true }
        wasThumbnailStripVisibleBeforeCrop = showThumbnailStrip
        if showThumbnailStrip { showThumbnailStrip = false }
        cropFrameImage = nil
        cropRect = .init(x: 0, y: 0, width: 1, height: 1)
        cropPreset = .free
        isCropMode = true
    }

    /// Re-apply the current preset after image/rotation change.
    /// Does nothing if the current preset is .free.
    private func reapplyCropPreset() {
        guard isCropMode, cropPreset != .free else { return }
        // Temporarily save preset, reset rect, then re-apply
        let saved = cropPreset
        cropRect = .init(x: 0, y: 0, width: 1, height: 1)
        cropPreset = .free
        setCropPreset(saved)
    }

    func applyCrop() {
        isCropMode = false
        if wasThumbnailStripVisibleBeforeCrop { showThumbnailStrip = true }
        if hasAnimatedFrames { resumeAnimation() }
        let restoreGrid = wasInGridViewBeforeCrop
        guard let img = decodedImage, let currentFile else { return }
        let imgW = CGFloat(img.image.width)
        let imgH = CGFloat(img.image.height)
        let pixelRect = CGRect(
            x: cropRect.origin.x * imgW,
            y: cropRect.origin.y * imgH,
            width: cropRect.width * imgW,
            height: cropRect.height * imgH
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return }

        // Crop the image (use frame strip selection if available)
        let sourceImage = cropFrameImage ?? img.image
        guard let cropped = ImageWriter.crop(sourceImage, to: pixelRect) else {
            showToast("Failed to crop image")
            return
        }

        // Generate output filename in the same folder: original_crop_N.ext
        let folder = currentFile.url.deletingLastPathComponent()
        let baseName = (currentFile.name as NSString).deletingPathExtension
        let ext = currentFile.url.pathExtension
        let existingNames = Set(files.map(\.name))
        var sequence = 1
        var outputName: String
        repeat {
            outputName = "\(baseName)_crop_\(sequence).\(ext)"
            sequence += 1
        } while existingNames.contains(outputName)

        let outputURL = folder.appendingPathComponent(outputName)
        let format = ImageWriter.SaveFormat.from(url: currentFile.url)
        guard ImageWriter.write(cropped, to: outputURL, format: format) else {
            showToast("Failed to save cropped file")
            return
        }

        // Add to file list and reload
        let newItem = FileItem(url: outputURL)
        files.append(newItem)
        files = FileSorter.sort(files, by: settings.sortMode)
        fileListVersion &+= 1

        if let newIdx = files.firstIndex(where: { $0.url == outputURL }) {
            currentIndex = newIdx
            stopAnimation()
            loadCurrentImage()
            needsCanvasFocus = true
        }

        cropFrameImage = nil

        // Return to grid if we came from there
        if restoreGrid {
            isGridView = true
            selectedGridIndices = [currentIndex]
            wasInGridViewBeforeCrop = false
        }

        showToast("Saved as \(outputName)")
    }

    func cancelCrop() {
        isCropMode = false
        cropFrameImage = nil
        if wasThumbnailStripVisibleBeforeCrop { showThumbnailStrip = true }
        if hasAnimatedFrames { resumeAnimation() }
        if wasInGridViewBeforeCrop {
            isGridView = true
            selectedGridIndices = [currentIndex]
            needsCanvasFocus = true
        }
    }

    func setCropPreset(_ preset: CropPreset) {
        cropPreset = preset
        guard let ratio = preset.ratio else {
            // Free — reset to full image
            cropRect = .init(x: 0, y: 0, width: 1, height: 1)
            return
        }
        guard let img = decodedImage else { return }
        // Use the actual CGImage dimensions (post-EXIF-orientation) rather than
        // the ImageIO property values which may differ for HEIC/GIF with EXIF.
        // Account for rotation: when 90° or 270°, effective W/H swaps.
        let rotated = (rotation % 180 != 0)
        let imgW = rotated ? CGFloat(img.image.height) : CGFloat(img.image.width)
        let imgH = rotated ? CGFloat(img.image.width)  : CGFloat(img.image.height)
        guard imgW > 0, imgH > 0 else { return }

        // Try to fill the longer dimension first. If it would exceed the image
        // bounds, fall back to filling the shorter dimension instead.
        let pw: CGFloat
        let ph: CGFloat
        let tryW = imgW
        let tryH = imgW / ratio
        if tryH <= imgH {
            pw = tryW; ph = tryH
        } else {
            ph = imgH; pw = ph * ratio
        }

        // Centre within image bounds
        let px = (imgW - pw) / 2
        let py = (imgH - ph) / 2

        cropRect = CGRect(x: px / imgW, y: py / imgH,
                          width: pw / imgW, height: ph / imgH)
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

    var activeFile: FileItem? {
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

    func copyMetadata() {
        guard let meta = metadata else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meta.exportText, forType: .string)
        showToast("Metadata copied")
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

    func showBatchRename() {
        guard isGridView, selectedGridIndices.count >= 2 else {
            showToast("Select at least 2 files")
            return
        }
        showBatchRenamePanel = true
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

    func loadCurrentImage() {
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
            if isCropMode { reapplyCropPreset() }
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
            if isCropMode { reapplyCropPreset() }
        }
    }

    private func preloadAdjacent() {
        let decoder = self.decoder
        let nav = navigableFiles
        guard let url = currentFile?.url, let pos = nav.firstIndex(where: { $0.url == url }) else { return }
        let adjPositions = [pos - 1, pos + 1].filter { nav.indices.contains($0) }
        for p in adjPositions {
            let file = nav[p]
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
