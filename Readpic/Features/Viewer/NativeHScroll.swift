import AppKit
import SwiftUI

/// A horizontal NSScrollView hosting SwiftUI content.
/// Click-drag scrolling via a transparent overlay that forwards taps to the content.
struct NativeHScroll<Content: View>: NSViewRepresentable {
    /// Index to scroll to on appear. Item width = 80 + 4 spacing = 84.
    var scrollToIndex: Int = -1
    @ViewBuilder let content: Content
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        hosting.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor).isActive = true
        hosting.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor).isActive = true
        hosting.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor).isActive = true

        // Overlay captures drag; taps are forwarded by temporarily hiding the overlay.
        let overlay = DragOverlay()
        overlay.scrollView = scrollView
        overlay.hostingView = hosting
        overlay.onScrollStart = onScrollStart
        overlay.onScrollEnd = onScrollEnd
        overlay.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            overlay.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            overlay.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        // Scroll to initial index after layout
        if scrollToIndex >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.scrollToItem(scrollView, index: scrollToIndex)
            }
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hosting = nsView.documentView as? NSHostingView<Content>,
              let overlay = nsView.contentView.subviews.first(where: { $0 is DragOverlay }) as? DragOverlay
        else { return }
        hosting.rootView = content
        overlay.scrollView = nsView
        overlay.hostingView = hosting
        overlay.onScrollStart = onScrollStart
        overlay.onScrollEnd = onScrollEnd

        // Scroll to index when it changes
        if scrollToIndex >= 0, scrollToIndex != context.coordinator.lastScrollIndex {
            context.coordinator.lastScrollIndex = scrollToIndex
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.scrollToItem(nsView, index: scrollToIndex)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastScrollIndex: Int = -1
    }

    /// Scroll NSScrollView to center the item at the given index.
    /// Item width = 80 + 4 spacing = 84, plus 8pt leading padding.
    private static func scrollToItem(_ scrollView: NSScrollView, index: Int) {
        let itemWidth: CGFloat = 84 // 80 + 4 spacing
        let padding: CGFloat = 8
        let targetX = padding + CGFloat(index) * itemWidth - (scrollView.bounds.width / 2) + (itemWidth / 2)
        let maxX = max(0, (scrollView.documentView?.bounds.width ?? 0) - scrollView.bounds.width)
        let clampedX = min(max(0, targetX), maxX)
        scrollView.contentView.scroll(NSPoint(x: clampedX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

extension NativeHScroll {
    func onScrollStart(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.onScrollStart = action
        return copy
    }
    func onScrollEnd(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.onScrollEnd = action
        return copy
    }
}

// MARK: - Drag overlay

private class DragOverlay: NSView {
    weak var scrollView: NSScrollView?
    weak var hostingView: NSView?
    var onScrollStart: (() -> Void)?
    var onScrollEnd: (() -> Void)?
    private var isDragging = false
    private var dragDistance: CGFloat = 0

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sv = scrollView else { return }
        dragDistance += abs(event.deltaX)
        if dragDistance > 4 {
            if !isDragging { isDragging = true; onScrollStart?() }
            let newX = sv.contentView.bounds.origin.x - event.deltaX
            sv.contentView.scroll(NSPoint(x: newX, y: 0))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onScrollEnd?()
        } else {
            // Forward tap: temporarily hide overlay, post synthetic events.
            let win = event.windowNumber
            let loc = event.locationInWindow
            let ts = event.timestamp
            let sup = superview
            self.removeFromSuperview()
            defer { sup?.addSubview(self) }

            NSEvent.mouseEvent(with: .leftMouseDown, location: loc,
                modifierFlags: [], timestamp: ts + 0.001, windowNumber: win,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                .map { NSApplication.shared.sendEvent($0) }

            NSEvent.mouseEvent(with: .leftMouseUp, location: loc,
                modifierFlags: [], timestamp: ts + 0.002, windowNumber: win,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                .map { NSApplication.shared.sendEvent($0) }
        }
    }
}
