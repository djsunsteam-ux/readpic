import Foundation

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private var entries: [(url: URL, image: DecodedImage)] = []
    private let maxCount = 5

    func get(_ url: URL) -> DecodedImage? {
        entries.first { $0.url == url }?.image
    }

    func set(_ image: DecodedImage) {
        if let index = entries.firstIndex(where: { $0.url == image.url }) {
            entries.remove(at: index)
        }
        entries.append((image.url, image))
        if entries.count > maxCount {
            entries.removeFirst()
        }
    }

    func remove(_ url: URL) {
        entries.removeAll { $0.url == url }
    }

    func clear() {
        entries.removeAll()
    }
}
