import XCTest
@testable import Readpic
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Performance Tests for Readpic Phase 1 Targets
//
// These tests measure core module performance against ROADMAP §2.2, §4.6 targets.
// Run with: swift test --filter ReadpicPerformanceTests

@MainActor
final class ReadpicPerformanceTests: XCTestCase {

    // MARK: - Properties

    var tempDir: URL!

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadpicPerf_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Reset global state for consistent test conditions
        isLowMemoryMode = false
        ThumbnailCache.shared.restoreCapacity()
        ThumbnailCache.shared.clear()
        ThumbnailDiskCache.shared.clear()
        ImageCache.shared.clear()
    }

    override func tearDownWithError() throws {
        ThumbnailQueueManager.shared.cancelAll()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Test Image Helpers

    /// Create a tiny (1×1 px) JPEG file for scanner tests.
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

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            fatalError("Cannot create JPEG destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    /// Create a full-size JPEG test image with non-trivial content (gradient + shapes).
    @discardableResult
    private func createTestJPEG(at dir: URL, width: Int, height: Int, name: String,
                                compressionQuality: CGFloat = 0.9) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        // Background
        ctx.setFillColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Gradient for visual complexity
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1),
                     CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1),
                     CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)] as CFArray,
            locations: [0, 0.5, 1.0]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: width, y: height), options: [])

        // Random circles
        for _ in 0..<20 {
            let cx = CGFloat.random(in: 0...CGFloat(width))
            let cy = CGFloat.random(in: 0...CGFloat(height))
            let r = CGFloat.random(in: 10...50)
            ctx.setFillColor(red: .random(in: 0...1), green: .random(in: 0...1),
                             blue: .random(in: 0...1), alpha: 0.5)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        let image = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            fatalError("Cannot create JPEG destination")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        let ok = CGImageDestinationFinalize(dest)
        precondition(ok, "JPEG write failed")
        return url
    }

    /// Create N tiny JPEG files (1×1 px) for folder-scan benchmarking.
    /// Uses only JPEG to avoid format compatibility issues in test environment.
    @discardableResult
    private func createManyTinyJPEGs(count: Int, prefix: String = "img") -> URL {
        let batchDir = tempDir.appendingPathComponent("batch_\(prefix)_\(count)", isDirectory: true)
        try! FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        for i in 0..<count {
            createTinyJPEG(at: batchDir, name: "\(prefix)_\(i)")
        }
        return batchDir
    }

    /// Create N full-size JPEG test images (1920×1080) in a subdirectory.
    @discardableResult
    private func createManyTestJPEGs(count: Int) -> URL {
        let batchDir = tempDir.appendingPathComponent("test_batch_\(count)", isDirectory: true)
        try! FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        for i in 0..<count {
            createTestJPEG(at: batchDir, width: 1920, height: 1080, name: "img_\(i)")
        }
        return batchDir
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.1f ms", seconds * 1000)
        } else {
            return String(format: "%.2f s", seconds)
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Estimate decoded CGImage pixel buffer size (doesn't include CG wrapper overhead).
    private func pixelBufferSize(_ image: CGImage) -> UInt64 {
        UInt64(image.height) * UInt64(image.bytesPerRow)
    }

    /// Read current resident memory (in-process, noisy but directional).
    private func currentRSS() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - FolderScanner Performance
    // ─────────────────────────────────────────────────────────────────

    func testFolderScanner_1000Images() async throws {
        let dir = createManyTinyJPEGs(count: 1000, prefix: "scan1k")
        let scanner = FolderScanner()
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            let items = try await scanner.scanFolder(dir)
            XCTAssertEqual(items.count, 1000)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  ⏱  FolderScanner: 1000 images → \(formatDuration(seconds))")
        XCTAssertLessThan(seconds, 0.5, "Scanning 1000 images should take < 500ms")
    }

    func testFolderScanner_10000Images() async throws {
        let dir = createManyTinyJPEGs(count: 10000, prefix: "scan10k")
        let scanner = FolderScanner()
        let clock = ContinuousClock()

        let elapsed = try await clock.measure {
            let items = try await scanner.scanFolder(dir)
            XCTAssertEqual(items.count, 10000)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  ⏱  FolderScanner: 10000 images → \(formatDuration(seconds))")
        XCTAssertLessThan(seconds, 2.0, "Scanning 10000 images should take < 2s")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - ImageDecoder Cold Decode Performance
    // ─────────────────────────────────────────────────────────────────

    func testImageDecoder_ColdDecode_JPEG_1080p() throws {
        let url = createTestJPEG(at: tempDir, width: 1920, height: 1080, name: "cold_1080p")
        let decoder = ImageDecoder()
        let clock = ContinuousClock()

        var decoded: DecodedImage!
        let elapsed = try clock.measure {
            decoded = try decoder.decode(url: url)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let bufSize = pixelBufferSize(decoded.image)
        print("  ⏱  Cold Decode JPEG 1080p: \(formatDuration(seconds))  |  pixel buffer: \(formatMemory(bufSize))")
        // ROADMAP §4.6: cold open < 150ms
        XCTAssertLessThan(seconds, 0.150, "Cold decode 1080p JPEG should be < 150ms")
        XCTAssertGreaterThan(decoded.pixelSize.width, 0)
    }

    func testImageDecoder_ColdDecode_JPEG_4K() throws {
        let url = createTestJPEG(at: tempDir, width: 3840, height: 2160, name: "cold_4k")
        let decoder = ImageDecoder()
        let clock = ContinuousClock()

        var decoded: DecodedImage!
        let elapsed = try clock.measure {
            decoded = try decoder.decode(url: url)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let bufSize = pixelBufferSize(decoded.image)
        print("  ⏱  Cold Decode JPEG 4K: \(formatDuration(seconds))  |  pixel buffer: \(formatMemory(bufSize))")
    }

    func testImageDecoder_ColdDecode_PNG_1080p() throws {
        // For PNG, create via CGImageDestination with PNG type
        let url = tempDir.appendingPathComponent("cold_png.png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 1920, height: 1080,
            bitsPerComponent: 8, bytesPerRow: 1920 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1),
                     CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)] as CFArray,
            locations: [0, 1.0]
        )!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1920, y: 1080), options: [])
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Cannot create PNG destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)

        let decoder = ImageDecoder()
        let clock = ContinuousClock()
        var decoded: DecodedImage!
        let elapsed = try clock.measure {
            decoded = try decoder.decode(url: url)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let bufSize = pixelBufferSize(decoded.image)
        print("  ⏱  Cold Decode PNG 1080p: \(formatDuration(seconds))  |  pixel buffer: \(formatMemory(bufSize))")
        XCTAssertLessThan(seconds, 0.150, "Cold decode 1080p PNG should be < 150ms")
    }

    func testImageDecoder_Proxy2048() throws {
        // Verify that 4K→2048px proxy decode produces a smaller buffer
        let url = createTestJPEG(at: tempDir, width: 3840, height: 2160, name: "proxy_4k")
        let decoder = ImageDecoder()
        let clock = ContinuousClock()

        var decoded: DecodedImage!
        let elapsed = try clock.measure {
            decoded = try decoder.decode(url: url, maxPixelSize: 2048)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let proxyMax = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        let bufSize = pixelBufferSize(decoded.image)
        print("  ⏱  Decode 4K→2048px proxy: \(formatDuration(seconds))  |  proxy: \(Int(proxyMax))px  |  buffer: \(formatMemory(bufSize))")
        XCTAssertLessThanOrEqual(proxyMax, 2048, "Proxy should be ≤ 2048px on longest side")
        XCTAssertLessThan(seconds, 0.080, "Proxy decode should be < 80ms")

        // Now decode at full resolution to compare buffer sizes
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return }

        // Decode at native resolution for comparison
        let nativeMax = max(w, h)
        let fullDecoded = try decoder.decode(url: url, maxPixelSize: nativeMax)
        let fullBufSize = pixelBufferSize(fullDecoded.image)
        let ratio = Double(fullBufSize) / Double(bufSize)
        print("      Full decode buffer: \(formatMemory(fullBufSize))  |  ratio: \(String(format: "%.1f", ratio))×")
        XCTAssertGreaterThan(ratio, 1.5, "Proxy should be > 1.5× smaller than full decode")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Memory Impact (in-process RSS — directional only)
    // ─────────────────────────────────────────────────────────────────

    func testDecodeMemoryImpact_JPEG_1080p() throws {
        let url = createTestJPEG(at: tempDir, width: 1920, height: 1080, name: "mem_1080p")
        let decoder = ImageDecoder()

        let rssBefore = currentRSS()
        let decoded = try decoder.decode(url: url)
        let rssAfter = currentRSS()

        let delta = rssAfter - rssBefore
        let bufSize = pixelBufferSize(decoded.image)
        print("  📊 Memory Impact JPEG 1080p:")
        print("      RSS before: \(formatMemory(rssBefore))")
        print("      RSS after:  \(formatMemory(rssAfter))")
        print("      Delta:      \(formatMemory(delta))")
        print("      Pixel buf:  \(formatMemory(bufSize))")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Thumbnail Generation Performance
    // ─────────────────────────────────────────────────────────────────

    func testThumbnailBatch_20Images() async throws {
        let dir = createManyTestJPEGs(count: 20)
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)

        ThumbnailCache.shared.clear()
        ThumbnailDiskCache.shared.clear()

        let clock = ContinuousClock()
        var imageCount = 0
        let elapsed = try await clock.measure {
            try await withThrowingTaskGroup(of: CGImage?.self) { group in
                for url in urls {
                    group.addTask {
                        return await ThumbnailLoader.load(url: url, priority: .visible)
                    }
                }
                for try await img in group {
                    if img != nil { imageCount += 1 }
                }
            }
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  ⏱  Thumbnail batch (20): \(formatDuration(seconds))  |  \(imageCount) images generated")
        XCTAssertEqual(imageCount, 20, "All 20 thumbnails should generate")
        // ROADMAP §4.6: first-screen 20 thumbnails < 2s
        XCTAssertLessThan(seconds, 2.0, "20 thumbnails should complete in < 2s")
    }

    func testThumbnailBatch_100Images() async throws {
        let dir = createManyTestJPEGs(count: 100)
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)

        ThumbnailCache.shared.clear()
        ThumbnailDiskCache.shared.clear()

        let clock = ContinuousClock()
        var imageCount = 0
        let elapsed = try await clock.measure {
            try await withThrowingTaskGroup(of: CGImage?.self) { group in
                for url in urls {
                    group.addTask {
                        return await ThumbnailLoader.load(url: url, priority: .visible)
                    }
                }
                for try await img in group {
                    if img != nil { imageCount += 1 }
                }
            }
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let perImage = seconds / 100
        print("  ⏱  Thumbnail batch (100): \(formatDuration(seconds)) total, \(formatDuration(perImage))/img  |  \(imageCount) images")
        XCTAssertEqual(imageCount, 100, "All 100 thumbnails should generate")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - First-Screen 20 Thumbnails Acceptance Test (§4.6)
    // ─────────────────────────────────────────────────────────────────

    func testFirstScreen20ThumbnailsUnder2Seconds() async throws {
        // ROADMAP §4.6: first-screen 20 thumbnails must complete in < 2s
        let dir = createManyTestJPEGs(count: 20)
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertEqual(urls.count, 20, "Should have 20 test images")

        ThumbnailCache.shared.clear()
        ThumbnailDiskCache.shared.clear()

        let clock = ContinuousClock()
        var images: [CGImage] = []
        let elapsed = try await clock.measure {
            try await withThrowingTaskGroup(of: CGImage?.self) { group in
                for url in urls {
                    group.addTask {
                        return await ThumbnailLoader.load(url: url, priority: .visible)
                    }
                }
                for try await image in group {
                    if let img = image { images.append(img) }
                }
            }
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  ✅ First-screen 20 thumbnails: \(formatDuration(seconds))  |  \(images.count)/20 generated")
        XCTAssertLessThan(seconds, 2.0,
                          "ROADMAP §4.6: first-screen 20 thumbnails must complete in < 2s (got \(formatDuration(seconds)))")
        XCTAssertEqual(images.count, 20, "All 20 thumbnails should generate successfully")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - ImageCache Hot Path
    // ─────────────────────────────────────────────────────────────────

    func testImageCache_HotHit() throws {
        let url = createTestJPEG(at: tempDir, width: 1920, height: 1080, name: "hot_test")
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        ImageCache.shared.set(decoded)
        XCTAssertNotNil(ImageCache.shared.get(url))

        let clock = ContinuousClock()
        var found: DecodedImage?
        let elapsed = clock.measure {
            found = ImageCache.shared.get(url)
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("  ⏱  ImageCache hot hit: \(formatDuration(seconds))")
        XCTAssertNotNil(found)
        XCTAssertLessThan(seconds, 0.001, "Cache lookup should be < 1ms")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Summary
    // ─────────────────────────────────────────────────────────────────

    override class func tearDown() {
        print("")
        print("┌──────────────────────────────────────────────────────────┐")
        print("│  Performance tests complete — compare against ROADMAP   │")
        print("│  §2.2 (memory baselines) and §4.6 (performance targets) │")
        print("└──────────────────────────────────────────────────────────┘")
    }
}
