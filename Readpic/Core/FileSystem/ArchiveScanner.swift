import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// Scans ZIP/CBZ archives and returns image entries as FileItem-compatible data.
struct ArchiveScanner: Sendable {
    /// Whether ZIP support is available (requires ZIPFoundation dependency).
    static var isAvailable: Bool {
        #if canImport(ZIPFoundation)
        return true
        #else
        return false
        #endif
    }

    /// An entry in the archive that can be displayed as an image.
    struct ArchiveEntry: Sendable {
        let path: String          // Path inside the archive
        let fileName: String      // Display name
        let fileSize: Int64
        let modificationDate: Date?
    }

    init() {}

    /// List image entries in a ZIP/CBZ archive, sorted by name.
    func scanArchive(_ archiveURL: URL, sortMode: SortMode = .name) throws -> [ArchiveEntry] {
        #if canImport(ZIPFoundation)
        let archive = try Archive(url: archiveURL, accessMode: .read)

        var entries: [ArchiveEntry] = []
        for entry in archive {
            guard entry.type == .file else { continue }
            let ext = (entry.path as NSString).pathExtension.lowercased()
            guard FileItem.supportedImageExtensions.contains(ext) else { continue }
            // Skip macOS resource forks and hidden files
            let name = (entry.path as NSString).lastPathComponent
            guard !name.hasPrefix("._"), !name.hasPrefix(".") else { continue }

            let modDate = entry.fileAttributes[.modificationDate] as? Date

            entries.append(ArchiveEntry(
                path: entry.path,
                fileName: name,
                fileSize: Int64(entry.uncompressedSize),
                modificationDate: modDate
            ))
        }

        switch sortMode {
        case .name:
            entries.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .date:
            entries.sort {
                let d0 = $0.modificationDate ?? .distantPast
                let d1 = $1.modificationDate ?? .distantPast
                if d0 != d1 { return d0 < d1 }
                return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
        }

        return entries
        #else
        throw NSError(domain: "ArchiveScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "ZIP support not available"])
        #endif
    }

    /// Extract a single entry from the archive to a temporary location.
    func extractEntry(_ entryPath: String, from archiveURL: URL, to tempDir: URL) -> URL? {
        #if canImport(ZIPFoundation)
        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            guard let entry = archive[entryPath] else { return nil }

            // Use a hash of the full path to avoid collisions (e.g. chapter1/image.jpg vs chapter2/image.jpg)
            let sanitized = entryPath.replacingOccurrences(of: "/", with: "_")
                                     .replacingOccurrences(of: "\\", with: "_")
            let outputURL = tempDir.appendingPathComponent(sanitized)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            }

            _ = try archive.extract(entry, to: outputURL)
            return outputURL
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Create a temporary directory for archive extraction.
    static func createTempDirectory(for archiveURL: URL) -> URL? {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.readpic/archive-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
            return tempBase
        } catch {
            return nil
        }
    }

    /// Clean up a temporary directory.
    static func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
