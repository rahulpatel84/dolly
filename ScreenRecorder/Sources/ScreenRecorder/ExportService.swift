import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Export to a user-chosen location and format, and rename-with-sidecars.
enum ExportService {

    enum Format: String, CaseIterable, Identifiable {
        case mov = "QuickTime (.mov)"
        case mp4 = "MP4 (.mp4)"
        case mp4Muted = "MP4, no audio"
        case mp4Compressed = "MP4, compressed H.264 1080p"
        case m4a = "Audio only (.m4a)"
        case gif = "Animated GIF (.gif)"
        var id: String { rawValue }
        var ext: String {
            switch self {
            case .mov: return "mov"
            case .mp4, .mp4Muted, .mp4Compressed: return "mp4"
            case .m4a: return "m4a"
            case .gif: return "gif"
            }
        }
        var type: UTType {
            switch self {
            case .mov: return .quickTimeMovie
            case .mp4, .mp4Muted, .mp4Compressed: return .mpeg4Movie
            case .m4a: return .mpeg4Audio
            case .gif: return .gif
            }
        }
    }

    /// Composition with only the chosen track types, for mute / audio-only.
    private static func composition(of source: URL, video: Bool, audio: Bool) async throws -> AVMutableComposition {
        let asset = AVURLAsset(url: source)
        let comp = AVMutableComposition()
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        if video, let v = try await asset.loadTracks(withMediaType: .video).first {
            let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try t.insertTimeRange(range, of: v, at: .zero)
            t.preferredTransform = try await v.load(.preferredTransform)
        }
        if audio {
            for a in try await asset.loadTracks(withMediaType: .audio) {
                let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
                try? t.insertTimeRange(range, of: a, at: .zero)
            }
        }
        return comp
    }

    private static func run(_ session: AVAssetExportSession, to url: URL, as type: AVFileType) async throws {
        session.outputURL = url
        session.outputFileType = type
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export failed."])
        }
    }

    /// Shows a save panel and exports. Returns the written URL, or nil if cancelled.
    @MainActor
    static func export(
        source: URL, suggestedName: String, format: Format,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = "\(suggestedName).\(format.ext)"
        panel.canCreateDirectories = true
        panel.title = "Export Recording"
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        try? FileManager.default.removeItem(at: destination)

        switch format {
        case .mov:
            try FileManager.default.copyItem(at: source, to: destination)
            progress?(1)
        case .mp4:
            // Container change only: HEVC/AAC pass straight through, no re-encode.
            guard let session = AVAssetExportSession(
                asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough)
            else { throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "No passthrough preset."]) }
            session.outputURL = destination
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else {
                throw session.error ?? NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "MP4 export failed."])
            }
            progress?(1)
        case .mp4Muted:
            let comp = try await composition(of: source, video: true, audio: false)
            guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw NSError(domain: "Export", code: 1) }
            try await run(session, to: destination, as: .mp4)
            progress?(1)
        case .mp4Compressed:
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPreset1920x1080) else { throw NSError(domain: "Export", code: 1) }
            try await run(session, to: destination, as: .mp4)
            progress?(1)
        case .m4a:
            let comp = try await composition(of: source, video: false, audio: true)
            guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else { throw NSError(domain: "Export", code: 1) }
            try await run(session, to: destination, as: .m4a)
            progress?(1)
        case .gif:
            let tmp = try await GifExporter.export(videoURL: source, progress: progress)
            try FileManager.default.moveItem(at: tmp, to: destination)
        }
        return destination
    }

    /// Renames a recording and every sidecar that belongs to it.
    static func rename(_ recording: Recording, to newName: String) throws -> URL {
        let dir = recording.url.deletingLastPathComponent()
        let cleaned = newName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return recording.url }
        let fm = FileManager.default
        let pairs: [(URL, URL)] = [
            (recording.url, dir.appendingPathComponent("\(cleaned).mov")),
            (PolishExporter.telemetryURL(for: recording.url), dir.appendingPathComponent("\(cleaned).telemetry.json")),
            (WebcamRecorder.sidecarURL(for: recording.url), dir.appendingPathComponent("\(cleaned).webcam.mov")),
            (PolishExporter.outputURL(for: recording.url), dir.appendingPathComponent("\(cleaned) (polished).mov")),
        ]
        guard !fm.fileExists(atPath: pairs[0].1.path) else {
            throw NSError(domain: "Rename", code: 1, userInfo: [NSLocalizedDescriptionKey: "A recording with that name already exists."])
        }
        for (from, to) in pairs where fm.fileExists(atPath: from.path) {
            try fm.moveItem(at: from, to: to)
        }
        return pairs[0].1
    }
}
