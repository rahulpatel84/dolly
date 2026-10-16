import AVFoundation
import Foundation

/// Finds the parts of a recording worth keeping, by cutting long silences.
///
/// Pure signal analysis over the first audio track: RMS per 50 ms window,
/// a run of windows under the threshold longer than `minSilence` is a cut,
/// with `padding` kept on either side so speech is never clipped.
enum SilenceDetector {

    static func keptRanges(
        asset: AVAsset, thresholdDB: Double, minSilence: Double, padding: Double
    ) async throws -> [CMTimeRange] {
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return [CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))]
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 16_000,
            ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "Silence", code: 1) }

        let window = 0.05
        let samplesPerWindow = Int(16_000 * window)
        var levels: [Double] = []
        var acc: Double = 0
        var count = 0

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            let floats = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: length / 4)
            for i in 0..<(length / 4) {
                let v = Double(floats[i])
                acc += v * v
                count += 1
                if count == samplesPerWindow {
                    levels.append(20 * log10(max(1e-9, sqrt(acc / Double(count)))))
                    acc = 0; count = 0
                }
            }
        }
        if count > 0 { levels.append(20 * log10(max(1e-9, sqrt(acc / Double(count))))) }

        // Silent runs.
        var cuts: [(Double, Double)] = []
        var runStart: Int?
        for (i, level) in levels.enumerated() {
            if level < thresholdDB {
                runStart = runStart ?? i
            } else if let start = runStart {
                let seconds = Double(i - start) * window
                if seconds >= minSilence {
                    cuts.append((Double(start) * window + padding, Double(i) * window - padding))
                }
                runStart = nil
            }
        }
        if let start = runStart, Double(levels.count - start) * window >= minSilence {
            cuts.append((Double(start) * window + padding, duration))
        }

        // Complement = kept.
        var kept: [CMTimeRange] = []
        var cursor = 0.0
        for (a, b) in cuts where b > a {
            if a > cursor + 0.05 {
                kept.append(CMTimeRange(
                    start: CMTime(seconds: cursor, preferredTimescale: 600),
                    end: CMTime(seconds: a, preferredTimescale: 600)))
            }
            cursor = b
        }
        if duration > cursor + 0.05 {
            kept.append(CMTimeRange(
                start: CMTime(seconds: cursor, preferredTimescale: 600),
                end: CMTime(seconds: duration, preferredTimescale: 600)))
        }
        return kept
    }
}
