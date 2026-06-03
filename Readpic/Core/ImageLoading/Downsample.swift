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

        let w = CGFloat(rawImage.width)
        let h = CGFloat(rawImage.height)
        let maxDim = max(w, h)

        guard maxDim > maxPixelSize else { return rawImage }

        let scale = maxPixelSize / maxDim
        let tw = Int((w * scale).rounded())
        let th = Int((h * scale).rounded())
        guard tw > 0, th > 0 else { return rawImage }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return rawImage }

        ctx.interpolationQuality = .high
        ctx.draw(rawImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        guard let downsampled = ctx.makeImage() else { return rawImage }
        return downsampled
    }
}
