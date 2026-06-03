import AppKit
import Foundation

struct ShareService {
    func share(_ url: URL, in view: NSView) {
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
