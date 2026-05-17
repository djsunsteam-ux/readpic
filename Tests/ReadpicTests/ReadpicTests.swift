import XCTest
@testable import Readpic

final class ReadpicTests: XCTestCase {

    // MARK: - FileSorter

    func testFileSorterNaturalNameSorting() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/img_10.png")),
            FileItem(url: URL(fileURLWithPath: "/tmp/img_2.png")),
            FileItem(url: URL(fileURLWithPath: "/tmp/img_1.png"))
        ]

        let sortedNames = FileSorter.sort(items, by: .name).map(\.name)

        XCTAssertEqual(sortedNames, ["img_1.png", "img_2.png", "img_10.png"])
    }

    func testFileSorterNameCaseInsensitivity() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/DSC_0001.HEIC")),
            FileItem(url: URL(fileURLWithPath: "/tmp/dsc_0010.heic")),
            FileItem(url: URL(fileURLWithPath: "/tmp/DSC_0100.Heic"))
        ]

        let sorted = FileSorter.sort(items, by: .name)
        // localizedStandardCompare treats "DSC_" and "dsc_" as equal — falls through to numeric
        XCTAssertEqual(sorted.map(\.name), ["DSC_0001.HEIC", "dsc_0010.heic", "DSC_0100.Heic"])
    }

    func testFileSorterDateSortNewestFirst() {
        let now = Date()
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/old.png"), modificationDate: now.addingTimeInterval(-3600)),
            FileItem(url: URL(fileURLWithPath: "/tmp/new.png"), modificationDate: now.addingTimeInterval(-60)),
            FileItem(url: URL(fileURLWithPath: "/tmp/mid.png"), modificationDate: now.addingTimeInterval(-1800))
        ]

        let sorted = FileSorter.sort(items, by: .date)
        XCTAssertEqual(sorted.map(\.name), ["new.png", "mid.png", "old.png"])
    }

    func testFileSorterDateSortWithNilDates() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/a.png"), modificationDate: Date()),
            FileItem(url: URL(fileURLWithPath: "/tmp/b.png"), modificationDate: nil),
            FileItem(url: URL(fileURLWithPath: "/tmp/c.png"), modificationDate: nil)
        ]

        let sorted = FileSorter.sort(items, by: .date)
        // Items with nil dates fall back to alphabetical after dated items
        XCTAssertEqual(sorted[0].name, "a.png")
        XCTAssertEqual(sorted[1].name, "b.png")
        XCTAssertEqual(sorted[2].name, "c.png")
    }

    func testFileSorterEmptyArray() {
        let sorted = FileSorter.sort([], by: .name)
        XCTAssertTrue(sorted.isEmpty)
    }

    func testFileSorterSingleItem() {
        let item = FileItem(url: URL(fileURLWithPath: "/tmp/solo.png"))
        let sorted = FileSorter.sort([item], by: .name)
        XCTAssertEqual(sorted.count, 1)
    }

    // MARK: - FolderScanner

    func testFolderScannerSupportedExtensions() {
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.jpg")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.jpeg")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.PNG")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.heic")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.HEIC")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.webp")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.gif")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.tiff")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.tif")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.bmp")))
        XCTAssertFalse(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.svg")))
        XCTAssertFalse(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.txt")))
        XCTAssertFalse(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertFalse(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a")))
    }

    func testFolderScannerFiltersAndSortsImages() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        for name in ["img_10.png", "notes.txt", "img_2.JPG", "img_1.jpeg", "img_3.HEIC", "img_4.webp"] {
            FileManager.default.createFile(atPath: folderURL.appendingPathComponent(name).path, contents: Data())
        }

        let items = try await FolderScanner().scanFolder(folderURL)

        // Only image files, sorted naturally by name
        XCTAssertEqual(items.map(\.name), ["img_1.jpeg", "img_2.JPG", "img_3.HEIC", "img_4.webp", "img_10.png"])
    }

    func testFolderScannerEmptyFolder() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let items = try await FolderScanner().scanFolder(folderURL)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - ImageCache (LRU, max 5)

    @MainActor
    func testImageCacheSetAndGet() {
        let cache = ImageCache.shared
        cache.clear()

        let url1 = URL(fileURLWithPath: "/tmp/img1.png")
        let img1 = makeFakeImage()
        let decoded1 = DecodedImage(url: url1, image: img1, pixelSize: CGSize(width: 100, height: 100),
                                    animatedFrames: nil, frameCount: 1)
        cache.set(decoded1)
        XCTAssertNotNil(cache.get(url1))
    }

    @MainActor
    func testImageCacheLRUEviction() {
        let cache = ImageCache.shared
        cache.clear()

        // Insert 6 images (max 5), the first one should be evicted
        var images: [DecodedImage] = []
        for i in 1...6 {
            let url = URL(fileURLWithPath: "/tmp/img_\(i).png")
            let fake = makeFakeImage()
            let decoded = DecodedImage(url: url, image: fake, pixelSize: CGSize(width: 100, height: 100),
                                       animatedFrames: nil, frameCount: 1)
            images.append(decoded)
            cache.set(decoded)
        }

        // First image should be evicted
        XCTAssertNil(cache.get(images[0].url))
        // Most recently inserted should still be there
        XCTAssertNotNil(cache.get(images[5].url))
        // Second image should also still be there (eviction = 1 at a time when exceeding 5)
        XCTAssertNotNil(cache.get(images[1].url))
    }

    @MainActor
    func testImageCacheReInsertMovesToBack() {
        let cache = ImageCache.shared
        cache.clear()

        let url1 = URL(fileURLWithPath: "/tmp/a.png")
        let url2 = URL(fileURLWithPath: "/tmp/b.png")
        let url3 = URL(fileURLWithPath: "/tmp/c.png")
        let url4 = URL(fileURLWithPath: "/tmp/d.png")
        let url5 = URL(fileURLWithPath: "/tmp/e.png")
        let url6 = URL(fileURLWithPath: "/tmp/f.png")

        let fake = makeFakeImage()
        for url in [url1, url2, url3, url4, url5] {
            cache.set(DecodedImage(url: url, image: fake, pixelSize: .zero, animatedFrames: nil, frameCount: 1))
        }

        // Re-insert url1 (it was first, now becomes most recent)
        cache.set(DecodedImage(url: url1, image: fake, pixelSize: .zero, animatedFrames: nil, frameCount: 1))

        // Insert url6 — should evict url2 (the LRU now, since url1 was re-inserted)
        cache.set(DecodedImage(url: url6, image: fake, pixelSize: .zero, animatedFrames: nil, frameCount: 1))

        XCTAssertNotNil(cache.get(url1)) // was re-inserted
        XCTAssertNil(cache.get(url2))     // should be evicted
        XCTAssertNotNil(cache.get(url6))  // newest
    }

    @MainActor
    func testImageCacheClear() {
        let cache = ImageCache.shared
        cache.clear()

        let url = URL(fileURLWithPath: "/tmp/test.png")
        cache.set(DecodedImage(url: url, image: makeFakeImage(), pixelSize: .zero, animatedFrames: nil, frameCount: 1))
        cache.clear()
        XCTAssertNil(cache.get(url))
    }

    // MARK: - ThumbnailCache (LRU, max 200)

    @MainActor
    func testThumbnailCacheLRUEviction() {
        let cache = ThumbnailCache.shared
        cache.clear()
        // Temporarily set a small max to test eviction
        cache.forceMaxCountForTesting(3)

        let url1 = URL(fileURLWithPath: "/tmp/t1.png")
        let url2 = URL(fileURLWithPath: "/tmp/t2.png")
        let url3 = URL(fileURLWithPath: "/tmp/t3.png")
        let url4 = URL(fileURLWithPath: "/tmp/t4.png")

        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url1))
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url2))
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url3))
        // Now at capacity (3)

        // This should evict url1 (the LRU)
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url4))

        XCTAssertNil(cache.get(key: ThumbnailCacheKey(url: url1)))
        XCTAssertNotNil(cache.get(key: ThumbnailCacheKey(url: url4)))
        XCTAssertNotNil(cache.get(key: ThumbnailCacheKey(url: url2)))

        cache.restoreCapacity()
    }

    @MainActor
    func testThumbnailCacheGetUpdatesAccessOrder() {
        let cache = ThumbnailCache.shared
        cache.clear()
        cache.forceMaxCountForTesting(2)

        let url1 = URL(fileURLWithPath: "/tmp/a.png")
        let url2 = URL(fileURLWithPath: "/tmp/b.png")
        let url3 = URL(fileURLWithPath: "/tmp/c.png")

        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url1))
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url2))

        // Access url1, making it MRU
        _ = cache.get(key: ThumbnailCacheKey(url: url1))

        // Insert url3 should evict url2 (now LRU)
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url3))

        XCTAssertNotNil(cache.get(key: ThumbnailCacheKey(url: url1)))
        XCTAssertNil(cache.get(key: ThumbnailCacheKey(url: url2)))
        XCTAssertNotNil(cache.get(key: ThumbnailCacheKey(url: url3)))

        cache.restoreCapacity()
    }

    @MainActor
    func testThumbnailCacheHalveCapacity() {
        let cache = ThumbnailCache.shared
        cache.clear()
        // halveCapacity has a floor of 50, so start at 100 to get meaningful eviction
        cache.forceMaxCountForTesting(100)

        for i in 0..<100 {
            let url = URL(fileURLWithPath: "/tmp/t_\(i).png")
            cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url))
        }
        XCTAssertEqual(cache.countForTesting(), 100)

        cache.halveCapacity() // maxCount becomes max(50, 50) = 50
        // At most 50 entries should remain
        let remaining = cache.countForTesting()
        XCTAssertLessThanOrEqual(remaining, 50)
        XCTAssertGreaterThan(remaining, 0)

        cache.restoreCapacity()
    }

    @MainActor
    func testThumbnailCacheClear() {
        let cache = ThumbnailCache.shared
        cache.clear()

        let url = URL(fileURLWithPath: "/tmp/t.png")
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url))
        cache.clear()

        XCTAssertNil(cache.get(key: ThumbnailCacheKey(url: url)))
    }

    @MainActor
    func testThumbnailCacheRemove() {
        let cache = ThumbnailCache.shared
        cache.clear()

        let url = URL(fileURLWithPath: "/tmp/toremove.png")
        cache.set(makeFakeImage(), for: ThumbnailCacheKey(url: url))
        XCTAssertNotNil(cache.get(key: ThumbnailCacheKey(url: url)))

        cache.remove(url)
        XCTAssertNil(cache.get(key: ThumbnailCacheKey(url: url)))
    }

    // MARK: - FileItem

    func testFileItemIdentity() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let item1 = FileItem(url: url, fileSize: 1024, modificationDate: Date())
        let item2 = FileItem(url: url, fileSize: 2048, modificationDate: Date().addingTimeInterval(100))

        // Same URL → same id (the Identifiable conformance uses URL as id)
        XCTAssertEqual(item1.id, item2.id)
        // FileItem uses synthesized Equatable — compares all properties, so different fileSize → not equal
        XCTAssertNotEqual(item1, item2)

        let item3 = FileItem(url: url, fileSize: 1024, modificationDate: item1.modificationDate)
        XCTAssertEqual(item1, item3)
    }

    func testFileItemNameExtraction() {
        let url = URL(fileURLWithPath: "/tmp/My Photo.jpg")
        let item = FileItem(url: url)
        XCTAssertEqual(item.name, "My Photo.jpg")
    }

    // MARK: - Helpers

    /// Creates a minimal 1×1 CGImage for cache testing.
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
