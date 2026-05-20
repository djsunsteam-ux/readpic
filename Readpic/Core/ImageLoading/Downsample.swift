import CoreGraphics
import Foundation
import ImageIO

struct Downsample {
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

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: constrainedSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodeError.noImage
        }

        return image
    }
}
