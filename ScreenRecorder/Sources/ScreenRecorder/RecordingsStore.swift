import AVFoundation
import ImageIO
import AppKit
import Foundation

/// One recording on disk, with everything the dashboard needs to show it.
struct Recording: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let created: Date
    let bytes: Int
    var duration: Double?
    var hasTelemetry: Bool
    var isPolished: Bool
    var polishedURL: URL?
    /// True when AVFoundation cannot open the file: a recording that was
    /// never finalised (no moov atom). Unplayable and unrecoverable.
    var isDamaged = false

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var durationText: String {
        guard let duration else { return "—" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var createdText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: created)
    }
}

/// Reads the recordings folder. Deliberately stateless -- the folder on disk
/// is the source of truth, so files added or deleted outside the app are
/// picked up on the next scan.
enum RecordingsStore {

    static func scan() -> [Recording] {
        let dir = CaptureEngine.recordingsDirectory()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        let movies = entries.filter { $0.pathExtension.lowercased() == "mov" }
        // A polished file is a derived artifact, not a separate recording.
        let originals = movies.filter { !$0.lastPathComponent.contains("(polished)") }

        return
            originals
            .map { url -> Recording in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let polished = PolishExporter.outputURL(for: url)
                let hasPolished = FileManager.default.fileExists(atPath: polished.path)
                return Recording(
                    id: url,
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    created: values?.contentModificationDate ?? .distantPast,
                    bytes: values?.fileSize ?? 0,
                    duration: nil,
                    hasTelemetry: FileManager.default.fileExists(
                        atPath: PolishExporter.telemetryURL(for: url).path),
                    isPolished: hasPolished,
                    polishedURL: hasPolished ? polished : nil
                )
            }
            .sorted { $0.created > $1.created }
    }

    /// Durations need an async asset load, so they fill in after the list shows.
    static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(d)
        return seconds.isFinite ? seconds : nil
    }

    static func scanScreenshots() -> [Screenshot] {
        let dir = CaptureEngine.recordingsDirectory()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let v = try? url.resourceValues(forKeys: Set(keys))
                return Screenshot(id: url, url: url, name: url.deletingPathExtension().lastPathComponent,
                                  created: v?.contentModificationDate ?? .distantPast, bytes: v?.fileSize ?? 0)
            }
            .sorted { $0.created > $1.created }
    }

    /// Small thumbnail from an image file without decoding the full image.
    static func imageThumbnail(_ url: URL, maxPixel: Int = 640) async -> (image: NSImage, size: CGSize)? {
        await Task.detached(priority: .utility) { () -> (NSImage, CGSize)? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            var size = CGSize.zero
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
                size = CGSize(width: w, height: h)
            }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return (NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), size)
        }.value
    }

    static func resolution(of url: URL) async -> CGSize? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return nil }
        return size
    }

    static func isPlayable(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
    }

    static func thumbnail(for url: URL, height: CGFloat = 76) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 3, height: height)
        guard
            let cg = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
                .image
        else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    static func totalBytes(_ recordings: [Recording]) -> String {
        let sum = recordings.reduce(0) { $0 + $1.bytes }
        return ByteCountFormatter.string(fromByteCount: Int64(sum), countStyle: .file)
    }

    static func moveToTrash(_ recording: Recording) {
        try? FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
        let sidecar = PolishExporter.telemetryURL(for: recording.url)
        try? FileManager.default.trashItem(at: sidecar, resultingItemURL: nil)
        if let polished = recording.polishedURL {
            try? FileManager.default.trashItem(at: polished, resultingItemURL: nil)
        }
    }
}
