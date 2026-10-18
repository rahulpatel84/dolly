import AVFoundation
import CoreGraphics
import Foundation
import AppKit
import ScreenCaptureKit

/// Drives ScreenCaptureKit and feeds the writer.
///
/// One stream delivers video, system audio and (on macOS 15+) the microphone.
/// Capturing system audio used to need a kernel extension or a virtual device
/// like BlackHole; since macOS 13 it is one configuration flag.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {

    enum CaptureError: Error, LocalizedError {
        case noDisplay
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display available to capture."
            case .alreadyRecording: return "A recording is already running."
            }
        }
    }

    struct Result {
        let videoURL: URL
        let telemetryURL: URL?
        let webcamURL: URL?
        let duration: TimeInterval
        let framesWritten: Int
        let framesDropped: Int
        let clickCount: Int
    }

    private(set) var isRecording = false
    private(set) var isPaused = false

    struct Options {
        var captureMicrophone = false
        var frameRate = 60
        var qualityFactor = 1.0
        var webcam = false
        var webcamDeviceID = ""
        /// NSWindow.windowNumber of the drawing overlay to KEEP in the capture.
        var overlayWindowNumber: Int?
    }

    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var telemetry: TelemetryRecorder?
    private var clock: RecordingClock?
    private var webcam: WebcamRecorder?
    private var startedAt: Date?
    private var currentURL: URL?

    private let videoQueue = DispatchQueue(label: "capture.video", qos: .userInitiated)
    private let systemAudioQueue = DispatchQueue(label: "capture.audio.system", qos: .userInitiated)
    private let micQueue = DispatchQueue(label: "capture.audio.mic", qos: .userInitiated)

    /// Frames ScreenCaptureKit told us it had nothing new to send. These are
    /// not failures -- the screen simply did not change.
    private var idleFrames = 0

    /// Called when ScreenCaptureKit ends the stream on its own. The file has
    /// already been finalised by the time this fires; `result` is nil only if
    /// nothing had been written yet.
    var onUnexpectedStop: ((Error, Result?) -> Void)?

    /// Persistent log so an unexpected stop can be diagnosed after the fact.
    static func log(_ message: String) {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ScreenRecorder.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        NSLog("%@", message)
    }

    // MARK: - Start

    func start(target: CaptureTarget, captureMicrophone: Bool) async throws -> URL {
        try await start(target: target, options: Options(captureMicrophone: captureMicrophone))
    }

    func start(target: CaptureTarget, options: Options) async throws -> URL {
        guard !isRecording else { throw CaptureError.alreadyRecording }
        let captureMicrophone = options.captureMicrophone

        let ownBundleID = Bundle.main.bundleIdentifier
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let excluded = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        // Our own windows are excluded, except the drawing overlay.
        let keep = content.windows.filter { w in options.overlayWindowNumber == Int(w.windowID) }

        let filter: SCContentFilter
        let pixelWidth: Int
        let pixelHeight: Int
        // Region of the captured surface that telemetry coordinates map onto,
        // in CoreGraphics global points, top-left origin.
        let telemetryBounds: CGRect
        var sourceRect: CGRect?

        switch target {
        case .display(let display):
            filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: keep)
            (pixelWidth, pixelHeight) = display.pixelSize
            telemetryBounds = CGDisplayBounds(display.displayID)

        case .region(let display, let rect):
            filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: keep)
            let bounds = CGDisplayBounds(display.displayID)
            let (dw, _) = display.pixelSize
            let scale = bounds.width > 0 ? Double(dw) / bounds.width : 1
            // sourceRect is expressed in the display's own point space.
            sourceRect = rect
            // Encoders reject odd dimensions, so round to even.
            pixelWidth = max(2, Int((rect.width * scale / 2).rounded()) * 2)
            pixelHeight = max(2, Int((rect.height * scale / 2).rounded()) * 2)
            telemetryBounds = CGRect(
                x: bounds.minX + rect.minX, y: bounds.minY + rect.minY,
                width: rect.width, height: rect.height)

        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            let frame = window.frame
            let scale =
                NSScreen.screens
                .first { $0.frame.intersects(frame) }?.backingScaleFactor ?? 2
            pixelWidth = max(2, Int((frame.width * scale / 2).rounded()) * 2)
            pixelHeight = max(2, Int((frame.height * scale / 2).rounded()) * 2)
            telemetryBounds = frame
        }

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // A deeper queue absorbs brief encoder stalls instead of dropping frames.
        config.queueDepth = 8
        if let sourceRect {
            config.sourceRect = sourceRect
            config.destinationRect = CGRect(
                x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight))
        }

        var micEnabled = false
        if captureMicrophone, #available(macOS 15.0, *) {
            config.captureMicrophone = true
            micEnabled = true
        }

        let url = Self.makeOutputURL()
        let clock = RecordingClock()
        let writer = try RecordingWriter(
            outputURL: url, width: pixelWidth, height: pixelHeight, includeMicrophone: micEnabled,
            clock: clock, frameRate: options.frameRate, qualityFactor: options.qualityFactor)

        let telemetry = TelemetryRecorder(
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, displayBounds: telemetryBounds)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: systemAudioQueue)
        if micEnabled, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQueue)
        }

        self.writer = writer
        self.telemetry = telemetry
        self.stream = stream
        self.clock = clock
        self.currentURL = url

        if options.webcam {
            let cam = WebcamRecorder()
            do {
                try cam.start(
                    besideVideoAt: url, deviceID: options.webcamDeviceID, clock: clock)
                self.webcam = cam
            } catch {
                // A missing camera should not abort a screen recording.
                NSLog("Webcam unavailable: \(error.localizedDescription)")
            }
        }

        try await stream.startCapture()

        telemetry.start()
        startedAt = Date()
        idleFrames = 0
        isRecording = true
        isPaused = false
        return url
    }

    // MARK: - Pause / resume

    func pause() {
        guard isRecording, !isPaused, let clock else { return }
        clock.pause()
        telemetry?.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused, let clock else { return }
        clock.resume()
        telemetry?.resume()
        isPaused = false
    }

    // MARK: - Stop

    func stop() async -> Result? {
        guard isRecording, let stream else { return nil }
        isRecording = false
        // Resume first so a recording stopped while paused still finalises
        // with consistent timestamps.
        if isPaused { resume() }
        Self.log("stop: stopping capture")
        // Bounded: during app termination SCStream's completion was observed
        // never to arrive, which left the writer un-finalised. The writer
        // ignores late frames once closed, so finalising after a short wait is safe.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await stream.stopCapture() }
            group.addTask { try? await Task.sleep(nanoseconds: 2_500_000_000) }
            await group.next()
            group.cancelAll()
        }
        Self.log("stop: finalising writer")
        let result = await finalize()
        Self.log("stop: done — \(result?.videoURL.lastPathComponent ?? "nothing"), frames \(result?.framesWritten ?? 0)")
        return result
    }

    /// Termination path. No Swift concurrency: during NSApplication.terminate
    /// the main-actor executor never gets to run, so an async stop() silently
    /// never starts. Everything here is completion handlers and semaphores,
    /// each bounded, so quitting can never hang and the file always gets
    /// its moov atom.
    func stopSynchronously() -> Result? {
        guard isRecording, let stream, let writer, let url = currentURL else { return nil }
        isRecording = false
        if isPaused { resume() }
        Self.log("quit: stopping capture (sync)")
        let stopped = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in stopped.signal() }
        _ = stopped.wait(timeout: .now() + 2.5)
        Self.log("quit: finalising writer (sync)")
        let ok = writer.finishSynchronously()
        let webcamURL = webcam?.stopSynchronously()
        let telemetryURL = telemetry?.stopAndWrite(besideVideoAt: url)
        let clicks = telemetry?.clickCount ?? 0
        let paused = clock?.pausedSeconds ?? 0
        let duration = (startedAt.map { Date().timeIntervalSince($0) } ?? 0) - paused
        Self.log("quit: done ok=\(ok) — \(url.lastPathComponent), frames \(writer.framesWritten)")
        let result = Result(videoURL: url, telemetryURL: telemetryURL, webcamURL: webcamURL, duration: duration,
                            framesWritten: writer.framesWritten, framesDropped: writer.framesDropped, clickCount: clicks)
        self.stream = nil; self.writer = nil; self.telemetry = nil; self.webcam = nil; self.clock = nil
        self.startedAt = nil; self.currentURL = nil
        return result
    }

    /// Finalises the writer, webcam and telemetry regardless of how the
    /// stream ended. Without this on the unexpected-stop path, the file was
    /// left without a moov atom and no sidecar was written -- unplayable, and
    /// unpolishable.
    private func finalize() async -> Result? {
        guard let writer, let url = currentURL else { return nil }
        await writer.finish()
        let webcamURL = await webcam?.stop()

        let telemetryURL = telemetry?.stopAndWrite(besideVideoAt: url)
        let clicks = telemetry?.clickCount ?? 0
        let paused = clock?.pausedSeconds ?? 0
        let duration = (startedAt.map { Date().timeIntervalSince($0) } ?? 0) - paused

        let result = Result(
            videoURL: url,
            telemetryURL: telemetryURL,
            webcamURL: webcamURL,
            duration: duration,
            framesWritten: writer.framesWritten,
            framesDropped: writer.framesDropped,
            clickCount: clicks
        )

        self.stream = nil
        self.writer = nil
        self.telemetry = nil
        self.webcam = nil
        self.clock = nil
        self.startedAt = nil
        self.currentURL = nil
        return result
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer), let writer else { return }

        switch type {
        case .screen:
            // ScreenCaptureKit marks frames where nothing changed as .idle and
            // still delivers them. Writing those would bloat the file.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                let raw = attachments.first?[.status] as? Int,
                let status = SCFrameStatus(rawValue: raw)
            else { return }

            guard status == .complete else {
                if status == .idle { idleFrames += 1 }
                return
            }
            writer.appendVideo(sampleBuffer)

        case .audio:
            writer.appendSystemAudio(sampleBuffer)

        default:
            if #available(macOS 15.0, *), type == .microphone {
                writer.appendMicrophone(sampleBuffer)
            }
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isRecording else { return }
        isRecording = false
        let ns = error as NSError
        Self.log("ScreenCaptureKit stopped the stream: \(ns.domain) \(ns.code) — \(ns.localizedDescription)")
        Task {
            if isPaused { resume() }
            let result = await finalize()
            Self.log("Finalised after unexpected stop: \(result?.videoURL.lastPathComponent ?? "nothing written"), frames \(result?.framesWritten ?? 0)")
            onUnexpectedStop?(error, result)
        }
    }

    /// For --selftest-unexpected-stop: drive the same path SCK uses.
    func simulateUnexpectedStop() {
        guard let stream else { return }
        let error = NSError(
            domain: "ScreenRecorder.SelfTest", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated ScreenCaptureKit stop"])
        Task { try? await stream.stopCapture() }
        self.stream(stream, didStopWithError: error)
    }

    // MARK: - Output location

    static func recordingsDirectory() -> URL {
        // Showcase / tests point the library elsewhere so personal files stay out.
        if let override = ProcessInfo.processInfo.environment["DOLLY_RECORDINGS_DIR"], !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Screen Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        // Pin the locale. Without this, DateFormatter honours the user's
        // 12-hour regional setting and rewrites "HH" as "h.mm.ss a",
        // producing filenames containing a narrow no-break space (U+202F)
        // that break shell globbing and anything parsing the name.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Recording \(formatter.string(from: Date())).mov"
        return recordingsDirectory().appendingPathComponent(name)
    }
}
