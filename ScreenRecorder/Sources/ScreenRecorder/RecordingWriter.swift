import AVFoundation
import CoreMedia
import Foundation

/// Writes the clean recording: video plus up to two audio tracks.
/// No effects are baked in here by design -- see the architecture doc.
/// Zoom, cursor smoothing and click emphasis are applied later from the
/// telemetry sidecar, which is only possible because this stays clean.
final class RecordingWriter {

    enum WriterError: Error, LocalizedError {
        case couldNotStart(String)

        var errorDescription: String? {
            switch self {
            case .couldNotStart(let reason): return "Could not start writing: \(reason)"
            }
        }
    }

    let outputURL: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput
    private let micInput: AVAssetWriterInput

    /// Only inputs actually added to the writer. Calling markAsFinished() on
    /// an unattached input throws an ObjC exception and aborts the process,
    /// which leaves the file without a moov atom and therefore unplayable.
    private var attachedInputs: [AVAssetWriterInput] = []
    private let micAttached: Bool

    private let lock = NSLock()
    private let clock: RecordingClock
    private var sessionStarted = false
    private var finished = false

    private(set) var framesWritten = 0
    private(set) var framesDropped = 0

    init(
        outputURL: URL, width: Int, height: Int, includeMicrophone: Bool,
        clock: RecordingClock, frameRate: Int = 60, qualityFactor: Double = 1.0
    ) throws {
        self.outputURL = outputURL
        self.clock = clock

        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw WriterError.couldNotStart(error.localizedDescription)
        }

        // HEVC gives noticeably smaller files than H.264 for screen content,
        // which is mostly flat colour and sharp text. Hardware encoded on
        // Apple Silicon via VideoToolbox, so this is effectively free.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(
                    Double(Self.bitrate(forWidth: width, height: height)) * qualityFactor),
                AVVideoExpectedSourceFrameRateKey: frameRate,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput.expectsMediaDataInRealTime = true

        micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micInput.expectsMediaDataInRealTime = true

        var attached: [AVAssetWriterInput] = []
        for input in [videoInput, systemAudioInput] where writer.canAdd(input) {
            writer.add(input)
            attached.append(input)
        }
        if includeMicrophone, writer.canAdd(micInput) {
            writer.add(micInput)
            attached.append(micInput)
        }
        attachedInputs = attached
        micAttached = attached.contains(micInput)

        guard writer.startWriting() else {
            throw WriterError.couldNotStart(writer.error?.localizedDescription ?? "unknown")
        }
    }

    /// Screen-content bitrate. Screen recordings compress far better than
    /// camera footage, so these are deliberately lower than video defaults.
    private static func bitrate(forWidth width: Int, height: Int) -> Int {
        let pixels = width * height
        switch pixels {
        case ..<(1280 * 800): return 6_000_000
        case ..<(1920 * 1200): return 12_000_000
        case ..<(2880 * 1800): return 24_000_000
        default: return 40_000_000
        }
    }

    func appendVideo(_ captured: CMSampleBuffer) {
        // Dropped while paused; otherwise shifted to close the pause gap.
        guard let sampleBuffer = clock.retimed(captured) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }

        if videoInput.isReadyForMoreMediaData {
            if videoInput.append(sampleBuffer) {
                framesWritten += 1
            } else {
                framesDropped += 1
            }
        } else {
            // The encoder is behind. Dropping here is correct: blocking would
            // stall the capture queue and make the stutter worse.
            framesDropped += 1
        }
    }

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: systemAudioInput)
    }

    func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard micAttached else { return }
        append(sampleBuffer, to: micInput)
    }

    private func append(_ captured: CMSampleBuffer, to input: AVAssetWriterInput) {
        guard let sampleBuffer = clock.retimed(captured) else { return }
        lock.lock()
        defer { lock.unlock() }
        // Audio arriving before the first video frame has nowhere to go:
        // the session clock is not established yet.
        guard !finished, sessionStarted, input.isReadyForMoreMediaData else { return }
        _ = input.append(sampleBuffer)
    }

    /// Marks the writer closed and reports whether there is anything to flush.
    /// Synchronous on purpose: the lock must not be held across an await.
    private func closeInputs() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        guard sessionStarted else { return false }
        for input in attachedInputs {
            input.markAsFinished()
        }
        return true
    }

    /// Blocking variant for app termination, where no async executor runs.
    func finishSynchronously(timeout: TimeInterval = 10) -> Bool {
        guard closeInputs() else {
            if writer.status == .writing { writer.cancelWriting() }
            return false
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        return done.wait(timeout: .now() + timeout) == .success && writer.status == .completed
    }

    func finish() async {
        guard closeInputs() else {
            if writer.status == .writing { writer.cancelWriting() }
            return
        }
        await writer.finishWriting()
    }
}
