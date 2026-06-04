import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = InnerView()
        view.onReady = onReady
        view.coordinator = context.coordinator
        return view
    }

    /// Custom NSView that applies window configuration as soon as it is
    /// attached to a window, before the first display pass.
    private class InnerView: NSView {
        var onReady: ((NSWindow) -> Void)?
        var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let callback = onReady else { return }
            window.delegate = coordinator
            callback(window)
            onReady = nil  // run once
        }
    }

    func updateNSView(_ view: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, NSWindowDelegate {
        private let mainWindowIdentifier = "mainWindow"

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow,
                  window.frameAutosaveName == mainWindowIdentifier else { return }
            NSApp.terminate(nil)
        }
    }
}
