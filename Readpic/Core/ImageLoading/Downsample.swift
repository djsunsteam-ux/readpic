import CoreGraphics
import Foundation
import ImageIO

struct Downsample {
    /// Read EXIF orientation from image source (1-8, default 1 = normal).
    static func readOrientation(source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orient = props[kCGImagePropertyOrientation] as? Int else {
            return 1
        }
        return orient
    }

    static func createImage(source: CGImageSource, maxPixelSize: CGFloat) throws -> CGImage {
        guard let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageDecodeError.noImage
        }

        // Apply EXIF orientation so the output CGImage is always upright.
        let orientation = readOrientation(source: source)
        let oriented = applyOrientation(orientation, to: rawImage)

        let w = CGFloat(oriented.width)
        let h = CGFloat(oriented.height)
        let maxDim = max(w, h)

        guard maxDim > maxPixelSize else { return oriented }

        let scale = maxPixelSize / maxDim
        let tw = Int((w * scale).rounded())
        let th = Int((h * scale).rounded())
        guard tw > 0, th > 0 else { return oriented }

        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: oriented.bitsPerComponent,
            bytesPerRow: 0,
            space: oriented.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: oriented.bitmapInfo.rawValue
        ) else { return oriented }

        ctx.interpolationQuality = .high
        ctx.draw(oriented, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let downsampled = ctx.makeImage() else { return oriented }
        return downsampled
    }

    /// Apply EXIF orientation to a CGImage by rotating/flipping pixels.
    private static func applyOrientation(_ orientation: Int, to image: CGImage) -> CGImage {
        guard orientation != 1 else { return image }

        let w = image.width
        let h = image.height

        // Determine output dimensions and transform
        let outW: Int
        let outH: Int
        var transform = CGAffineTransform.identity

        switch orientation {
        case 2: // Flipped horizontally
            outW = w; outH = h
            transform = transform.translatedBy(x: CGFloat(w), y: 0).scaledBy(x: -1, y: 1)
        case 3: // Rotated 180°
            outW = w; outH = h
            transform = transform.translatedBy(x: CGFloat(w), y: CGFloat(h)).rotated(by: .pi)
        case 4: // Flipped vertically
            outW = w; outH = h
            transform = transform.translatedBy(x: 0, y: CGFloat(h)).scaledBy(x: 1, y: -1)
        case 5: // Transposed (flip H + rotate 270° CW)
            outW = h; outH = w
            transform = transform.rotated(by: -.pi / 2).scaledBy(x: -1, y: 1)
        case 6: // Rotated 90° CW
            outW = h; outH = w
            transform = transform.translatedBy(x: CGFloat(h), y: 0).rotated(by: .pi / 2)
        case 7: // Transversed (flip H + rotate 90° CW)
            outW = h; outH = w
            transform = transform.translatedBy(x: CGFloat(h), y: CGFloat(w)).rotated(by: .pi / 2).scaledBy(x: -1, y: 1)
        case 8: // Rotated 90° CCW
            outW = h; outH = w
            transform = transform.translatedBy(x: 0, y: CGFloat(w)).rotated(by: -.pi / 2)
        default:
            return image
        }

        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return image }

        ctx.concatenate(transform)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
