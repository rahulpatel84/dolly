import AVFoundation
import AppKit
import CoreMedia
import Foundation

/// Records the camera to its own file, time-aligned with the screen capture.
///
/// Kept separate on purpose. Compositing the webcam live would bake it into
/// the screen pixels for good; as a sidecar file it can be placed, resized,
/// or dropped entirely at polish time, and the clean recording stays clean.
final class WebcamRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    static func availableCameras() -> [(id: String, name: String)] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        return discovery.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    static func sidecarURL(for videoURL: URL) -> URL {
        videoURL.deletingPathExtension().appendingPathExtension("webcam.mov")
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "webcam.frames", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false
    private var clock: RecordingClock?
    private let lock = NSLock()

    private(set) var outputURL: URL?
    private var preview: WebcamPreviewWindow?

    func start(besideVideoAt videoURL: URL, deviceID: String, clock: RecordingClock) throws {
        let device: AVCaptureDevice? =
            deviceID.isEmpty
            ? AVCaptureDevice.default(for: .video)
            : AVCaptureDevice(uniqueID: deviceID) ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw NSError(
            domain: "Webcam", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No camera is available."]) }

        let cameraInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(cameraInput) else {
            session.commitConfiguration()
            throw NSError(
                domain: "Webcam", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The camera could not be opened."])
        }
        session.addInput(cameraInput)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(
                domain: "Webcam", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The camera output could not be added."])
        }
        session.addOutput(output)
        session.commitConfiguration()

        let url = Self.sidecarURL(for: videoURL)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000],
            ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "Webcam", code: 4)
        }

        self.writer = writer
        self.input = input
        self.clock = clock
        self.outputURL = url

        queue.async { [session] in session.startRunning() }

        DispatchQueue.main.async { [weak self] in
            let preview = WebcamPreviewWindow(session: self?.session)
            preview.show()
            self?.preview = preview
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, let input, let clock,
            let retimed = clock.retimed(sampleBuffer)
        else { return }

        if !started {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(retimed))
            started = true
        }
        if input.isReadyForMoreMediaData {
            input.append(retimed)
        }
    }

    /// Hands the writer over synchronously; the lock must not span an await.
    private func detach() -> (AVAssetWriter, AVAssetWriterInput, Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let writer, let input else { return nil }
        let started = self.started
        self.writer = nil
        self.input = nil
        return (writer, input, started)
    }

    func stopSynchronously(timeout: TimeInterval = 5) -> URL? {
        DispatchQueue.main.async { [weak self] in self?.preview?.close(); self?.preview = nil }
        session.stopRunning()
        guard let (writer, input, started) = detach() else { return nil }
        guard started else {
            writer.cancelWriting()
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        _ = done.wait(timeout: .now() + timeout)
        return writer.status == .completed ? outputURL : nil
    }

    func stop() async -> URL? {
        DispatchQueue.main.async { [weak self] in
            self?.preview?.close()
            self?.preview = nil
        }
        session.stopRunning()

        guard let (writer, input, started) = detach() else { return nil }
        guard started else {
            writer.cancelWriting()
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? outputURL : nil
    }
}

/// Small always-on-top preview so the user can see they are in frame.
/// Excluded from the recording along with the rest of this app.
@MainActor
final class WebcamPreviewWindow {
    private let window: NSWindow

    init(session: AVCaptureSession?) {
        let size: CGFloat = 200
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(
            x: screen.maxX - size - 24, y: screen.minY + 24, width: size, height: size)
        window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = true

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = size / 2
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 3
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor

        if let session {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(layer)
        }
        window.contentView = view
    }

    func show() { window.orderFrontRegardless() }
    func close() { window.orderOut(nil) }
}
