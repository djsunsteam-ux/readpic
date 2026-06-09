import Foundation

public struct FolderScanner: Sendable {

    /// Maximum recursion depth when scanning subfolders.
    private static let maxDepth = 10

    public init() {}

    /// Scan a folder for supported image files.
    /// - Parameters:
    ///   - folderURL: The root folder to scan.
    ///   - sortMode: How to sort results within each group.
    ///   - recursive: When `true`, descend into subfolders (up to `maxDepth` levels),
    ///     skip symlink cycles, and tag each `FileItem` with its `relativeFolder`.
    public func scanFolder(
        _ folderURL: URL,
        sortMode: SortMode = .name,
        recursive: Bool = false
    ) async throws -> [FileItem] {
        if recursive {
            return try scanRecursive(folderURL, sortMode: sortMode)
        }
        return try scanSingleLevel(folderURL, sortMode: sortMode)
    }

    // MARK: - Single-level scan (original behaviour)

    private func scanSingleLevel(_ folderURL: URL, sortMode: SortMode) throws -> [FileItem] {
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

    // MARK: - Recursive scan

    private func scanRecursive(_ folderURL: URL, sortMode: SortMode) throws -> [FileItem] {
        let fm = FileManager.default
        let rootPath = folderURL.standardizedFileURL.path
        let rootDepth = folderURL.pathComponents.count

        // Track visited real directories to detect symlink cycles.
        var visitedRealDirs: Set<String> = []
        do {
            let realRoot = try fm.destinationOfSymbolicLink(atPath: rootPath)
            visitedRealDirs.insert(realRoot)
        } catch {
            // Not a symlink — use the path itself.
            visitedRealDirs.insert(rootPath)
        }

        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                .fileSizeKey, .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var items: [FileItem] = []

        while let url = enumerator.nextObject() as? URL {
            // Safely read resource values; skip entries that fail.
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                .fileSizeKey, .contentModificationDateKey
            ]) else {
                continue
            }

            // Handle directories: depth-limit and symlink-cycle detection.
            if values.isDirectory == true {
                let depth = url.pathComponents.count - rootDepth
                if depth >= Self.maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                // Resolve symlinks for cycle detection.
                if values.isSymbolicLink == true {
                    let realPath: String
                    do {
                        realPath = try fm.destinationOfSymbolicLink(atPath: url.path)
                    } catch {
                        enumerator.skipDescendants()
                        continue
                    }
                    if visitedRealDirs.contains(realPath) {
                        enumerator.skipDescendants()
                        continue
                    }
                    visitedRealDirs.insert(realPath)
                }
                continue
            }

            // Only process supported image files.
            guard values.isRegularFile == true, Self.supports(url) else { continue }

            // Compute relativeFolder: the path of the file's parent relative to folderURL.
            let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
            let relativeFolder: String
            if parentPath == rootPath {
                relativeFolder = ""
            } else if parentPath.hasPrefix(rootPath + "/") {
                relativeFolder = String(parentPath.dropFirst(rootPath.count + 1))
            } else {
                relativeFolder = ""
            }

            items.append(FileItem(
                url: url,
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate,
                relativeFolder: relativeFolder
            ))
        }

        return FileSorter.sortGrouped(items, by: sortMode)
    }

    // MARK: - Helpers

    public static func supports(_ url: URL) -> Bool {
        FileItem.supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Check if a URL is a ZIP/CBZ archive.
    public static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "cbz"
    }
}
