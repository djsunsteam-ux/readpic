import Accelerate
import CoreGraphics
import Foundation

/// RGB + luminance histograms computed from a CGImage via vImage.
struct Histogram {
    let red: [UInt]
    let green: [UInt]
    let blue: [UInt]
    let luminance: [UInt]

    /// Pre-computed smoothed channel curves (radius-2 moving average).
    /// Lazily computed once; chart view avoids re-smoothing on every render.
    let smoothRed: [CGFloat]
    let smoothGreen: [CGFloat]
    let smoothBlue: [CGFloat]
    let smoothLuminance: [CGFloat]

    static let binCount = 256

    /// Maximum count across all channels (for normalising display).
    var maxCount: UInt {
        let all = red + green + blue + luminance
        return all.max() ?? 1
    }

    // MARK: - Cache

    nonisolated(unsafe) private static let cache: NSCache<NSURL, CachedHistogram> = {
        let c = NSCache<NSURL, CachedHistogram>()
        c.countLimit = 10
        return c
    }()

    private final class CachedHistogram {
        let value: Histogram
        init(_ value: Histogram) { self.value = value }
    }

    /// Compute histograms for a CGImage, with URL-keyed cache.
    /// Images >512px are automatically downsampled for performance.
    /// Returns `nil` for unsupported formats or allocation failures.
    static func compute(from image: CGImage, url: URL? = nil, maxPixelSize: CGFloat = 512) -> Histogram? {
        if let url = url as NSURL?, let cached = cache.object(forKey: url) {
            return cached.value
        }

        let source: CGImage
        let longSide = max(image.width, image.height)
        if CGFloat(longSide) > maxPixelSize, let downsampled = thumbnail(from: image, maxPixelSize: maxPixelSize) {
            source = downsampled
        } else {
            source = image
        }

        guard let result = computeRaw(from: source) else { return nil }

        let hist = Histogram(
            red: result.red, green: result.green, blue: result.blue, luminance: result.luminance,
            smoothRed: smooth(result.red), smoothGreen: smooth(result.green),
            smoothBlue: smooth(result.blue), smoothLuminance: smooth(result.luminance)
        )

        if let url = url as NSURL? {
            cache.setObject(CachedHistogram(hist), forKey: url)
        }
        return hist
    }

    /// Clear the histogram cache (e.g. after saving changes to an image).
    static func clearCache(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    // MARK: - Internal

    /// Raw histogram computation (no caching, no downsampling).
    private static func computeRaw(from image: CGImage) -> (red: [UInt], green: [UInt], blue: [UInt], luminance: [UInt])? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        // 1. Render into a known-format ARGB bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let pixelData = ctx.data else { return nil }

        // 2. Wrap in a vImage buffer
        var src = vImage_Buffer(
            data: pixelData,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * 4
        )

        // 3. RGB histograms
        var hr = [vImagePixelCount](repeating: 0, count: binCount)
        var hg = [vImagePixelCount](repeating: 0, count: binCount)
        var hb = [vImagePixelCount](repeating: 0, count: binCount)
        var ha = [vImagePixelCount](repeating: 0, count: binCount)

        var histErr: vImage_Error = kvImageNoError
        hr.withUnsafeMutableBufferPointer { rBuf in
            hg.withUnsafeMutableBufferPointer { gBuf in
                hb.withUnsafeMutableBufferPointer { bBuf in
                    ha.withUnsafeMutableBufferPointer { aBuf in
                        var hists = [rBuf.baseAddress, gBuf.baseAddress, bBuf.baseAddress, aBuf.baseAddress]
                        histErr = vImageHistogramCalculation_ARGB8888(&src, &hists, vImage_Flags(kvImageNoFlags))
                    }
                }
            }
        }
        guard histErr == kvImageNoError else { return nil }

        // 4. Luminance histogram
        // Compute luminance = 0.2126*R + 0.7152*G + 0.0722*B (Rec. 709)
        // by matrix-multiplying the ARGB buffer into a planar 8-bit luminance buffer.
        var lumBuf = vImage_Buffer(
            data: nil,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )
        guard vImageBuffer_Init(&lumBuf, vImagePixelCount(h), vImagePixelCount(w), 8, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return nil }
        defer { free(lumBuf.data) }

        // Rec. 709 matrix: R*0.2126 + G*0.7152 + B*0.0722
        var matrix: [Int16] = [
            Int16(0.2126 * 1024),  // R
            Int16(0.7152 * 1024),  // G
            Int16(0.0722 * 1024),  // B
            0                       // A
        ]
        // 1x4 matrix, divisor = 1024
        let divisor: Int32 = 1024

        guard vImageMatrixMultiply_ARGB8888ToPlanar8(
            &src, &lumBuf, &matrix, divisor,
            nil,     // preBias
            0,       // postBias
            vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError
        else { return nil }

        var hl = [vImagePixelCount](repeating: 0, count: binCount)
        guard vImageHistogramCalculation_Planar8(
            &lumBuf,
            &hl,
            vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError
        else { return nil }

        return (
            red:   hr.map(UInt.init),
            green: hg.map(UInt.init),
            blue:  hb.map(UInt.init),
            luminance: hl.map(UInt.init)
        )
    }

    /// Downsample an image to fit within `maxPixelSize` long side.
    private static func thumbnail(from image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        guard let (tw, th) = Downsample.targetDimensions(
            imageSize: CGSize(width: image.width, height: image.height),
            maxPixelSize: Int(maxPixelSize)
        ) else { return image }

        guard let ctx = CGContext(
            data: nil, width: tw, height: th,
            bitsPerComponent: 8, bytesPerRow: tw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    // MARK: - Smoothing

    /// Radius-1 moving-average smoother (pre-computed once for each channel).
    private static func smooth(_ data: [UInt], radius: Int = 1) -> [CGFloat] {
        guard !data.isEmpty else { return [] }
        var result = [CGFloat](repeating: 0, count: data.count)
        for i in 0..<data.count {
            var sum: CGFloat = 0
            var count: CGFloat = 0
            let start = max(0, i - radius)
            let end = min(data.count - 1, i + radius)
            for j in start...end {
                sum += CGFloat(data[j])
                count += 1
            }
            result[i] = sum / count
        }
        return result
    }
}
