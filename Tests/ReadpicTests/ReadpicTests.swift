import XCTest
@testable import Readpic

final class ReadpicTests: XCTestCase {
    func testNaturalFileNameSorting() {
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/img_10.png")),
            FileItem(url: URL(fileURLWithPath: "/tmp/img_2.png")),
            FileItem(url: URL(fileURLWithPath: "/tmp/img_1.png"))
        ]

        let sortedNames = FileSorter.sortByName(items).map(\.name)

        XCTAssertEqual(sortedNames, ["img_1.png", "img_2.png", "img_10.png"])
    }

    func testSupportedImageExtensionsAreCaseInsensitive() {
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.jpeg")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.PNG")))
        XCTAssertTrue(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.gif")))
        XCTAssertFalse(FolderScanner.supports(URL(fileURLWithPath: "/tmp/a.svg")))
    }

    func testImageMetadataFileProperties() {
        let url = URL(fileURLWithPath: "/tmp/metadata_test.png")
        let metadata = MetadataReader().read(url: url, pixelSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(metadata.name, "metadata_test.png")
        XCTAssertEqual(metadata.format, "PNG")
        XCTAssertEqual(metadata.dimensionsText, "800 × 600")
    }

    func testFolderScannerFiltersAndSortsImages() async throws {
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        for name in ["img_10.png", "notes.txt", "img_2.JPG", "img_1.jpeg", "img_3.HEIC", "img_4.webp"] {
            FileManager.default.createFile(atPath: folderURL.appendingPathComponent(name).path, contents: Data())
        }

        let items = try await FolderScanner().scanFolder(folderURL)

        XCTAssertEqual(items.map(\.name), ["img_1.jpeg", "img_2.JPG", "img_3.HEIC", "img_4.webp", "img_10.png"])
    }
}
