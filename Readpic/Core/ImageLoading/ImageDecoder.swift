import CoreGraphics
import Foundation
import ImageIO

struct AnimationFrame: Sendable {
    let image: CGImage
    let delay: TimeInterval
}

struct DecodedImage: Sendable {
    let url: URL
    let image: CGImage
    let pixelSize: CGSize
    let animatedFrames: [AnimationFrame]?
    let frameCount: Int
}

enum ImageDecodeError: Error {
    case unsupported
    case noImage
}

struct ImageDecoder {
    private static let maxAnimationFrames = 100
    private static let maxFPS: TimeInterval = 30
    private static let minFrameDelay: TimeInterval = 1.0 / maxFPS

    func decode(url: URL, maxPixelSize: CGFloat? = nil) throws -> DecodedImage {
        let pixelSize = maxPixelSize ?? (isLowMemoryMode ? 1024 : 2048)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageDecodeError.unsupported
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageDecodeError.noImage
        }

        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let frameCount = CGImageSourceGetCount(source)
        let image = try Downsample.createImage(source: source, maxPixelSize: pixelSize)
        let animatedFrames: [AnimationFrame]?

        if frameCount > 1 {
            let maxFrames = min(frameCount, Self.maxAnimationFrames)
            animatedFrames = decodeFrames(source: source, frameCount: maxFrames, maxPixelSize: pixelSize)
        } else {
            animatedFrames = nil
        }

        return DecodedImage(
            url: url,
            image: image,
            pixelSize: CGSize(width: width, height: height),
            animatedFrames: animatedFrames,
            frameCount: frameCount
        )
    }

    private func decodeFrames(source: CGImageSource, frameCount: Int, maxPixelSize: CGFloat) -> [AnimationFrame]? {
        var frames: [AnimationFrame] = []
        var previousFrame: CGImage?

        for i in 0..<frameCount {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
            ]

            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifDict = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gifDict?[kCGImagePropertyGIFDelayTime] as? Double
            var delay = max(unclamped ?? clamped ?? 0.1, 0.02)
            delay = max(delay, Self.minFrameDelay)

            guard var frameImage = CGImageSourceCreateImageAtIndex(source, i, options as CFDictionary) else {
                continue
            }

            let disposalKey = "DisposalMethod" as CFString
            let disposal = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[disposalKey] as? Int ?? 0
            // disposal method: 0=no disposal, 1=do not dispose, 2=restore to background, 3=restore to previous

            if disposal == 2 {
                // restore to background: render frame on clean canvas
                previousFrame = nil
            } else if disposal == 3 {
                // restore to previous: composite on previous frame
                if let prev = previousFrame {
                    frameImage = compositeFrame(previous: prev, current: frameImage)
                }
            } else if disposal == 0 || disposal == 1 {
                // do not dispose: composite on previous frame
                if let prev = previousFrame {
                    frameImage = compositeFrame(previous: prev, current: frameImage)
                }
            }

            let resized = downsampleIfNeeded(frameImage, maxPixelSize: maxPixelSize)
            frames.append(AnimationFrame(image: resized, delay: delay))

            if disposal != 3 {
                previousFrame = frameImage
            }
        }

        return frames.isEmpty ? nil : frames
    }

    private func compositeFrame(previous: CGImage, current: CGImage) -> CGImage {
        let width = max(previous.width, current.width)
        let height = max(previous.height, current.height)

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: previous.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return current }

        ctx.draw(previous, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(current, in: CGRect(x: 0, y: 0, width: current.width, height: current.height))
        return ctx.makeImage() ?? current
    }

    private func downsampleIfNeeded(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let maxDim = max(w, h)
        guard maxDim > maxPixelSize else { return image }

        let scale = maxPixelSize / maxDim
        let targetWidth = Int((w * scale).rounded())
        let targetHeight = Int((h * scale).rounded())

        let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        )
        guard let ctx = context else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage() ?? image
    }
}
