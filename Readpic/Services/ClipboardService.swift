import AppKit
import CoreGraphics
import Foundation

struct ClipboardService {
    func copyFilePath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func copyFile(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    func copyImage(_ image: CGImage) {
        NSPasteboard.general.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(size: NSSize(width: image.width, height: image.height))
        nsImage.addRepresentation(rep)
        NSPasteboard.general.writeObjects([nsImage])
    }
}
