import Foundation

public struct FileItem: Identifiable, Equatable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let fileSize: Int64
    public let modificationDate: Date?

    public init(url: URL, fileSize: Int64 = 0, modificationDate: Date? = nil) {
        self.url = url
        self.id = url
        self.name = url.lastPathComponent
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}
