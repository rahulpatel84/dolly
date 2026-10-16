import AVFoundation
import Foundation
import ScreenCaptureKit

/// Audio-only recording to .m4a: system audio, plus the microphone as a
/// second track when enabled. Uses the same ScreenCaptureKit stream as video
/// capture with a 2×2 video configuration that is never written.
final class AudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var systemInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var started = false
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "audio.only")
    private(set) var outputURL: URL?
    private(set) var isRecording = false

    func start(includeMicrophone: Bool) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureEngine.CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        var mic = false
        if includeMicrophone, #available(macOS 15.0, *) { config.captureMicrophone = true; mic = true }

        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = CaptureEngine.recordingsDirectory().appendingPathComponent("Audio \(f.string(from: Date())).m4a")
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        let sys = AVAssetWriterInput(mediaType: .audio, outputSettings: settings); sys.expectsMediaDataInRealTime = true
        writer.add(sys)
        var micIn: AVAssetWriterInput?
        if mic {
            let m = AVAssetWriterInput(mediaType: .audio, outputSettings: settings); m.expectsMediaDataInRealTime = true
            writer.add(m); micIn = m
        }
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Audio", code: 1) }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if mic, #available(macOS 15.0, *) { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        self.writer = writer; self.systemInput = sys; self.micInput = micIn; self.stream = stream; self.outputURL = url
        try await stream.startCapture()
        isRecording = true
        return url
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sb), let writer else { return }
        lock.lock(); defer { lock.unlock() }
        if !started { writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb)); started = true }
        let input: AVAssetWriterInput?
        if type == .audio { input = systemInput }
        else if #available(macOS 15.0, *), type == .microphone { input = micInput }
        else { input = nil }
        if let input, input.isReadyForMoreMediaData { input.append(sb) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { isRecording = false }

    func stop() async -> URL? {
        guard isRecording, let stream, let writer else { return nil }
        isRecording = false
        try? await stream.stopCapture()
        lock.lock()
        let began = started
        systemInput?.markAsFinished(); micInput?.markAsFinished()
        lock.unlock()
        guard began else { writer.cancelWriting(); return nil }
        await writer.finishWriting()
        self.stream = nil
        return writer.status == .completed ? outputURL : nil
    }
}
