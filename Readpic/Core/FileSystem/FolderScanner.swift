import Foundation

public struct FolderScanner: Sendable {
    private static let supportedExtensions: Set<String> = [
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

    public init() {}

    public func scanFolder(_ folderURL: URL, sortMode: SortMode = .name) async throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let items = urls.compactMap { url -> FileItem? in
            guard Self.supports(url) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileItem(
                url: url,
                fileSize: Int64(values?.fileSize ?? 0),
                modificationDate: values?.contentModificationDate
            )
        }

        return FileSorter.sort(items, by: sortMode)
    }

    public static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
