import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.delegate = context.coordinator
            onReady(window)
        }
        return view
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
