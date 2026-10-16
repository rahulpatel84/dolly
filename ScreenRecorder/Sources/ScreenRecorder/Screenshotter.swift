import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Still capture, sharing the same target model as recording.
///
/// Uses SCScreenshotManager rather than the deprecated CGWindowListCreateImage,
/// so it honours the same Screen Recording permission already granted and
/// needs no extra approval.
enum Screenshotter {

    enum ShotError: Error, LocalizedError {
        case noDisplay
        case captureFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display available."
            case .captureFailed: return "The screenshot could not be captured."
            case .writeFailed: return "The screenshot could not be written."
            }
        }
    }

    /// `url` is where the file WILL be; `saved` completes once it is on disk
    /// and on the clipboard. The editor opens before either happens, because
    /// PNG-encoding a 5K screenshot takes longer than a person is willing to
    /// wait for a window.
    struct Captured {
        let url: URL
        let image: NSImage
        let saved: Task<Bool, Never>
    }

    static func capture(target: CaptureTarget) async throws -> URL {
        let shot = try await captureImage(target: target)
        _ = await shot.saved.value
        return shot.url
    }

    static func captureImage(target: CaptureTarget) async throws -> Captured {
        // Read every setting on the main actor up front. This function runs
        // on a background executor after its first await, so touching
        // AppSettings from here later (as an earlier version did through
        // MainActor.assumeIsolated) trips Swift's isolation check and aborts.
        let prefs = await MainActor.run { () -> (jpeg: Bool, folder: URL, background: String, downscale: Bool) in
            let s = AppSettings.shared
            return (s.screenshotFormat == "jpeg", s.screenshotFolder, s.windowBackground, s.downscaleRetina)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == ownBundleID }

        let filter: SCContentFilter
        let config = SCStreamConfiguration()

        switch target {
        case .display(let display):
            filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: [])
            let (w, h) = display.pixelSize
            config.width = w
            config.height = h

        case .region(let display, let rect):
            filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: [])
            let bounds = CGDisplayBounds(display.displayID)
            let (dw, _) = display.pixelSize
            let scale = bounds.width > 0 ? Double(dw) / bounds.width : 1
            config.sourceRect = rect
            config.width = max(1, Int(rect.width * scale))
            config.height = max(1, Int(rect.height * scale))

        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale =
                NSScreen.screens.first { $0.frame.intersects(window.frame) }?
                .backingScaleFactor ?? 2
            let style = prefs.background
            // Leave room for the system shadow unless the user asked to trim it.
            let pad: CGFloat = style == "trim" ? 0 : 40
            config.width = max(1, Int((window.frame.width + pad * 2) * scale))
            config.height = max(1, Int((window.frame.height + pad * 2) * scale))
            config.shouldBeOpaque = false
            if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = style == "trim" }
        }

        config.showsCursor = false
        config.captureResolution = .best

        guard
            var image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        else { throw ShotError.captureFailed }

        if case .window = target {
            image = applyWindowBackground(image, style: prefs.background)
        }
        if prefs.downscale, let scaled = downscale(image) { image = scaled }

        let url = plannedURL(jpeg: prefs.jpeg, folder: prefs.folder)
        let cg = image
        let pasteboardCount = NSPasteboard.general.changeCount
        let saved = Task.detached(priority: .userInitiated) { () -> Bool in
            let ok = (try? write(cg, to: url, jpeg: prefs.jpeg)) != nil
            // Clipboard after the file. If the user copied something in the
            // meantime (their annotated version, say), leave it alone.
            let (tiff, png) = Clipboard.encode(cg)
            await MainActor.run {
                if NSPasteboard.general.changeCount == pasteboardCount {
                    Clipboard.set(tiff: tiff, png: png, source: cg)
                }
            }
            return ok
        }
        return Captured(url: url, image: NSImage(cgImage: image, size: .zero), saved: saved)
    }

    private static func plannedURL(jpeg: Bool, folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Screenshot \(formatter.string(from: Date())).\(jpeg ? "jpg" : "png")")
    }

    /// Window screenshots: what sits behind the window's transparent margins.
    private static func applyWindowBackground(_ image: CGImage, style: String) -> CGImage {
        guard style == "solid" || style == "gradient" else { return image }  // transparent/shadow/trim: as captured
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        if style == "gradient" {
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
                CGColor(red: 0.25, green: 0.35, blue: 0.75, alpha: 1), CGColor(red: 0.55, green: 0.25, blue: 0.60, alpha: 1)] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        } else {
            ctx.setFillColor(CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    private static func downscale(_ image: CGImage) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard scale > 1 else { return nil }
        return FastImage.downscale(image, maxWidth: Int(CGFloat(image.width) / scale))
    }

    private static func write(_ image: CGImage, to url: URL, jpeg: Bool) throws -> URL {
        if !jpeg {
            guard FastImage.writePNG(image, to: url) else { throw ShotError.writeFailed }
            return url
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ShotError.writeFailed }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ShotError.writeFailed }
        return url
    }
}
