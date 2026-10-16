import AVFoundation
import CoreImage
import Foundation

/// Sequential reader for the webcam sidecar, used during polish.
///
/// AVAssetExportSession renders frames in order, so a forward-only reader
/// with a one-frame lookahead is enough and avoids the cost of seeking the
/// webcam file once per output frame.
final class WebcamFrameSource {

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var pending: (time: Double, image: CIImage)?
    private var current: (time: Double, image: CIImage)?
    private var exhausted = false
    private let lock = NSLock()

    init?(url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        self.reader = reader
        self.output = output
    }

    /// Latest webcam frame at or before `time`.
    func image(at time: Double) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        while !exhausted {
            if pending == nil { pending = next() }
            guard let p = pending else { exhausted = true; break }
            if p.time <= time {
                current = p
                pending = nil
            } else {
                break
            }
        }
        return current?.image
    }

    private func next() -> (time: Double, image: CIImage)? {
        guard reader.status == .reading,
            let sample = output.copyNextSampleBuffer(),
            let pixels = CMSampleBufferGetImageBuffer(sample)
        else { return nil }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        return (t, CIImage(cvPixelBuffer: pixels))
    }
}
