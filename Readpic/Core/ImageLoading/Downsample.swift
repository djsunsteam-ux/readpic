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

    /// Compute target width/height for downsampling an image so its longest
    /// side fits within `maxPixelSize`. Returns `nil` when no downsampling is
    /// needed (the image already fits).
    static func targetDimensions(imageSize: CGSize, maxPixelSize: Int) -> (Int, Int)? {
        let w = imageSize.width
        let h = imageSize.height
        let maxDim = max(w, h)
        guard maxDim > CGFloat(maxPixelSize) else { return nil }

        let scale = CGFloat(maxPixelSize) / maxDim
        let tw = Int((w * scale).rounded())
        let th = Int((h * scale).rounded())
        guard tw > 0, th > 0 else { return nil }
        return (tw, th)
    }

}
