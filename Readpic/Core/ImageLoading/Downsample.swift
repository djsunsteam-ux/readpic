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
        // Only constrain max pixel size if it's smaller than the source,
        // otherwise ImageIO warns that maxPixelSize exceeds the image dimensions.
        let constrainedSize: CGFloat
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            let sourceMax = max(w, h)
            constrainedSize = sourceMax < maxPixelSize ? sourceMax : maxPixelSize
        } else {
            constrainedSize = maxPixelSize
        }

        // Don't use embedded thumbnails — they are typically 160px and look
        // blurry when displayed at full screen. Force full decode + downsample.
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: constrainedSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodeError.noImage
        }

        return image
    }
}
