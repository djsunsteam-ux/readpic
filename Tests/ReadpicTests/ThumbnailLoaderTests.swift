import XCTest
@testable import Readpic
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - ThumbnailLoader Unit Tests

@MainActor
final class ThumbnailLoaderTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadpicThumb_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        isLowMemoryMode = false

        // Clean shared caches for test isolation
        ThumbnailCache.shared.clear()
        ThumbnailDiskCache.shared.clear()
        ThumbnailQueueManager.shared.cancelAll()
    }

    override func tearDownWithError() throws {
        ThumbnailQueueManager.shared.cancelAll()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helpers

    /// Create a JPEG test image.
    @discardableResult
    private func createTestJPEG(at dir: URL, width: Int, height: Int, name: String) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Add some visual complexity for meaningful thumbnail
        ctx.setFillColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.6)
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))

        let image = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create JPEG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("JPEG write failed") }
        return url
    }

    /// Create a 1×1 pixel JPEG.
    @discardableResult
    private func createTinyJPEG(at dir: URL, name: String) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create JPEG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    // MARK: - generateThumbnail

    func testGenerateThumbnailJPEG() throws {
        let url = createTestJPEG(at: tempDir, width: 1920, height: 1080, name: "thumb_jpeg")
        let thumbnail = ThumbnailLoader.generateThumbnail(url: url)

        XCTAssertNotNil(thumbnail, "Thumbnail generation should succeed for JPEG")
        if let thumb = thumbnail {
            let maxDim = max(thumb.width, thumb.height)
            XCTAssertLessThanOrEqual(maxDim, 160, "Thumbnail should be ≤ 160px on longest side")
            XCTAssertGreaterThan(maxDim, 0)
        }
    }

    func testGenerateThumbnailWithCustomMaxSize() throws {
        let url = createTestJPEG(at: tempDir, width: 1920, height: 1080, name: "custom_size")
        let thumbnail = ThumbnailLoader.generateThumbnail(url: url, maxSize: 64)

        XCTAssertNotNil(thumbnail)
        if let thumb = thumbnail {
            let maxDim = max(thumb.width, thumb.height)
            XCTAssertLessThanOrEqual(maxDim, 64, "Thumbnail should be ≤ 64px on longest side")
        }
    }

    func testGenerateThumbnailPNG() throws {
        let url = tempDir.appendingPathComponent("thumb_png.png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 800, height: 600,
            bitsPerComponent: 8, bytesPerRow: 800 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 0.8)
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let image = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("Cannot create PNG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)

        let thumbnail = ThumbnailLoader.generateThumbnail(url: url)
        XCTAssertNotNil(thumbnail, "Thumbnail generation should succeed for PNG")
        if let thumb = thumbnail {
            let maxDim = max(thumb.width, thumb.height)
            XCTAssertLessThanOrEqual(maxDim, 160)
        }
    }

    func testGenerateThumbnailSmallImage() throws {
        // Image smaller than thumbnail size should still produce a valid thumbnail
        let url = createTinyJPEG(at: tempDir, name: "tiny")
        let thumbnail = ThumbnailLoader.generateThumbnail(url: url)

        XCTAssertNotNil(thumbnail, "Even tiny images should generate a thumbnail")
        if let thumb = thumbnail {
            XCTAssertEqual(thumb.width, 1, "1px image should stay 1px")
            XCTAssertEqual(thumb.height, 1)
        }
    }

    func testGenerateThumbnailUnsupportedFormat() {
        let url = tempDir.appendingPathComponent("test.txt")
        try? "not an image".write(to: url, atomically: true, encoding: .utf8)

        let thumbnail = ThumbnailLoader.generateThumbnail(url: url)
        XCTAssertNil(thumbnail, "Unsupported format should return nil")
    }

    func testGenerateThumbnailNonexistentFile() {
        let url = tempDir.appendingPathComponent("nonexistent.jpg")
        let thumbnail = ThumbnailLoader.generateThumbnail(url: url)
        XCTAssertNil(thumbnail, "Nonexistent file should return nil")
    }

    // MARK: - ThumbnailCache Key

    func testThumbnailCacheKeyUniqueness() {
        let url1 = URL(fileURLWithPath: "/tmp/a.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/b.jpg")

        let key1a = ThumbnailCacheKey(url: url1, fileSize: 1000, modificationDate: 1000)
        let key1b = ThumbnailCacheKey(url: url1, fileSize: 1000, modificationDate: 1000)
        let key2 = ThumbnailCacheKey(url: url2, fileSize: 2000, modificationDate: 2000)
        let keyDiffSize = ThumbnailCacheKey(url: url1, fileSize: 999, modificationDate: 1000)
        let keyDiffDate = ThumbnailCacheKey(url: url1, fileSize: 1000, modificationDate: 999)

        XCTAssertEqual(key1a, key1b, "Same inputs should produce equal keys")
        XCTAssertNotEqual(key1a, key2, "Different URLs should produce different keys")
        XCTAssertNotEqual(key1a, keyDiffSize, "Different fileSize should produce different keys")
        XCTAssertNotEqual(key1a, keyDiffDate, "Different modificationDate should produce different keys")
    }

    func testThumbnailCacheKeyFromURL() throws {
        let url = createTestJPEG(at: tempDir, width: 100, height: 100, name: "key_test")
        let key = ThumbnailCacheKey(url: url)

        XCTAssertEqual(key.url, url)
        XCTAssertGreaterThan(key.fileSize, 0)
        XCTAssertGreaterThan(key.modificationDate, 0)
    }

    // MARK: - ThumbnailCache Memory Cache

    @MainActor
    func testThumbnailCacheSetAndGet() {
        let cache = ThumbnailCache.shared
        cache.clear()
        defer { cache.clear() }

        let key = ThumbnailCacheKey(url: URL(fileURLWithPath: "/tmp/mem_test.jpg"))
        let image = makeFakeImage()

        cache.set(image, for: key)
        let retrieved = cache.get(key: key)
        XCTAssertNotNil(retrieved)
    }

    @MainActor
    func testThumbnailCacheLRUEviction() {
        let cache = ThumbnailCache.shared
        cache.clear()
        cache.forceMaxCountForTesting(2)
        defer { cache.restoreCapacity() }

        let key1 = ThumbnailCacheKey(url: URL(fileURLWithPath: "/tmp/lru_1.jpg"))
        let key2 = ThumbnailCacheKey(url: URL(fileURLWithPath: "/tmp/lru_2.jpg"))
        let key3 = ThumbnailCacheKey(url: URL(fileURLWithPath: "/tmp/lru_3.jpg"))

        cache.set(makeFakeImage(), for: key1)
        cache.set(makeFakeImage(), for: key2)
        // Access key1 to make it MRU
        _ = cache.get(key: key1)
        // Insert key3 — should evict key2 (now LRU)
        cache.set(makeFakeImage(), for: key3)

        XCTAssertNotNil(cache.get(key: key1))
        XCTAssertNil(cache.get(key: key2))
        XCTAssertNotNil(cache.get(key: key3))
    }

    // MARK: - ThumbnailQueueManager

    func testQueueManagerCancellation() {
        let queueManager = ThumbnailQueueManager.shared
        queueManager.cancelAll()
        // No assertion — just verify it doesn't crash
    }

    // MARK: - ThumbnailDiskCache

    func testThumbnailDiskCacheSetAndGet() throws {
        let url = createTestJPEG(at: tempDir, width: 100, height: 100, name: "disk_cache")
        let key = ThumbnailCacheKey(url: url)

        // Clear before test
        ThumbnailDiskCache.shared.clear()
        defer { ThumbnailDiskCache.shared.clear() }

        // Generate thumbnail and store
        guard let thumbnail = ThumbnailLoader.generateThumbnail(url: url) else {
            XCTFail("Should generate thumbnail")
            return
        }

        ThumbnailDiskCache.shared.set(key: key, image: thumbnail)
        let retrieved = ThumbnailDiskCache.shared.get(key: key)
        XCTAssertNotNil(retrieved, "Disk cache should return the stored thumbnail")
    }

    func testThumbnailDiskCacheMissOnDifferentKey() throws {
        let url = createTestJPEG(at: tempDir, width: 100, height: 100, name: "disk_miss")
        let key = ThumbnailCacheKey(url: url, fileSize: 1234, modificationDate: 5678)
        let wrongKey = ThumbnailCacheKey(url: url, fileSize: 9999, modificationDate: 1111)

        ThumbnailDiskCache.shared.clear()
        defer { ThumbnailDiskCache.shared.clear() }

        guard let thumbnail = ThumbnailLoader.generateThumbnail(url: url) else {
            XCTFail("Should generate thumbnail")
            return
        }

        ThumbnailDiskCache.shared.set(key: key, image: thumbnail)
        let retrieved = ThumbnailDiskCache.shared.get(key: wrongKey)
        XCTAssertNil(retrieved, "Wrong key should not match")
    }

    func testThumbnailDiskCacheRemove() throws {
        let url = createTestJPEG(at: tempDir, width: 100, height: 100, name: "disk_remove")
        let key = ThumbnailCacheKey(url: url)

        ThumbnailDiskCache.shared.clear()
        defer { ThumbnailDiskCache.shared.clear() }

        guard let thumbnail = ThumbnailLoader.generateThumbnail(url: url) else {
            XCTFail("Should generate thumbnail")
            return
        }

        ThumbnailDiskCache.shared.set(key: key, image: thumbnail)
        XCTAssertNotNil(ThumbnailDiskCache.shared.get(key: key))

        ThumbnailDiskCache.shared.remove(key: key)
        XCTAssertNil(ThumbnailDiskCache.shared.get(key: key))
    }

    // MARK: - Helpers

    private func makeFakeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}
