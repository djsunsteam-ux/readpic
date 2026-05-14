import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onReady(window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
