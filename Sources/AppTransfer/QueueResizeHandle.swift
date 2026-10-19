import AppKit
import SwiftUI

/// AppKit owns the entire hit area and cursor, including while SwiftUI relayouts
/// the queue during a drag. Screen coordinates keep that moving origin stable.
struct QueueResizeHandle: NSViewRepresentable {
    static let height: CGFloat = 20
    var onHover: (Bool) -> Void
    var onBegin: () -> Void
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> ResizeView {
        let view = ResizeView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: ResizeView, context: Context) {
        view.onHover = onHover
        view.onBegin = onBegin
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class ResizeView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        var onBegin: () -> Void = {}
        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = {}
        private var tracking: NSTrackingArea?
        private var initialScreenY: CGFloat?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func updateTrackingAreas() {
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero,
                options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate, .mouseEnteredAndExited],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
            super.updateTrackingAreas()
        }

        override func cursorUpdate(with event: NSEvent) { NSCursor.resizeUpDown.set() }
        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        override func mouseDown(with event: NSEvent) {
            initialScreenY = screenY(event)
            onBegin()
            NSCursor.resizeUpDown.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let initialScreenY else { return }
            onChange(screenY(event) - initialScreenY)
            NSCursor.resizeUpDown.set()
        }

        override func mouseUp(with event: NSEvent) {
            guard let initialScreenY else { return }
            onChange(screenY(event) - initialScreenY)
            self.initialScreenY = nil
            onEnd()
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            onHover(inside)
            if inside { NSCursor.resizeUpDown.set() }
            window?.invalidateCursorRects(for: self)
        }

        private func screenY(_ event: NSEvent) -> CGFloat {
            window?.convertPoint(toScreen: event.locationInWindow).y ?? event.locationInWindow.y
        }
    }
}
