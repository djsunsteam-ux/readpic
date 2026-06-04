import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Applies rotation/flip transforms to CGImage and writes to file.
struct ImageWriter {

    /// Supported export formats.
    enum SaveFormat: String, CaseIterable, Sendable {
        case jpeg = "JPEG"
        case png  = "PNG"
        case tiff = "TIFF"
        case bmp  = "BMP"
        case heic = "HEIC"

        var utType: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png:  .png
            case .tiff: .tiff
            case .bmp:  .bmp
            case .heic: .heic
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .png:  "png"
            case .tiff: "tiff"
            case .bmp:  "bmp"
            case .heic: "heic"
            }
        }

        /// Whether this format supports a quality slider (JPEG / HEIC).
        var supportsQuality: Bool {
            switch self {
            case .jpeg, .heic: true
            case .png, .tiff, .bmp: false
            }
        }

        /// Infer save format from a file extension string.
        static func from(extension ext: String) -> SaveFormat? {
            switch ext.lowercased() {
            case "jpg", "jpeg": .jpeg
            case "png":         .png
            case "tiff", "tif": .tiff
            case "bmp":         .bmp
            case "heic", "heif": .heic
            default:            nil
            }
        }

        /// Infer save format from a file URL's extension.
        static func from(url: URL) -> SaveFormat {
            from(extension: url.pathExtension) ?? .jpeg
        }
    }

    // MARK: - Transform

    /// Produce a new CGImage with rotation and horizontal flip baked into pixel data.
    /// - Parameters:
    ///   - image: Source image (untransformed).
    ///   - rotation: Rotation in degrees (0, 90, 180, 270).
    ///   - isFlipped: Whether to mirror horizontally.
    /// - Returns: Transformed CGImage, or `nil` on context allocation failure.
    static func applyTransform(to image: CGImage, rotation: Int, isFlipped: Bool) -> CGImage? {
        let angle = ((rotation % 360) + 360) % 360  // Normalise to 0..360
        let swapDim = (angle == 90 || angle == 270)

        let srcW = image.width
        let srcH = image.height
        let dstW = swapDim ? srcH : srcW
        let dstH = swapDim ? srcW : srcH

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // Use opaque context (no alpha) to avoid warnings when saving to
        // formats that don't support alpha (JPEG). Source alpha channels
        // composite onto the opaque black background during draw.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high

        // Move origin to centre
        ctx.translateBy(x: CGFloat(dstW) / 2, y: CGFloat(dstH) / 2)

        // Flip horizontal (applied first in the display chain: rotate → scale -1)
        if isFlipped {
            ctx.scaleBy(x: -1, y: 1)
        }

        // Rotate
        let rad = CGFloat(angle) * .pi / 180
        ctx.rotate(by: rad)

        // Draw source image centred
        ctx.draw(image, in: CGRect(
            x: -CGFloat(srcW) / 2,
            y: -CGFloat(srcH) / 2,
            width: CGFloat(srcW),
            height: CGFloat(srcH)
        ))

        return ctx.makeImage()
    }

    // MARK: - Crop

    /// Crop a CGImage to the given pixel rect.
    /// The rect is in pixel coordinates relative to the source image.
    /// Returns `nil` if the rect is empty or the context can't be created.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let x = max(0, Int(rect.origin.x))
        let y = max(0, Int(rect.origin.y))
        let w = max(1, Int(rect.width))
        let h = max(1, Int(rect.height))

        guard x + w <= image.width, y + h <= image.height else { return nil }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    // MARK: - Write

    /// Write a CGImage to a file at the given URL.
    /// - Parameters:
    ///   - image: The image data to write.
    ///   - url: Destination file URL.
    ///   - format: Target image format.
    ///   - compressionQuality: JPEG quality 0-1 (ignored for lossless formats).
    /// - Returns: `true` on success.
    @discardableResult
    static func write(_ image: CGImage, to url: URL, format: SaveFormat, compressionQuality: CGFloat? = nil) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else { return false }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            let quality = compressionQuality.map { max(0, min(1, $0)) } ?? 0.9
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
