import AVFoundation
import CoreImage
import Foundation

/// Applies the zoom plan to a recording and writes a new file.
///
/// Runs after capture, reading the clean video plus its telemetry sidecar.
/// Because nothing was baked into the pixels during recording, the camera
/// path can be recomputed and re-rendered as often as you like.
enum PolishExporter {

    enum Background: String, CaseIterable, Identifiable {
        case none, gradient, solid
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .gradient: return "Gradient"
            case .solid: return "Solid colour"
            }
        }
    }

    struct Options {
        var zoom: ZoomPlanner.Settings = .default
        var highlightCursor = true
        var includeWebcam = true
        var removeSilence = false
        var silenceThresholdDB: Double = -45
        var minSilenceSeconds: Double = 1.2
        var silencePadding: Double = 0.25
        var background: Background = .none
        /// Fraction of the frame left as margin around the inset when a
        /// background is used.
        var padding: Double = 0.07
        /// 0 keeps the source size; otherwise the output height in pixels.
        var exportHeight: Int = 0
        static let `default` = Options()
    }

    enum PolishError: Error, LocalizedError {
        case noTelemetry
        case noVideoTrack
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noTelemetry:
                return "No telemetry sidecar found next to this recording."
            case .noVideoTrack:
                return "That file has no video track."
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            }
        }
    }

    static func telemetryURL(for videoURL: URL) -> URL {
        videoURL.deletingPathExtension().appendingPathExtension("telemetry.json")
    }

    static func outputURL(for videoURL: URL) -> URL {
        let base = videoURL.deletingPathExtension().lastPathComponent
        return videoURL.deletingLastPathComponent()
            .appendingPathComponent("\(base) (polished).mov")
    }

    /// A white ring, built once and reused for every click marker.
    /// Regenerating it per frame would dominate the render cost.
    private static let ringImage: CIImage? = {
        let size = 256
        guard
            let ctx = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setShouldAntialias(true)
        let lineWidth = CGFloat(size) * 0.08
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(lineWidth)
        let inset = lineWidth / 2 + 1
        ctx.strokeEllipse(
            in: CGRect(
                x: inset, y: inset, width: CGFloat(size) - inset * 2,
                height: CGFloat(size) - inset * 2))
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }()

    private static let ringDuration: Double = 0.45

    /// One Metal-backed context for the whole export. Passing nil to
    /// request.finish(with:context:) made AVFoundation fall back to a slow
    /// default, and colour management on screen content is wasted work.
    private static let renderContext = CIContext(options: [
        .workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
        .cacheIntermediates: false, .useSoftwareRenderer: false,
    ])

    /// Soft radial halo used to highlight the pointer.
    private static let haloImage: CIImage? = {
        let size = 256
        guard
            let ctx = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let mid = CGFloat(size) / 2
        let colors =
            [
                CGColor(red: 1, green: 0.95, blue: 0.4, alpha: 0.38),
                CGColor(red: 1, green: 0.95, blue: 0.4, alpha: 0),
            ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors,
            locations: [0, 1])
        {
            ctx.drawRadialGradient(
                gradient, startCenter: CGPoint(x: mid, y: mid), startRadius: 0,
                endCenter: CGPoint(x: mid, y: mid), endRadius: mid, options: [])
        }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }()

    /// Second pass: keep only `kept` ranges of the polished file. Passthrough,
    /// so it is lossless and takes well under a second.
    private static func cutSilences(polished: URL, kept: [CMTimeRange]) async throws {
        guard !kept.isEmpty else { return }
        let asset = AVURLAsset(url: polished)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let comp = AVMutableComposition()
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let ca = audio.map { _ in comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)! }
        var at = CMTime.zero
        for range in kept {
            try cv.insertTimeRange(range, of: video, at: at)
            for (i, t) in audio.enumerated() { try? ca[i].insertTimeRange(range, of: t, at: at) }
            at = CMTimeAdd(at, range.duration)
        }
        let tmp = polished.deletingLastPathComponent()
            .appendingPathComponent(".cut-" + polished.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            throw PolishError.exportFailed("no passthrough preset for silence cut")
        }
        session.outputURL = tmp
        session.outputFileType = .mov
        await session.export()
        guard session.status == .completed else {
            throw PolishError.exportFailed("silence cut: \(session.error?.localizedDescription ?? "unknown")")
        }
        _ = try FileManager.default.replaceItemAt(polished, withItemAt: tmp)
    }

    /// Background with shadow, and the rounded mask, rendered once to pixels.
    private static func staticFrameLayers(extent: CGRect, style: Background, padding: Double) -> (bg: CIImage, mask: CIImage)? {
        let scale = 1 - padding * 2
        let w = extent.width * scale, h = extent.height * scale
        let ox = extent.minX + (extent.width - w) / 2, oy = extent.minY + (extent.height - h) / 2
        let bg: CIImage
        switch style {
        case .gradient:
            let g = CIFilter(name: "CILinearGradient")!
            g.setValue(CIVector(x: extent.minX, y: extent.maxY), forKey: "inputPoint0")
            g.setValue(CIVector(x: extent.maxX, y: extent.minY), forKey: "inputPoint1")
            g.setValue(CIColor(red: 0.16, green: 0.20, blue: 0.42), forKey: "inputColor0")
            g.setValue(CIColor(red: 0.42, green: 0.16, blue: 0.38), forKey: "inputColor1")
            bg = (g.outputImage ?? CIImage.empty()).cropped(to: extent)
        case .solid:
            bg = CIImage(color: CIColor(red: 0.12, green: 0.13, blue: 0.16)).cropped(to: extent)
        case .none:
            return nil
        }
        let radius = min(w, h) * 0.03
        let rr = CIFilter(name: "CIRoundedRectangleGenerator")!
        rr.setValue(CIVector(cgRect: CGRect(x: ox, y: oy, width: w, height: h)), forKey: "inputExtent")
        rr.setValue(radius, forKey: "inputRadius")
        rr.setValue(CIColor.white, forKey: "inputColor")
        guard let mask = rr.outputImage?.cropped(to: extent) else { return nil }
        let shadow = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.55),
        ])
        .transformed(by: CGAffineTransform(translationX: 0, y: -extent.height * 0.012))
        .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": extent.width * 0.012])
        .cropped(to: extent)
        // Flatten to real pixels once; both become cheap texture sources.
        guard let bgCG = renderContext.createCGImage(shadow.composited(over: bg), from: extent),
              let maskCG = renderContext.createCGImage(mask, from: extent) else { return nil }
        return (CIImage(cgImage: bgCG), CIImage(cgImage: maskCG))
    }

    /// Per-frame: scale the frame into the inset and blend through the mask.
    private static func framed(_ image: CIImage, extent: CGRect, padding: Double, bg: CIImage, mask: CIImage) -> CIImage {
        let scale = 1 - padding * 2
        let w = extent.width * scale, h = extent.height * scale
        let ox = extent.minX + (extent.width - w) / 2, oy = extent.minY + (extent.height - h) / 2
        let inset = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: ox - extent.minX * scale, y: oy - extent.minY * scale))
        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(inset, forKey: kCIInputImageKey)
        blend.setValue(bg, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? image
    }

    /// Circular webcam inset, bottom-right, ~18% of the frame width.
    private static func pictureInPicture(_ cam: CIImage, over image: CIImage, extent: CGRect)
        -> CIImage
    {
        let diameter = extent.width * 0.18
        let margin = extent.width * 0.025
        let side = min(cam.extent.width, cam.extent.height)
        // Centre-crop the camera to a square, then scale to the inset size.
        let square = cam.cropped(
            to: CGRect(
                x: cam.extent.midX - side / 2, y: cam.extent.midY - side / 2,
                width: side, height: side))
        let scale = diameter / side
        var inset = square.transformed(
            by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY))
        inset = inset.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let origin = CGPoint(
            x: extent.maxX - diameter - margin, y: extent.minY + margin)
        inset = inset.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))

        // Circular mask with a thin white rim.
        let center = CIVector(x: origin.x + diameter / 2, y: origin.y + diameter / 2)
        guard let maskFilter = CIFilter(name: "CIRadialGradient") else { return image }
        maskFilter.setValue(center, forKey: "inputCenter")
        maskFilter.setValue(diameter / 2 - 1, forKey: "inputRadius0")
        maskFilter.setValue(diameter / 2, forKey: "inputRadius1")
        maskFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        maskFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
        guard let mask = maskFilter.outputImage else { return image }

        guard let rimFilter = CIFilter(name: "CIRadialGradient") else { return image }
        rimFilter.setValue(center, forKey: "inputCenter")
        rimFilter.setValue(diameter / 2 + 2, forKey: "inputRadius0")
        rimFilter.setValue(diameter / 2 + 3.5, forKey: "inputRadius1")
        rimFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0.95), forKey: "inputColor0")
        rimFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
        let rim = (rimFilter.outputImage ?? CIImage.empty()).cropped(
            to: CGRect(
                x: origin.x - 4, y: origin.y - 4, width: diameter + 8, height: diameter + 8))

        // A radial gradient is a filled disc, not a ring: it must go UNDER the
        // camera. Masking the camera over it leaves only the outer edge
        // visible, which is the rim.
        let withRim = rim.composited(over: image)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(inset, forKey: kCIInputImageKey)
        blend.setValue(withRim, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? image
    }

    static func polish(
        videoURL: URL,
        settings: ZoomPlanner.Settings = .default,
        highlightCursor: Bool = true,
        includeWebcam: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        var options = Options()
        options.zoom = settings
        options.highlightCursor = highlightCursor
        options.includeWebcam = includeWebcam
        return try await polish(videoURL: videoURL, options: options, progress: progress)
    }

    /// Maps composition time back to source time once silences are cut.
    private struct Segment { let compStart: Double; let srcStart: Double; let duration: Double }

    static func polish(
        videoURL: URL,
        options: Options,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let settings = options.zoom
        let highlightCursor = options.highlightCursor
        let includeWebcam = options.includeWebcam

        let sidecarURL = telemetryURL(for: videoURL)
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            throw PolishError.noTelemetry
        }
        let sidecar = try TelemetrySidecar.load(from: sidecarURL)

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PolishError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)

        let plan = ZoomPlanner.plan(from: sidecar, duration: seconds, settings: settings)

        // Silence removal happens as a second, lossless pass over the polished
        // output (see cutSilences). AVFoundation refuses a CIFilter video
        // composition on top of an AVMutableComposition (-17913), so the
        // render always reads the original asset and the cut comes after.
        let renderAsset: AVAsset = asset
        func sourceTime(_ t: Double) -> Double { t }

        // Output size.
        var outSize = naturalSize
        if options.exportHeight > 0, naturalSize.height > 0 {
            let f = Double(options.exportHeight) / naturalSize.height
            outSize = CGSize(width: (naturalSize.width * f / 2).rounded() * 2, height: Double(options.exportHeight))
        }
        let outScale = outSize.height / max(1, naturalSize.height)

        // Webcam sidecar, composited as picture-in-picture AFTER the zoom so
        // it stays pinned to the corner rather than being zoomed with the
        // content. Nil when there is no webcam file or it was left out.
        let webcamURL = WebcamRecorder.sidecarURL(for: videoURL)
        let webcam: WebcamFrameSource? =
            includeWebcam && FileManager.default.fileExists(atPath: webcamURL.path)
            ? await WebcamFrameSource(url: webcamURL) : nil

        // The sidecar records display pixels; the video may have been written
        // at a different size. Map between them rather than assuming parity.
        let sx = naturalSize.width / max(1, plan.frameSize.width)
        let sy = naturalSize.height / max(1, plan.frameSize.height)

        // Background, shadow and rounded mask never change between frames.
        // Build them once and render them to real pixels so the per-frame
        // work is one blend, not a gradient + generator + Gaussian blur.
        let frameExtent = CGRect(origin: .zero, size: naturalSize)
        let staticFrame: (bg: CIImage, mask: CIImage)? = options.background == .none ? nil
            : Self.staticFrameLayers(extent: frameExtent, style: options.background, padding: options.padding)

        let composition = AVMutableVideoComposition(asset: renderAsset) { request in
            let time = sourceTime(CMTimeGetSeconds(request.compositionTime))
            var image = request.sourceImage
            let extent = image.extent

            // Cursor halo, drawn under the click rings and before the crop so
            // it scales with the content rather than floating over it.
            if highlightCursor, let halo = haloImage,
                let sample = plan.sample(at: time)
            {
                let radius = extent.width * 0.045
                let cx = extent.minX + sample.x * sx
                let cy = extent.minY + (plan.frameSize.height - sample.y) * sy
                let factor = (radius * 2) / halo.extent.width
                var glow = halo.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                glow = glow.transformed(
                    by: CGAffineTransform(
                        translationX: cx - glow.extent.width / 2,
                        y: cy - glow.extent.height / 2))
                image = glow.composited(over: image)
            }

            // Click rings are composited in SOURCE space so they zoom with the
            // content they are marking, rather than floating over it.
            if let ring = ringImage {
                for click in plan.clicks
                where time >= click.t && time < click.t + ringDuration {
                    let p = (time - click.t) / ringDuration
                    let radius = extent.width * 0.025 * (0.45 + p * 1.15)
                    let alpha = max(0, 1 - p)

                    let cx = extent.minX + click.point.x * sx
                    // Telemetry is top-left origin; CoreImage is bottom-left.
                    let cy = extent.minY + (plan.frameSize.height - click.point.y) * sy

                    let scale = (radius * 2) / ring.extent.width
                    var marker = ring.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    marker = marker.transformed(
                        by: CGAffineTransform(
                            translationX: cx - marker.extent.width / 2,
                            y: cy - marker.extent.height / 2))
                    if let fade = CIFilter(name: "CIColorMatrix") {
                        fade.setValue(marker, forKey: kCIInputImageKey)
                        fade.setValue(CIVector(x: 0, y: 0, z: 0, w: alpha), forKey: "inputAVector")
                        marker = fade.outputImage ?? marker
                    }
                    image = marker.composited(over: image)
                }
            }

            // Crop to the planned view, then scale it back to full size.
            let state = plan.state(at: time)
            if state.scale > 1.001 {
                let w = extent.width / state.scale
                let h = extent.height / state.scale
                let cx = extent.minX + state.center.x * sx
                let cy = extent.minY + (plan.frameSize.height - state.center.y) * sy

                var ox = cx - w / 2
                var oy = cy - h / 2
                ox = min(max(ox, extent.minX), extent.maxX - w)
                oy = min(max(oy, extent.minY), extent.maxY - h)

                image =
                    image
                    .cropped(to: CGRect(x: ox, y: oy, width: w, height: h))
                    .transformed(by: CGAffineTransform(translationX: -ox, y: -oy))
                    .transformed(by: CGAffineTransform(scaleX: state.scale, y: state.scale))
                    .transformed(
                        by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            }

            if let staticFrame {
                image = Self.framed(image, extent: extent, padding: options.padding, bg: staticFrame.bg, mask: staticFrame.mask)
            }

            if let webcam, let cam = webcam.image(at: time) {
                image = Self.pictureInPicture(cam, over: image, extent: extent)
            }

            var out = image.cropped(to: extent)
            if abs(outScale - 1) > 0.001 {
                out = out.transformed(by: CGAffineTransform(scaleX: outScale, y: outScale))
                    .cropped(to: CGRect(origin: .zero, size: outSize))
            }
            request.finish(with: out, context: Self.renderContext)
        }
        composition.renderSize = outSize
        let fps = (try? await track.load(.nominalFrameRate)) ?? 0
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps > 1 ? fps.rounded() : 30))

        let output = outputURL(for: videoURL)
        try? FileManager.default.removeItem(at: output)

        guard
            let session = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
        else {
            throw PolishError.exportFailed("no suitable export preset")
        }
        session.outputURL = output
        session.outputFileType = .mov
        session.videoComposition = composition

        let ticker = Task {
            while !Task.isCancelled {
                progress?(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { ticker.cancel() }

        await session.export()

        switch session.status {
        case .completed:
            if options.removeSilence {
                let kept = try await SilenceDetector.keptRanges(
                    asset: asset, thresholdDB: options.silenceThresholdDB,
                    minSilence: options.minSilenceSeconds, padding: options.silencePadding)
                try await cutSilences(polished: output, kept: kept)
            }
            progress?(1.0)
            return output
        case .cancelled:
            throw PolishError.exportFailed("cancelled")
        default:
            throw PolishError.exportFailed(
                session.error?.localizedDescription ?? "unknown error")
        }
    }
}
