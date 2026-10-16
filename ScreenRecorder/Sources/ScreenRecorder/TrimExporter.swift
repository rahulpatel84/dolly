import AVFoundation
import Foundation

/// Cuts a recording to a time range, and cuts its sidecars to match.
///
/// Passthrough export: no re-encode, so it is fast and lossless. The
/// telemetry and webcam files are trimmed too, with timestamps shifted, so
/// the trimmed recording can still be auto-zoomed and still gets its
/// picture-in-picture.
enum TrimExporter {

    enum TrimError: Error, LocalizedError {
        case badRange
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .badRange: return "The trim range is empty."
            case .exportFailed(let r): return "Trim failed: \(r)"
            }
        }
    }

    static func outputURL(for videoURL: URL) -> URL {
        let base = videoURL.deletingPathExtension().lastPathComponent
        return videoURL.deletingLastPathComponent()
            .appendingPathComponent("\(base) (trimmed).mov")
    }

    /// `remove`: cut the range OUT and join what is on either side.
    static func trim(videoURL: URL, start: Double, end: Double, remove: Bool = false) async throws -> URL {
        guard end - start > 0.1 else { throw TrimError.badRange }
        let output = outputURL(for: videoURL)
        if remove {
            let asset = AVURLAsset(url: videoURL)
            let total = CMTimeGetSeconds(try await asset.load(.duration))
            let kept = [(0.0, start), (end, total)].filter { $0.1 - $0.0 > 0.05 }
                .map { CMTimeRange(start: CMTime(seconds: $0.0, preferredTimescale: 600), end: CMTime(seconds: $0.1, preferredTimescale: 600)) }
            try await exportRanges(asset, ranges: kept, to: output)
            // Telemetry: keep both sides; shift the tail back by the cut length.
            let sidecarURL = PolishExporter.telemetryURL(for: videoURL)
            if let data = try? Data(contentsOf: sidecarURL),
               var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let samples = json["samples"] as? [[String: Any]] {
                json["samples"] = samples.compactMap { sample -> [String: Any]? in
                    guard let t = sample["t"] as? Double else { return nil }
                    if t < start { return sample }
                    if t >= end { var c = sample; c["t"] = t - (end - start); return c }
                    return nil
                }
                if let out = try? JSONSerialization.data(withJSONObject: json) {
                    try? out.write(to: PolishExporter.telemetryURL(for: output), options: .atomic)
                }
            }
            let webcamURL = WebcamRecorder.sidecarURL(for: videoURL)
            if FileManager.default.fileExists(atPath: webcamURL.path) {
                try? await exportRanges(AVURLAsset(url: webcamURL), ranges: kept, to: WebcamRecorder.sidecarURL(for: output))
            }
            return output
        }
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600))
        try await export(AVURLAsset(url: videoURL), range: range, to: output)

        // Telemetry: keep samples inside the range, rebase t to the new start.
        let sidecarURL = PolishExporter.telemetryURL(for: videoURL)
        if let data = try? Data(contentsOf: sidecarURL),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let samples = json["samples"] as? [[String: Any]]
        {
            let kept = samples.compactMap { sample -> [String: Any]? in
                guard let t = sample["t"] as? Double, t >= start, t <= end else { return nil }
                var copy = sample
                copy["t"] = t - start
                return copy
            }
            json["samples"] = kept
            if let out = try? JSONSerialization.data(withJSONObject: json) {
                try? out.write(to: PolishExporter.telemetryURL(for: output), options: .atomic)
            }
        }

        // Webcam: same range, so the two files stay aligned.
        let webcamURL = WebcamRecorder.sidecarURL(for: videoURL)
        if FileManager.default.fileExists(atPath: webcamURL.path) {
            try? await export(
                AVURLAsset(url: webcamURL), range: range,
                to: WebcamRecorder.sidecarURL(for: output))
        }

        return output
    }

    private static func exportRanges(_ asset: AVAsset, ranges: [CMTimeRange], to url: URL) async throws {
        let comp = AVMutableComposition()
        guard let v = try await asset.loadTracks(withMediaType: .video).first else { throw TrimError.badRange }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let ca = audio.map { _ in comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)! }
        var at = CMTime.zero
        for r in ranges {
            try cv.insertTimeRange(r, of: v, at: at)
            for (i, a) in audio.enumerated() { try? ca[i].insertTimeRange(r, of: a, at: at) }
            at = CMTimeAdd(at, r.duration)
        }
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            throw TrimError.exportFailed("no passthrough preset")
        }
        session.outputURL = url
        session.outputFileType = .mov
        await session.export()
        guard session.status == .completed else {
            throw TrimError.exportFailed(session.error?.localizedDescription ?? "unknown")
        }
    }

    private static func export(_ asset: AVAsset, range: CMTimeRange, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        guard
            let session = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetPassthrough)
        else { throw TrimError.exportFailed("no passthrough preset") }
        session.outputURL = url
        session.outputFileType = .mov
        session.timeRange = range
        await session.export()
        guard session.status == .completed else {
            throw TrimError.exportFailed(session.error?.localizedDescription ?? "unknown")
        }
    }
}
