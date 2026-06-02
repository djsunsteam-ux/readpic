import XCTest
@testable import Readpic
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - MetadataReader Unit Tests

final class MetadataReaderTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadpicMeta_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helpers

    /// Create a JPEG image with embedded metadata.
    /// - Parameters:
    ///   - exif: EXIF dictionary (kCGImagePropertyExifDictionary value)
    ///   - tiff: TIFF dictionary (kCGImagePropertyTIFFDictionary value)
    ///   - iptc: IPTC dictionary (kCGImagePropertyIPTCDictionary value)
    ///   - gps: GPS dictionary (kCGImagePropertyGPSDictionary value)
    ///   - xmp: XMP dictionary (as key in the top-level properties)
    @discardableResult
    private func createImageWithMetadata(
        at dir: URL,
        name: String,
        width: Int = 100,
        height: Int = 100,
        exif: [CFString: Any]? = nil,
        tiff: [CFString: Any]? = nil,
        iptc: [CFString: Any]? = nil,
        gps: [CFString: Any]? = nil,
        xmp: [CFString: Any]? = nil,
        additionalProps: [CFString: Any]? = nil
    ) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create JPEG destination") }

        // Build metadata dictionary
        var properties: [CFString: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary] = exif }
        if let tiff { properties[kCGImagePropertyTIFFDictionary] = tiff }
        if let iptc { properties[kCGImagePropertyIPTCDictionary] = iptc }
        if let gps { properties[kCGImagePropertyGPSDictionary] = gps }
        if let xmp { properties["{XMP}" as CFString] = xmp }
        if let additionalProps {
            for (k, v) in additionalProps {
                properties[k] = v
            }
        }

        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fatalError("JPEG write failed") }
        return url
    }

    /// Create a plain JPEG with no special metadata.
    @discardableResult
    private func createPlainJPEG(at dir: URL, name: String) -> URL {
        let url = dir.appendingPathComponent("\(name).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 200, height: 100,
            bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let image = ctx.makeImage()!
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create JPEG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("JPEG write failed") }
        return url
    }

    // MARK: - Basic Metadata

    func testReadBasicFileMetadata() throws {
        let url = createPlainJPEG(at: tempDir, name: "test_photo")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: CGSize(width: 200, height: 100))

        XCTAssertEqual(meta.name, "test_photo.jpg")
        XCTAssertEqual(meta.path, url.path)
        XCTAssertGreaterThan(meta.fileSize, 0)
        XCTAssertNotNil(meta.createdAt)
        XCTAssertNotNil(meta.modifiedAt)
    }

    func testReadImageDimensions() throws {
        let url = createPlainJPEG(at: tempDir, name: "dim_test")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: CGSize(width: 200, height: 100))

        XCTAssertEqual(meta.pixelSize.width, 200)
        XCTAssertEqual(meta.pixelSize.height, 100)
    }

    func testReadImageDimensionsFromSourceWhenPixelSizeIsZero() throws {
        let url = createPlainJPEG(at: tempDir, name: "zero_size")
        let reader = MetadataReader()
        // Passing .zero should force reading from image source properties
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.pixelSize.width, 200)
        XCTAssertEqual(meta.pixelSize.height, 100)
    }

    func testReadFormat() throws {
        let url = createPlainJPEG(at: tempDir, name: "format_test")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.format, "JPG")
    }

    func testReadColorSpace() throws {
        let url = createPlainJPEG(at: tempDir, name: "colorspace_test")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        // sRGB is the default device RGB color space in CGContext
        XCTAssertFalse(meta.colorSpace.isEmpty)
        XCTAssertNotEqual(meta.colorSpace, "Unknown")
    }

    func testReadBitDepth() throws {
        let url = createPlainJPEG(at: tempDir, name: "bitdepth_test")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.bitDepth, 8)
    }

    // MARK: - EXIF Metadata

    func testReadEXIFCameraModel() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_camera",
            tiff: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: "EOS R5"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.camera, "Canon EOS R5")
    }

    func testReadEXIFCameraMakeOnly() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_make",
            tiff: [
                kCGImagePropertyTIFFMake: "Nikon"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.camera, "Nikon")
    }

    func testReadEXIFLens() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_lens",
            exif: [
                kCGImagePropertyExifLensModel: "EF 24-70mm f/2.8L II USM"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.lens, "EF 24-70mm f/2.8L II USM")
    }

    func testReadEXIFISO() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_iso",
            exif: [
                kCGImagePropertyExifISOSpeedRatings: [1600] as [NSNumber]
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.iso, 1600)
    }

    func testReadEXIFAperture() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_aperture",
            exif: [
                kCGImagePropertyExifFNumber: 2.8
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.aperture), 2.8, accuracy: 0.001)
    }

    func testReadEXIFShutterSpeed() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_shutter",
            exif: [
                kCGImagePropertyExifExposureTime: 0.004  // 1/250s
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.shutterSpeed), 0.004, accuracy: 0.0001)
    }

    func testReadEXIFFocalLength() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_focal",
            exif: [
                kCGImagePropertyExifFocalLength: 50.0
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.focalLength), 50.0, accuracy: 0.001)
    }

    func testReadEXIFExposureCompensation() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_ev",
            exif: [
                kCGImagePropertyExifExposureBiasValue: -0.7
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.exposureCompensation), -0.7, accuracy: 0.001)
    }

    func testReadEXIFDateTaken() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_date",
            exif: [
                kCGImagePropertyExifDateTimeOriginal: "2025:12:25 10:30:00"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNotNil(meta.dateTaken)
        // Verify the date components
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: meta.dateTaken!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    func testReadEXIFFlashFired() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_flash",
            exif: [
                kCGImagePropertyExifFlash: 1  // Fired
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNotNil(meta.flash)
        XCTAssertTrue(meta.flash!.contains("Fired"))
    }

    func testReadEXIFFlashDidNotFire() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_flash_off",
            exif: [
                kCGImagePropertyExifFlash: 16  // Did not fire
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNotNil(meta.flash)
        XCTAssertTrue(meta.flash!.contains("Did not fire"), "Flash value 16 should indicate 'Did not fire'")
    }

    func testReadEXIFMeteringMode() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_metering",
            exif: [
                kCGImagePropertyExifMeteringMode: 5  // Multi-segment
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.meteringMode, "Multi-segment")
    }

    func testReadEXIFWhiteBalance() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_wb",
            exif: [
                kCGImagePropertyExifWhiteBalance: 0  // Auto
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.whiteBalance, "Auto")
    }

    func testReadEXIFExposureMode() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_exp_mode",
            exif: [
                kCGImagePropertyExifExposureMode: 1  // Manual
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.exposureMode, "Manual")
    }

    func testReadEXIFSubjectDistance() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_distance",
            exif: [
                kCGImagePropertyExifSubjectDistance: 3.5
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.subjectDistance), 3.5, accuracy: 0.001)
    }

    func testReadEXIFDigitalZoomRatio() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "exif_zoom",
            exif: [
                kCGImagePropertyExifDigitalZoomRatio: 2.0
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.digitalZoomRatio), 2.0, accuracy: 0.001)
    }

    // MARK: - IPTC Metadata (read from a JPEG with no IPTC → fields are nil)

    func testReadIPTCNoData() throws {
        let url = createPlainJPEG(at: tempDir, name: "iptc_none")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNil(meta.caption, "Clean JPEG should have no IPTC caption")
        XCTAssertTrue(meta.keywords.isEmpty, "Clean JPEG should have no IPTC keywords")
        XCTAssertNil(meta.copyright)
        XCTAssertNil(meta.credit)
        XCTAssertNil(meta.byline)
        XCTAssertNil(meta.city)
        XCTAssertNil(meta.country)
        XCTAssertNil(meta.headline)
        XCTAssertNil(meta.objectName)
    }

    // MARK: - XMP Metadata (read from a JPEG with no XMP → fields are nil)

    func testReadXMPNoData() throws {
        let url = createPlainJPEG(at: tempDir, name: "xmp_none")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNil(meta.xmpRating, "Clean JPEG should have no XMP rating")
        XCTAssertNil(meta.xmpLabel)
        XCTAssertNil(meta.creatorTool)
        XCTAssertNil(meta.xmpDescription)
        XCTAssertNil(meta.xmpRights)
    }

    // MARK: - GPS Metadata

    func testReadGPSLatitudeLongitude() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "gps_coords",
            gps: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.latitude), 37.7749, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(meta.longitude), -122.4194, accuracy: 0.001)
    }

    func testReadGPSAltitude() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "gps_alt",
            gps: [
                kCGImagePropertyGPSLatitude: 0,
                kCGImagePropertyGPSLongitude: 0,
                kCGImagePropertyGPSAltitude: 100.0,
                kCGImagePropertyGPSAltitudeRef: 0  // Above sea level
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.altitude), 100.0, accuracy: 0.1)
    }

    func testReadGPSAltitudeBelowSeaLevel() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "gps_alt_neg",
            gps: [
                kCGImagePropertyGPSLatitude: 0,
                kCGImagePropertyGPSLongitude: 0,
                kCGImagePropertyGPSAltitude: 50.0,
                kCGImagePropertyGPSAltitudeRef: 1  // Below sea level
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.altitude), -50.0, accuracy: 0.1)
    }

    func testReadGPSSouthernHemisphere() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "gps_south",
            gps: [
                kCGImagePropertyGPSLatitude: 33.8688,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.2093,
                kCGImagePropertyGPSLongitudeRef: "E"
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(try XCTUnwrap(meta.latitude), -33.8688, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(meta.longitude), 151.2093, accuracy: 0.001)
    }

    // MARK: - Computed Properties

    func testFormattedFileSize() throws {
        let url = createPlainJPEG(at: tempDir, name: "size_format")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertFalse(meta.formattedFileSize.isEmpty)
        // ByteCountFormatter output — just verify it's a reasonable string
        XCTAssertTrue(meta.formattedFileSize.contains("bytes") ||
                      meta.formattedFileSize.contains("KB") ||
                      meta.formattedFileSize.contains("MB"))
    }

    func testDimensionsText() throws {
        let url = createPlainJPEG(at: tempDir, name: "dims")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: CGSize(width: 200, height: 100))

        XCTAssertEqual(meta.dimensionsText, "200 × 100")
    }

    func testApertureText() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "ap_text",
            exif: [kCGImagePropertyExifFNumber: 2.8]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.apertureText, "ƒ/2.8")
    }

    func testApertureTextNil() throws {
        let url = createPlainJPEG(at: tempDir, name: "ap_nil")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNil(meta.apertureText)
    }

    func testShutterTextFast() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "shutter_fast",
            exif: [kCGImagePropertyExifExposureTime: 1.0 / 250.0]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.shutterText, "1/250s")
    }

    func testShutterTextSlow() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "shutter_slow",
            exif: [kCGImagePropertyExifExposureTime: 2.0]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.shutterText, "2s")
    }

    func testShutterTextNil() throws {
        let url = createPlainJPEG(at: tempDir, name: "shutter_nil")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNil(meta.shutterText)
    }

    func testDateTakenText() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "date_text",
            exif: [kCGImagePropertyExifDateTimeOriginal: "2025:06:15 14:30:00"]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNotNil(meta.dateTakenText)
        // DateFormatter output is locale-dependent, just verify it contains 2025
        XCTAssertTrue(meta.dateTakenText!.contains("2025"))
    }

    func testLocationText() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "loc_text",
            gps: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSAltitude: 10.0,
                kCGImagePropertyGPSAltitudeRef: 0
            ]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNotNil(meta.locationText)
        XCTAssertTrue(meta.locationText!.contains("N"))
        XCTAssertTrue(meta.locationText!.contains("W"))
    }

    func testLocationTextNil() throws {
        let url = createPlainJPEG(at: tempDir, name: "loc_nil")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertNil(meta.locationText)
    }

    // MARK: - Export Text

    func testExportTextContainsKeySections() throws {
        let url = createImageWithMetadata(
            at: tempDir, name: "export_test",
            exif: [kCGImagePropertyExifISOSpeedRatings: [400] as [NSNumber]],
            tiff: [kCGImagePropertyTIFFModel: "TestCamera"]
        )
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        let export = meta.exportText
        XCTAssertTrue(export.contains("Readpic — Image Information"))
        XCTAssertTrue(export.contains("▸ File"))
        XCTAssertTrue(export.contains("▸ Image"))
        XCTAssertTrue(export.contains("▸ Camera"))
        XCTAssertTrue(export.contains("TestCamera"))
        XCTAssertTrue(export.contains("400"))
    }

    // MARK: - Equatable

    func testMetadataEquatable() throws {
        let url1 = createPlainJPEG(at: tempDir, name: "eq_a")
        let url2 = createPlainJPEG(at: tempDir, name: "eq_b")
        let reader = MetadataReader()

        let meta1 = reader.read(url: url1, pixelSize: .zero)
        let meta1copy = reader.read(url: url1, pixelSize: .zero)
        let meta2 = reader.read(url: url2, pixelSize: .zero)

        XCTAssertEqual(meta1, meta1copy, "Same file should produce equal metadata")
        XCTAssertNotEqual(meta1, meta2, "Different files should produce different metadata")
    }

    // MARK: - MetadataReader with no metadata

    func testReadMinimalJPEG() throws {
        // A JPEG with absolutely no EXIF/IPTC/XMP should still return basic file info
        let url = createPlainJPEG(at: tempDir, name: "minimal")
        let reader = MetadataReader()
        let meta = reader.read(url: url, pixelSize: .zero)

        XCTAssertEqual(meta.name, "minimal.jpg")
        XCTAssertNotNil(meta.pixelSize)
        // All optional fields should be nil
        XCTAssertNil(meta.camera)
        XCTAssertNil(meta.lens)
        XCTAssertNil(meta.iso)
        XCTAssertNil(meta.aperture)
        XCTAssertNil(meta.shutterSpeed)
        XCTAssertNil(meta.dateTaken)
        XCTAssertNil(meta.caption)
        XCTAssertTrue(meta.keywords.isEmpty)
        XCTAssertNil(meta.latitude)
        XCTAssertNil(meta.longitude)
    }

    // MARK: - MetadataReader Sendable

    func testMetadataReaderSendable() {
        // Compile-time check: MetadataReader is marked Sendable
        let reader = MetadataReader()
        let expectation = XCTestExpectation(description: "Sendable check")

        Task {
            // Just verify we can call read from a Task (proving Sendable)
            let url = URL(fileURLWithPath: "/tmp/sendable_check.jpg")
            _ = reader.read(url: url, pixelSize: .zero)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
