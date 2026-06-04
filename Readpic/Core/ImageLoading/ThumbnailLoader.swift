import AppKit
import CoreGraphics
import Foundation
import ImageIO
import os

/// Global low-memory flag — checked by ImageDecoder and ThumbnailLoader.
/// Written from @MainActor, read from background queues. Thread-safe via unfair lock.
private let _isLowMemoryMode = OSAllocatedUnfairLock(initialState: false)
var isLowMemoryMode: Bool {
    get { _isLowMemoryMode.withLock { $0 } }
    set { _isLowMemoryMode.withLock { $0 = newValue } }
}

/// Composite key for thumbnail cache using multiple file identity factors.
struct ThumbnailCacheKey: Hashable, Sendable {
    let url: URL
    let fileSize: Int64
    let modificationDate: TimeInterval

    init(url: URL, fileSize: Int64, modificationDate: TimeInterval) {
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.url = url
        self.fileSize = Int64(values?.fileSize ?? 0)
        self.modificationDate = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [ThumbnailCacheKey: CGImage] = [:]
    /// Tracks access order — front is least-recently-used, back is most-recently-used.
    private var accessOrder: [ThumbnailCacheKey] = []
    private var maxCount: Int = 200

    private init() {}

    func get(key: ThumbnailCacheKey) -> CGImage? {
        guard cache[key] != nil else { return nil }
        // Promote to most-recently-used
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        return cache[key]
    }

    func set(_ image: CGImage, for key: ThumbnailCacheKey) {
        cache[key] = image
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        if cache.count > maxCount {
            evictLRU()
        }
    }

    func remove(_ url: URL) {
        let key = ThumbnailCacheKey(url: url)
        cache.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    func halveCapacity() {
        maxCount = max(maxCount / 2, 50)
        if cache.count > maxCount {
            evictLRU()
        }
    }

    func restoreCapacity() {
        maxCount = 200
    }

    /// Evicts the least-recently-used entries (front of accessOrder).
    private func evictLRU() {
        while cache.count > maxCount, !accessOrder.isEmpty {
            let lru = accessOrder.removeFirst()
            cache.removeValue(forKey: lru)
        }
    }

#if TESTING
    /// Override max count for unit tests — resets restoreCapcity on next call.
    func forceMaxCountForTesting(_ count: Int) {
        maxCount = count
    }

    /// Returns current entry count for unit test assertions.
    func countForTesting() -> Int {
        cache.count
    }
#endif
}

final class ThumbnailQueueManager: @unchecked Sendable {
    static let shared = ThumbnailQueueManager()

    private let visibleQueue: OperationQueue
    private let backgroundQueue: OperationQueue
    private let preloadQueue: OperationQueue

    private init() {
        visibleQueue = OperationQueue()
        visibleQueue.maxConcurrentOperationCount = 4
        visibleQueue.qualityOfService = .userInitiated

        backgroundQueue = OperationQueue()
        backgroundQueue.maxConcurrentOperationCount = 2
        backgroundQueue.qualityOfService = .utility

        preloadQueue = OperationQueue()
        preloadQueue.maxConcurrentOperationCount = 2
        preloadQueue.qualityOfService = .userInitiated
    }

    enum Priority {
        case visible
        case background
        case preload
    }

    func schedule(url: URL, priority: Priority, completion: @escaping @Sendable (CGImage?) -> Void) {
        let op = BlockOperation { [weak self] in
            guard self != nil else { return }

            let cacheKey = ThumbnailCacheKey(url: url)

            // 1. Check disk cache before hitting ImageIO
            if let diskCached = ThumbnailDiskCache.shared.get(key: cacheKey) {
                DispatchQueue.main.async {
                    ThumbnailCache.shared.set(diskCached, for: cacheKey)
                    completion(diskCached)
                }
                return
            }

            // 2. Generate thumbnail via ImageIO
            let maxSize: CGFloat = isLowMemoryMode ? 128 : 160
            guard let thumbnail = ThumbnailLoader.generateThumbnail(url: url, maxSize: maxSize) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 3. Persist to disk (fire-and-forget on this background thread)
            ThumbnailDiskCache.shared.set(key: cacheKey, image: thumbnail)

            DispatchQueue.main.async {
                ThumbnailCache.shared.set(thumbnail, for: cacheKey)
                completion(thumbnail)
            }
        }

        switch priority {
        case .visible: visibleQueue.addOperation(op)
        case .preload: preloadQueue.addOperation(op)
        case .background: backgroundQueue.addOperation(op)
        }
    }

    func cancelAll() {
        visibleQueue.cancelAllOperations()
        backgroundQueue.cancelAllOperations()
        preloadQueue.cancelAllOperations()
    }

    func cancelBackground() {
        backgroundQueue.cancelAllOperations()
        preloadQueue.cancelAllOperations()
    }
}

enum ThumbnailLoader {
    static let maxSize: CGFloat = 160

    static func load(url: URL, priority: ThumbnailQueueManager.Priority = .visible) async -> CGImage? {
        let cacheKey = ThumbnailCacheKey(url: url)
        if let cached = await ThumbnailCache.shared.get(key: cacheKey) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            ThumbnailQueueManager.shared.schedule(url: url, priority: priority) { image in
                continuation.resume(returning: image)
            }
        }
    }

    static func generateThumbnail(url: URL, maxSize: CGFloat = 160) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        // Skip truncated or incomplete images to avoid ImageIO console errors
        // (e.g. kCGImageSourceErrUnexpectedEOF / error -51 on corrupt JPEGs).
        guard CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { return nil }

        let options: [CFString: Any] = [
            "kCGImageSourceCreateThumbnailFromImageIfPossible" as CFString: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
