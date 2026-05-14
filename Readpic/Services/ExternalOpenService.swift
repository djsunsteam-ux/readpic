import AppKit
import Foundation

struct ExternalOpenService {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
