import Foundation

public struct FolderScanner: Sendable {

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
        FileItem.supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Check if a URL is a ZIP/CBZ archive.
    public static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }
}
