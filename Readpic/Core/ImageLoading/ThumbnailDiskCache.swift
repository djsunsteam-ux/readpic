import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Disk-backed thumbnail cache.
///
/// All methods are synchronous (blocking I/O) and designed to be called from
/// background queues only — never from the MainActor.
///
/// Cache invalidation is automatic: the filename encodes `fileSize` and
/// `modificationDate` from `ThumbnailCacheKey`, so a changed source file
/// produces a different filename and triggers a fresh generate.
///
/// Eviction: LRU by file modification date (touched on read), capped at
/// 100 MB and 5,000 files.
final class ThumbnailDiskCache: @unchecked Sendable {
    static let shared = ThumbnailDiskCache()

    private let maxDiskBytes: Int64 = 100 * 1024 * 1024   // 100 MB
    private let maxFileCount = 5000
    private let fileManager = FileManager.default

    private var cacheDir: URL? {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appending(path: "com.readpic/Thumbnails/v1", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    // MARK: - Public API

    /// Look up a thumbnail on disk.
    /// Returns `nil` on miss, corrupted data, or I/O error.
    /// Touches the file's modification date on hit (for LRU ordering).
    func get(key: ThumbnailCacheKey) -> CGImage? {
        guard let dir = cacheDir else { return nil }
        let url = dir.appendingPathComponent(filename(for: key))
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }

        // Decode JPEG/PNG data from disk
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        // Touch file for LRU ordering
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        return image
    }

    /// Store a thumbnail to disk. Skips if an entry for this `key` already
    /// exists (deduplicates concurrent writes from multiple priority queues).
    func set(key: ThumbnailCacheKey, image: CGImage) {
        guard let dir = cacheDir else { return }
        let url = dir.appendingPathComponent(filename(for: key))

        guard !fileManager.fileExists(atPath: url.path) else { return }

        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: .atomic)

        // Keep total within budget
        enforceBudget()
    }

    /// Remove a specific thumbnail.
    func remove(key: ThumbnailCacheKey) {
        guard let dir = cacheDir else { return }
        let url = dir.appendingPathComponent(filename(for: key))
        try? fileManager.removeItem(at: url)
    }

    /// Wipe the entire thumbnail cache directory.
    func clear() {
        guard let dir = cacheDir else { return }
        try? fileManager.removeItem(at: dir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    /// Deterministic filename encoding the cache key.
    /// `{urlHash}_{fileSize}_{modDateMs}.thumb`
    private func filename(for key: ThumbnailCacheKey) -> String {
        let urlHash = sha256Prefix(key.url.absoluteString)
        let modMs = Int(key.modificationDate * 1000)
        return "\(urlHash)_\(key.fileSize)_\(modMs).thumb"
    }

    /// First 16 hex chars of SHA-256 — enough to avoid collision in practice.
    private func sha256Prefix(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.prefix(16).joined()
    }

    /// Scan cache dir and evict oldest entries until under both size and count caps.
    private func enforceBudget() {
        guard let dir = cacheDir else { return }

        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        var files: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate
            else { continue }
            files.append((fileURL, Int64(size), date))
            totalSize += Int64(size)
        }

        guard totalSize > maxDiskBytes || files.count > maxFileCount else { return }

        // Oldest modification date first → LRU eviction
        files.sort { $0.date < $1.date }

        var remaining = files.count
        for file in files {
            guard totalSize > maxDiskBytes || remaining > maxFileCount else { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
            remaining -= 1
        }
    }
}

// MARK: - CGImage → JPEG data

private extension CGImage {
    /// Encode this CGImage as JPEG data at the given quality.
    func jpegData(compressionQuality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, self, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
