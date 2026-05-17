import CoreGraphics
import Foundation
import ImageIO

public struct ImageMetadata: Equatable, Sendable {
    public let name: String
    public let path: String
    public let fileSize: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let pixelSize: CGSize
    public let format: String
    public let colorSpace: String
    public let bitDepth: Int?
    public let dateTaken: Date?
    public let camera: String?
    public let lens: String?
    public let iso: Int?
    public let aperture: Double?
    public let shutterSpeed: Double?

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var dimensionsText: String {
        "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    public var apertureText: String? {
        aperture.map { "ƒ/\(String(format: "%.1f", $0))" }
    }

    public var shutterText: String? {
        guard let s = shutterSpeed else { return nil }
        if s >= 1 {
            return "\(String(format: "%.0f", s))s"
        } else {
            let frac = Int((1 / s).rounded())
            return "1/\(frac)s"
        }
    }

    public var dateTakenText: String? {
        dateTaken.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) }
    }
}

public struct MetadataReader: Sendable {
    public init() {}

    public func read(url: URL, pixelSize: CGSize) -> ImageMetadata {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])

        let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let exif = readEXIF(source: source)

        let actualPixelSize: CGSize
        if pixelSize == .zero, let source,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
            let h = (props[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
            actualPixelSize = CGSize(width: w, height: h)
        } else {
            actualPixelSize = pixelSize
        }

        return ImageMetadata(
            name: url.lastPathComponent,
            path: url.path,
            fileSize: Int64(resourceValues?.fileSize ?? 0),
            createdAt: resourceValues?.creationDate,
            modifiedAt: resourceValues?.contentModificationDate,
            pixelSize: actualPixelSize,
            format: url.pathExtension.uppercased(),
            colorSpace: colorSpaceName(source: source),
            bitDepth: readBitDepth(source: source),
            dateTaken: exif.dateTaken,
            camera: exif.camera,
            lens: exif.lens,
            iso: exif.iso,
            aperture: exif.aperture,
            shutterSpeed: exif.shutterSpeed
        )
    }

    private func readEXIF(source: CGImageSource?) -> (dateTaken: Date?, camera: String?, lens: String?, iso: Int?, aperture: Double?, shutterSpeed: Double?) {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil, nil, nil, nil, nil)
        }

        let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let dateTaken: Date?
        if let dateStr = exifDict?[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            dateTaken = formatter.date(from: dateStr)
        } else {
            dateTaken = nil
        }

        let make = tiffDict?[kCGImagePropertyTIFFMake] as? String ?? ""
        let model = tiffDict?[kCGImagePropertyTIFFModel] as? String ?? ""
        let camera: String?
        if !make.isEmpty && !model.isEmpty {
            camera = "\(make) \(model)"
        } else if !model.isEmpty {
            camera = model
        } else if !make.isEmpty {
            camera = make
        } else {
            camera = nil
        }

        let lens = exifDict?[kCGImagePropertyExifLensModel] as? String

        let iso = (exifDict?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue

        let aperture = (exifDict?[kCGImagePropertyExifFNumber] as? Double)

        let shutterSpeed: Double?
        if let exposureTime = exifDict?[kCGImagePropertyExifExposureTime] as? Double {
            shutterSpeed = exposureTime
        } else {
            shutterSpeed = nil
        }

        return (dateTaken, camera, lens, iso, aperture, shutterSpeed)
    }

    private func colorSpaceName(source: CGImageSource?) -> String {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return "Unknown"
        }

        if let profileName = properties[kCGImagePropertyProfileName] as? String {
            return profileName
        }

        if let colorModel = properties[kCGImagePropertyColorModel] as? String {
            return colorModel
        }

        return "Unknown"
    }

    private func readBitDepth(source: CGImageSource?) -> Int? {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[kCGImagePropertyDepth] as? Int
    }
}
