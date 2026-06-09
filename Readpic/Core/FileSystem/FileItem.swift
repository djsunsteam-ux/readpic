import Foundation

public struct FileItem: Identifiable, Equatable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let fileSize: Int64
    public let modificationDate: Date?
    /// Relative folder path from the scan root (empty for root-level files).
    /// e.g. "vacation/beach" for a file inside /root/vacation/beach/
    public let relativeFolder: String

    public static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png",
        "heic", "heif", "webp", "gif", "tiff", "tif", "bmp", "ico",
        // RAW
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf",
        "srw", "pef", "srf", "sr2", "3fr", "fff", "x3f", "mef", "mos",
        // AVIF
        "avif",
        // PSD
        "psd", "psb",
    ]

    public init(url: URL, fileSize: Int64 = 0, modificationDate: Date? = nil, relativeFolder: String = "") {
        self.url = url
        self.id = url
        self.name = url.lastPathComponent
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.relativeFolder = relativeFolder
    }
}
