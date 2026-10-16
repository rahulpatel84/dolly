import AppKit
import Foundation

/// A 3-2-1 countdown before capture starts.
///
/// Not decoration: without it the first second of every recording catches you
/// still moving the mouse away from the menu bar, which then has to be
/// trimmed off. The overlay excludes itself from capture by closing before
/// the stream starts.
@MainActor
final class CountdownOverlay {

    private var window: NSWindow?

    func run(from count: Int = 3, completion: @escaping () -> Void) {
        guard count > 0 else { return completion() }
        show(count)
        tick(count, completion: completion)
    }

    private func tick(_ remaining: Int, completion: @escaping () -> Void) {
        guard remaining > 0 else {
            dismiss()
            // One frame of breathing room so the overlay is definitely gone
            // from the screen before ScreenCaptureKit starts reading it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: completion)
            return
        }
        update(remaining)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.tick(remaining - 1, completion: completion)
        }
    }

    private func show(_ value: Int) {
        guard let screen = NSScreen.main else { return }
        let size: CGFloat = 180
        let frame = NSRect(
            x: screen.frame.midX - size / 2, y: screen.frame.midY - size / 2,
            width: size, height: size)

        let window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false

        let view = CountdownView(frame: NSRect(origin: .zero, size: frame.size))
        view.value = value
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
    }

    private func update(_ value: Int) {
        (window?.contentView as? CountdownView)?.value = value
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class CountdownView: NSView {
    var value: Int = 3 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 10, dy: 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 6, dy: 6))
        ring.lineWidth = 2
        ring.stroke()

        let text = "\(value)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 86, weight: .light),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attrs)
    }
}
