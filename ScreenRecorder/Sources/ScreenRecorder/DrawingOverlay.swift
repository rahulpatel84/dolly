import AppKit
import Foundation

/// Transparent full-screen layer you can draw on while recording.
///
/// This is the one place effects ARE burned into the recording, on purpose:
/// live annotation while presenting is the use case. The window is created
/// before the stream starts and passed to ScreenCaptureKit as an exception to
/// the "exclude our own app" rule, so it is captured while the rest of the UI
/// is not.
@MainActor
final class DrawingOverlay {
    private(set) var window: NSWindow?
    private var view: StrokeView?
    private(set) var isDrawing = false
    var onToggle: ((Bool) -> Void)?

    /// Creates the (click-through, invisible) window on the given screen.
    func prepare(on screen: NSScreen) {
        if window != nil { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        let v = StrokeView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.onEscape = { [weak self] in self?.setDrawing(false) }
        w.contentView = v
        w.orderFrontRegardless()
        window = w
        view = v
    }

    var windowNumber: Int? { window?.windowNumber }

    func setDrawing(_ on: Bool) {
        guard let window else { return }
        isDrawing = on
        window.ignoresMouseEvents = !on
        if on {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSCursor.crosshair.push()
        } else {
            NSCursor.pop()
        }
        view?.showHint = on
        view?.needsDisplay = true
        onToggle?(on)
    }

    func toggle() { setDrawing(!isDrawing) }
    func clear() { view?.strokes.removeAll(); view?.needsDisplay = true }

    func tearDown() {
        if isDrawing { NSCursor.pop() }
        isDrawing = false
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}

final class StrokeView: NSView {
    var strokes: [NSBezierPath] = []
    var current: NSBezierPath?
    var showHint = false
    var onEscape: (() -> Void)?
    var color: NSColor = .systemRed
    var width: CGFloat = 5

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p)
        current = path
    }
    override func mouseDragged(with event: NSEvent) {
        current?.line(to: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let c = current { strokes.append(c) }
        current = nil
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()                                // Esc: stop drawing
        case 8: strokes.removeAll(); needsDisplay = true    // C: clear
        case 6: if event.modifierFlags.contains(.command) { _ = strokes.popLast(); needsDisplay = true } // ⌘Z
        default: break
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        color.setStroke()
        for s in strokes { s.stroke() }
        current?.stroke()
        if showHint {
            let hint = "Drawing on screen · Esc to stop · C to clear · ⌘Z undo"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            let sz = hint.size(withAttributes: attrs)
            let box = NSRect(x: bounds.midX - sz.width / 2 - 10, y: bounds.maxY - 44, width: sz.width + 20, height: 26)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            hint.draw(at: NSPoint(x: box.minX + 10, y: box.minY + 6), withAttributes: attrs)
        }
    }
}
