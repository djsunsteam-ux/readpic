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
        // Use full decode + manual downsample. CGImageSourceCreateThumbnailAtIndex
        // falls back to tiny embedded thumbnails for some JPEG files (error -51).
        guard let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageDecodeError.noImage
        }

        let w = CGFloat(fullImage.width)
        let h = CGFloat(fullImage.height)
        let maxDim = max(w, h)

        // Skip downsample if image is already within target size
        guard maxDim > maxPixelSize else { return fullImage }

        let scale = maxPixelSize / maxDim
        let tw = Int((w * scale).rounded())
        let th = Int((h * scale).rounded())
        guard tw > 0, th > 0 else { return fullImage }

        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: fullImage.bitsPerComponent,
            bytesPerRow: 0,
            space: fullImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: fullImage.bitmapInfo.rawValue
        ) else { return fullImage }

        ctx.interpolationQuality = .high
        ctx.draw(fullImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let downsampled = ctx.makeImage() else { return fullImage }
        return downsampled
    }
}
