import XCTest
@testable import Readpic
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageDecoder Unit Tests

final class ImageDecoderTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadpicDecode_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        isLowMemoryMode = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helpers

    /// Create a JPEG test image with solid color content.
    @discardableResult
    private func createJPEG(at dir: URL, width: Int, height: Int, name: String,
                            compressionQuality: CGFloat = 0.85) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create JPEG destination") }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fatalError("JPEG write failed") }
        return url
    }

    /// Create a PNG test image.
    @discardableResult
    private func createPNG(at dir: URL, width: Int, height: Int, name: String) -> URL {
        let url = dir.appendingPathComponent("\(name).png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 0.8)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("Cannot create PNG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed") }
        return url
    }

    /// Create a GIF test image with multiple animation frames.
    @discardableResult
    private func createGIF(at dir: URL, name: String, frameCount: Int) -> URL {
        let url = dir.appendingPathComponent("\(name).gif")
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // NOTE: We use `let` for the destination, but the `images` array must use explicit CFArray bridging
        let frameProperty: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1
            ]
        ]

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)
        else { fatalError("Cannot create GIF destination") }

        let gifMetadata: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, gifMetadata as CFDictionary)

        for i in 0..<frameCount {
            let ctx = CGContext(
                data: nil, width: 50, height: 50,
                bitsPerComponent: 8, bytesPerRow: 50 * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )!
            let r = CGFloat(i) / CGFloat(frameCount)
            ctx.setFillColor(red: r, green: 0.5, blue: 1.0 - r, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
            let frameImage = ctx.makeImage()!

            CGImageDestinationAddImage(dest, frameImage, frameProperty as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { fatalError("GIF write failed") }
        return url
    }

    /// Create a file that exists but is not a valid image.
    @discardableResult
    private func createNonImageFile(at dir: URL, name: String) -> URL {
        let url = dir.appendingPathComponent("\(name).txt")
        try? "This is not an image".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - JPEG Decoding

    func testDecodeJPEG() throws {
        let url = createJPEG(at: tempDir, width: 1920, height: 1080, name: "test_jpeg")
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        XCTAssertEqual(decoded.url, url)
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 1920, height: 1080))
        XCTAssertNil(decoded.animatedFrames)
        XCTAssertEqual(decoded.frameCount, 1)
        // Proxy decode at default 2048px should not exceed the source
        let maxDim = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        XCTAssertLessThanOrEqual(maxDim, 2048)
    }

    func testDecodeJPEGWithCustomMaxPixelSize() throws {
        let url = createJPEG(at: tempDir, width: 4000, height: 3000, name: "large_jpeg")
        let decoder = ImageDecoder()

        // Decode with very small proxy
        let decoded = try decoder.decode(url: url, maxPixelSize: 512)
        let maxDim = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        XCTAssertLessThanOrEqual(maxDim, 512)
        XCTAssertGreaterThan(maxDim, 0)
    }

    func testDecodeJPEGWithoutDownsample() throws {
        let url = createJPEG(at: tempDir, width: 100, height: 100, name: "small_jpeg")
        let decoder = ImageDecoder()

        // Image smaller than default proxy size — should decode at native resolution
        let decoded = try decoder.decode(url: url, maxPixelSize: 2048)
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 100, height: 100))
        let maxDim = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        XCTAssertLessThanOrEqual(maxDim, 100)
    }

    // MARK: - PNG Decoding

    func testDecodePNG() throws {
        let url = createPNG(at: tempDir, width: 800, height: 600, name: "test_png")
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        XCTAssertEqual(decoded.pixelSize, CGSize(width: 800, height: 600))
        XCTAssertNil(decoded.animatedFrames)
        let maxDim = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        XCTAssertLessThanOrEqual(maxDim, 2048)
    }

    // MARK: - GIF Animation Decoding

    func testDecodeGIFWithMultipleFrames() throws {
        let url = createGIF(at: tempDir, name: "animated", frameCount: 5)
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        XCTAssertNotNil(decoded.animatedFrames)
        XCTAssertEqual(decoded.frameCount, 5)
        XCTAssertEqual(decoded.animatedFrames?.count, 5)

        // Verify frame timing
        if let frames = decoded.animatedFrames {
            for frame in frames {
                // Delay should be at least minFrameDelay (1/30s ≈ 0.033)
                XCTAssertGreaterThanOrEqual(frame.delay, 0.033)
            }
        }
    }

    func testDecodeGIFSingleFrame() throws {
        let url = createGIF(at: tempDir, name: "static_gif", frameCount: 1)
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        // Single-frame GIF should have nil animatedFrames
        XCTAssertNil(decoded.animatedFrames)
    }

    // MARK: - Decode Pixel Size Accuracy

    func testDecodePixelSizeMatchesOriginal() throws {
        let url = createJPEG(at: tempDir, width: 640, height: 480, name: "size_check")
        let decoder = ImageDecoder()
        let decoded = try decoder.decode(url: url)

        XCTAssertEqual(decoded.pixelSize.width, 640)
        XCTAssertEqual(decoded.pixelSize.height, 480)
    }

    // MARK: - Error Cases

    func testDecodeUnsupportedFormat() {
        let url = createNonImageFile(at: tempDir, name: "fake_image")
        // Rename to .jpg to pass FolderScanner's extension check
        let jpgURL = tempDir.appendingPathComponent("fake_image.jpg")
        try? FileManager.default.moveItem(at: url, to: jpgURL)

        let decoder = ImageDecoder()
        XCTAssertThrowsError(try decoder.decode(url: jpgURL)) { error in
            XCTAssertTrue(error is ImageDecodeError)
        }
    }

    func testDecodeNonexistentFile() {
        let url = tempDir.appendingPathComponent("does_not_exist.jpg")
        let decoder = ImageDecoder()
        XCTAssertThrowsError(try decoder.decode(url: url)) { error in
            guard let decodeError = error as? ImageDecodeError else {
                XCTFail("Expected ImageDecodeError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(decodeError, .unsupported)
        }
    }

    func testDecodeEmptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.jpg")
        try Data().write(to: url)
        let decoder = ImageDecoder()
        XCTAssertThrowsError(try decoder.decode(url: url)) { error in
            guard let decodeError = error as? ImageDecodeError else {
                XCTFail("Expected ImageDecodeError")
                return
            }
            // Empty JPEG data: CGImageSource is created but no image properties → .noImage
            XCTAssertEqual(decodeError, .noImage)
        }
    }

    // MARK: - DecodedImage Integrity

    func testDecodedImageSendable() {
        // Compile-time check: DecodedImage is marked Sendable
        // Verify the struct has no non-sendable stored properties
        let url = URL(fileURLWithPath: "/tmp/sendable_check.png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        let image = ctx.makeImage()!
        let decoded = DecodedImage(url: url, image: image,
                                   pixelSize: CGSize(width: 100, height: 100),
                                   animatedFrames: nil, frameCount: 1)

        // Pass to a Task to verify Sendable conformance at runtime
        let expectation = XCTestExpectation(description: "Sendable")
        Task {
            let reflected = decoded.url
            XCTAssertEqual(reflected, url)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Low Memory Mode

    func testDecodeRespectsLowMemoryMode() throws {
        let url = createJPEG(at: tempDir, width: 4000, height: 3000, name: "low_mem")
        let decoder = ImageDecoder()

        // Enable low memory mode
        isLowMemoryMode = true
        defer { isLowMemoryMode = false }

        // Default decode (no explicit maxPixelSize) should use 1024px proxy
        let decoded = try decoder.decode(url: url)
        let maxDim = max(CGFloat(decoded.image.width), CGFloat(decoded.image.height))
        XCTAssertLessThanOrEqual(maxDim, 1024)

        // Explicit maxPixelSize should still be honored
        let explicit = try decoder.decode(url: url, maxPixelSize: 256)
        let explicitMax = max(CGFloat(explicit.image.width), CGFloat(explicit.image.height))
        XCTAssertLessThanOrEqual(explicitMax, 256)
    }
}
