import AVFoundation
import CoreGraphics
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Animated GIF export.
///
/// AVAssetWriter cannot produce GIF, so frames are sampled and written through
/// ImageIO instead. Sampling is deliberately coarse: GIF is a 256-colour
/// format with per-frame palettes, so a full 60 fps export would be enormous
/// and look no better.
enum GifExporter {

    enum GifError: Error, LocalizedError {
        case noVideoTrack
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "That file has no video track."
            case .writeFailed: return "The GIF could not be written."
            }
        }
    }

    struct Settings {
        var framesPerSecond: Double = 12
        var maxWidth: CGFloat = 900
        /// Cap the output length; GIF size grows linearly with frames.
        var maxSeconds: Double = 30
        static let `default` = Settings()
    }

    static func outputURL(for videoURL: URL) -> URL {
        videoURL.deletingPathExtension().appendingPathExtension("gif")
    }

    static func export(
        videoURL: URL,
        settings: Settings = .default,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {

        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GifError.noVideoTrack
        }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let span = min(duration, settings.maxSeconds)
        let naturalSize = try await track.load(.naturalSize)

        let scale = min(1, settings.maxWidth / max(1, naturalSize.width))
        let outSize = CGSize(
            width: (naturalSize.width * scale).rounded(),
            height: (naturalSize.height * scale).rounded())

        let frameCount = max(1, Int(span * settings.framesPerSecond))
        let delay = 1.0 / settings.framesPerSecond

        let output = outputURL(for: videoURL)
        try? FileManager.default.removeItem(at: output)

        guard
            let dest = CGImageDestinationCreateWithURL(
                output as CFURL, UTType.gif.identifier as CFString, frameCount, nil)
        else { throw GifError.writeFailed }

        CGImageDestinationSetProperties(
            dest,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

        // Decode sequentially with AVAssetReader (hardware HEVC decode, no
        // per-frame seeking) and keep every Nth frame. Scaling via vImage.
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        trackOutput.alwaysCopiesSampleData = false
        reader.add(trackOutput)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: span, preferredTimescale: 600))
        guard reader.startReading() else { throw GifError.writeFailed }

        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .useSoftwareRenderer: false])
        var nextTime = 0.0
        var written = 0
        while written < frameCount, let sample = trackOutput.copyNextSampleBuffer() {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            guard t + 1e-6 >= nextTime, let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            nextTime += 1.0 / settings.framesPerSecond
            let ci = CIImage(cvPixelBuffer: pb)
            guard let full = ciContext.createCGImage(ci, from: ci.extent),
                  let small = FastImage.downscale(full, maxWidth: Int(outSize.width)) else { continue }
            CGImageDestinationAddImage(dest, small, frameProps)
            written += 1
            progress?(Double(written) / Double(frameCount))
        }
        reader.cancelReading()

        guard CGImageDestinationFinalize(dest) else { throw GifError.writeFailed }
        return output
    }
}
