import AppKit
import Foundation

/// Full-screen overlay for dragging out a capture region.
///
/// One borderless transparent window per display, above everything, so the
/// selection can start on any screen. Escape or a right-click cancels.
enum RegionChoice {
    /// A dragged rectangle in the screen's own coordinates, top-left origin, points.
    case region(NSScreen, CGRect)
    /// A single click: the point, same coordinate space. Callers capture the
    /// window under it, like the system's Cmd-Shift-4 + Space.
    case click(NSScreen, CGPoint)
}

@MainActor
final class RegionSelector {

    private var windows: [NSWindow] = []
    private var completion: (RegionChoice?) -> Void = { _ in }

    func present(completion: @escaping (RegionChoice?) -> Void) {
        self.completion = completion

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
                defer: false, screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.hasShadow = false

            // Force the full screen frame, menu bar and notch included. AppKit
            // may otherwise place the window below the menu bar, which would
            // shift every selection by the menu bar's height.
            window.setFrame(screen.frame, display: false)
            let view = RegionSelectionView(frame: NSRect(origin: .zero, size: window.frame.size))
            view.onFinish = { [weak self, weak window] rect in
                self?.finish(screen: screen, window: window, rect: rect)
            }
            view.onCancel = { [weak self] in self?.finish(screen: nil, window: nil, rect: nil) }
            window.contentView = view

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    private func finish(screen: NSScreen?, window: NSWindow?, rect: CGRect?) {
        NSCursor.pop()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()

        guard let screen, let window, let rect else { return completion(nil) }
        // Go through the window's REAL frame: window-local → global AppKit →
        // screen-local, top-left origin. This stays correct even if AppKit
        // placed the window somewhere other than the full screen frame.
        func toScreenTopLeft(_ p: CGPoint) -> CGPoint {
            let g = window.convertPoint(toScreen: p)
            return CGPoint(x: g.x - screen.frame.minX, y: screen.frame.maxY - g.y)
        }
        let tl = toScreenTopLeft(CGPoint(x: rect.minX, y: rect.maxY))
        let br = toScreenTopLeft(CGPoint(x: rect.maxX, y: rect.minY))
        if rect.width >= 8 || rect.height >= 8 {
            completion(.region(screen, CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)))
        } else {
            completion(.click(screen, tl))
        }
    }

    /// For --selftest-selector: where each overlay window actually landed.
    func debugFrames() -> [(screen: NSRect, window: NSRect)] {
        windows.compactMap { w in w.screen.map { ($0.frame, w.frame) } }
    }
}

private final class RegionSelectionView: NSView {

    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let selection { onFinish?(selection) }
        else if let start { onFinish?(CGRect(origin: start, size: .zero)) }  // a click
        else { onCancel?() }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }  // Escape
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let selection, selection.width > 0, selection.height > 0 else {
            drawHint()
            return
        }

        // Punch the selection clear so the user sees exactly what is captured.
        NSColor.clear.setFill()
        selection.fill(using: .copy)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var box = CGRect(
            x: selection.midX - size.width / 2 - pad,
            y: selection.minY - size.height - pad * 2 - 6,
            width: size.width + pad * 2, height: size.height + pad)
        if box.minY < 4 { box.origin.y = selection.maxY + 6 }

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad / 2), withAttributes: attrs)
    }

    private func drawHint() {
        let hint = "Drag to select an area  ·  click a window to capture it  ·  Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = hint.size(withAttributes: attrs)
        hint.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs)
    }
}
