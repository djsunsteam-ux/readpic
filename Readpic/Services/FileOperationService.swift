import Foundation

struct TrashedFile: Equatable {
    let originalURL: URL
    let trashedURL: URL
}

enum FileOperationError: Error {
    case trashFailed
    case restoreDestinationExists
}

struct FileOperationService {
    func moveToTrash(_ url: URL) throws -> TrashedFile {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)

        guard let trashedURL = resultingURL as URL? else {
            throw FileOperationError.trashFailed
        }

        return TrashedFile(originalURL: url, trashedURL: trashedURL)
    }

    func restore(_ trashedFile: TrashedFile) throws {
        guard !FileManager.default.fileExists(atPath: trashedFile.originalURL.path) else {
            throw FileOperationError.restoreDestinationExists
        }

        try FileManager.default.moveItem(at: trashedFile.trashedURL, to: trashedFile.originalURL)
    }
}
