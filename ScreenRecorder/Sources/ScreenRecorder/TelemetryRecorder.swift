import AppKit
import Foundation

/// Records where the cursor went and when it was clicked, as a sidecar file
/// beside the video. Nothing is drawn during capture.
///
/// This is the foundation for automatic zoom, cursor smoothing and click
/// emphasis. Those effects are only possible because this data is kept
/// separate from the pixels instead of being burned into them.
///
/// Deliberately uses polling rather than CGEventTap: sampling
/// NSEvent.mouseLocation and pressedMouseButtons needs no Accessibility or
/// Input Monitoring permission at all. Keystroke display would need a tap,
/// and with it a permission prompt -- a cost worth deferring.
final class TelemetryRecorder {

    struct Sample: Codable {
        /// Seconds since recording start.
        let t: Double
        let x: Double
        let y: Double
        /// True on the sample where a press began.
        let click: Bool
    }

    struct Sidecar: Codable {
        let version: Int
        let recordingStartedAt: Date
        let sampleRateHz: Int
        let displayPixelWidth: Int
        let displayPixelHeight: Int
        let samples: [Sample]
    }

    private var samples: [Sample] = []
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "telemetry.sampler")
    private var startedAt: Date?
    private var startTime: CFAbsoluteTime = 0
    private var lastButtonsDown = false
    private var paused = false
    private var pausedTotal: Double = 0
    private var pauseBegan: CFAbsoluteTime = 0

    func pause() {
        queue.sync {
            guard !paused else { return }
            paused = true
            pauseBegan = CFAbsoluteTimeGetCurrent()
        }
    }

    func resume() {
        queue.sync {
            guard paused else { return }
            pausedTotal += CFAbsoluteTimeGetCurrent() - pauseBegan
            paused = false
        }
    }

    private let sampleRateHz = 60
    private let pixelWidth: Int
    private let pixelHeight: Int
    /// Bounds of the display actually being captured, in points, top-left
    /// origin, in CoreGraphics global space.
    private let displayBounds: CGRect

    init(pixelWidth: Int, pixelHeight: Int, displayBounds: CGRect) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayBounds = displayBounds
    }

    func start() {
        queue.sync {
            samples.removeAll()
            startedAt = Date()
            startTime = CFAbsoluteTimeGetCurrent()
            lastButtonsDown = false
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(sampleRateHz))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    private func sample() {
        guard !paused else { return }
        let location = NSEvent.mouseLocation
        let buttonsDown = NSEvent.pressedMouseButtons != 0
        // Record the leading edge only. A held button is one click, not sixty.
        let isNewClick = buttonsDown && !lastButtonsDown
        lastButtonsDown = buttonsDown

        // NSEvent.mouseLocation is AppKit global space: points, bottom-left
        // origin of the PRIMARY display. Video frames are top-left origin
        // pixels of the CAPTURED display, which on a multi-display setup is a
        // different screen entirely. Convert through CoreGraphics global space
        // and scale by the captured display's own pixel ratio -- not
        // NSScreen.main's, which may belong to another monitor.
        guard let primary = NSScreen.screens.first else { return }
        let globalX = location.x
        let globalY = primary.frame.maxY - location.y

        let localX = globalX - displayBounds.minX
        let localY = globalY - displayBounds.minY

        guard displayBounds.width > 0, displayBounds.height > 0 else { return }
        let scaleX = Double(pixelWidth) / displayBounds.width
        let scaleY = Double(pixelHeight) / displayBounds.height

        samples.append(
            Sample(
                t: CFAbsoluteTimeGetCurrent() - startTime - pausedTotal,
                x: localX * scaleX,
                y: localY * scaleY,
                click: isNewClick
            ))
    }

    /// Stops sampling and writes the sidecar next to the video.
    @discardableResult
    func stopAndWrite(besideVideoAt videoURL: URL) -> URL? {
        timer?.cancel()
        timer = nil

        var captured: [Sample] = []
        var started: Date?
        queue.sync {
            captured = samples
            started = startedAt
        }
        guard let started, !captured.isEmpty else { return nil }

        let sidecar = Sidecar(
            version: 1,
            recordingStartedAt: started,
            sampleRateHz: sampleRateHz,
            displayPixelWidth: pixelWidth,
            displayPixelHeight: pixelHeight,
            samples: captured
        )

        let url = videoURL.deletingPathExtension().appendingPathExtension("telemetry.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(sidecar).write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Telemetry write failed: \(error.localizedDescription)")
            return nil
        }
    }

    var clickCount: Int {
        queue.sync { samples.filter(\.click).count }
    }
}
