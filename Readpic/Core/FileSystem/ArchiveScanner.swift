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
    /// Supported image extensions inside archives.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png",
        "heic", "heif", "webp", "gif", "tiff", "tif", "bmp", "ico",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf",
        "srw", "pef", "srf", "sr2", "3fr", "fff", "x3f", "mef", "mos",
        "avif", "psd", "psb",
    ]

    /// An entry in the archive that can be displayed as an image.
    struct ArchiveEntry: Sendable {
        let path: String          // Path inside the archive
        let fileName: String      // Display name
        let fileSize: Int64
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
            guard imageExtensions.contains(ext) else { continue }
            // Skip macOS resource forks and hidden files
            let name = (entry.path as NSString).lastPathComponent
            guard !name.hasPrefix("._"), !name.hasPrefix(".") else { continue }

            entries.append(ArchiveEntry(
                path: entry.path,
                fileName: name,
                fileSize: Int64(entry.uncompressedSize)
            ))
        }

        switch sortMode {
        case .name:
            entries.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .date:
            entries.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        }

        return entries
        #else
        throw NSError(domain: "ArchiveScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "ZIP support not available"])
        #endif
    }

    /// Extract a single entry from the archive to a temporary location.
    func extractEntry(_ entryPath: String, from archiveURL: URL, to tempDir: URL) -> URL? {
        #if canImport(ZIPFoundation)
        guard let archive = try? Archive(url: archiveURL, accessMode: .read) else { return nil }
        guard let entry = archive[entryPath] else { return nil }

        let outputURL = tempDir.appendingPathComponent((entryPath as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        do {
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
