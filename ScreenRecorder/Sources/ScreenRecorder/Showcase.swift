import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// `--showcase <dir>`: produce real window screenshots of the app for the
/// website and documentation. A synthetic demo library is generated first so
/// no personal recording is ever photographed.
@MainActor
enum Showcase {
    static var outputDir: URL?

    static func runIfRequested(delegate: AppDelegate) {
        guard let out = outputDir else { return }
        Task { @MainActor in
            do { try await run(delegate: delegate, out: out) } catch { log("FAILED: \(error)") }
            exit(0)
        }
    }

    /// Logged to stderr and to <out>/run.log (the app is launched via `open`,
    /// which detaches stderr).
    private static func log(_ s: String) {
        let line = "showcase: \(s)\n"
        FileHandle.standardError.write(Data(line.utf8))
        if let out = outputDir {
            let url = out.appendingPathComponent("run.log")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
    private static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    private static func run(delegate: AppDelegate, out: URL) async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let library = CaptureEngine.recordingsDirectory()
        log("building demo library in \(library.path)")
        try await DemoLibrary.build(in: library)
        log("library ready · preflight permission=\(Permissions.hasScreenRecording) bundle=\(Bundle.main.bundlePath)")
        // Warm up ScreenCaptureKit; retry while TCC settles after launch.
        for attempt in 1...5 {
            do { _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true); break }
            catch {
                log("shareable content attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt == 1 { Permissions.requestScreenRecording() }
                await wait(2)
            }
        }

        // Dashboard — recordings grid with inspector, screenshots, polished.
        let dash = delegate.dashboard
        dash.show()
        dash.model.reload()
        await wait(2.5)   // thumbnails + durations
        if let w = dash.window {
            w.setContentSize(NSSize(width: 1240, height: 720)); w.center()
            dash.model.section = .recordings
            if let first = dash.model.recordings.first { dash.model.selection = [first.url] }
            await wait(1.0); try await capture(window: w, to: out, "dashboard")
            dash.model.section = .screenshots
            if let shot = dash.model.screenshots.first { dash.model.selection = [shot.url] }
            await wait(0.8); try await capture(window: w, to: out, "dashboard-screenshots")
            dash.model.section = .polished
            dash.model.selection = []
            await wait(0.8); try await capture(window: w, to: out, "dashboard-polished")
            dash.model.section = .recordings
            // Player and trimmer windows.
            if let rec = dash.model.recordings.first {
                dash.model.playing = rec
                await wait(2.0)
                if let p = dash.playerWindow { try await capture(window: p, to: out, "player") }
                dash.model.playing = nil
                await wait(0.3)
                dash.model.trimming = rec
                await wait(2.0)
                if let t = dash.trimWindow { try await capture(window: t, to: out, "trim") }
                dash.model.trimming = nil
            }
        }

        // Settings — every tab.
        delegate.settingsWindow.show()
        await wait(0.8)
        if let w = delegate.settingsWindow.window {
            for tab in ["general", "recording", "polish", "screenshots", "hotkeys"] {
                AppSettings.shared.settingsTab = tab
                await wait(0.6)
                try await capture(window: w, to: out, "settings-\(tab)")
            }
            w.orderOut(nil)
        }

        // Screenshot editor — annotated, then styled.
        let shotURL = library.appendingPathComponent("Pricing page.png")
        if let image = NSImage(contentsOf: shotURL) {
            let (model, w) = ScreenshotEditorWindows.shared.open(image: image, sourceURL: shotURL)
            w.setContentSize(NSSize(width: 1280, height: 860)); w.center()
            let W = model.pixelSize.width, H = model.pixelSize.height
            let k = max(1, W / 1280)
            model.annotations = [
                Annotation(kind: .rect, start: CGPoint(x: W * 0.355, y: H * 0.42), end: CGPoint(x: W * 0.645, y: H * 0.93), color: Color(red: 0.95, green: 0.23, blue: 0.24), width: 5 * k),
                Annotation(kind: .arrow, start: CGPoint(x: W * 0.72, y: H * 0.30), end: CGPoint(x: W * 0.60, y: H * 0.47), color: Color(red: 0.95, green: 0.23, blue: 0.24), width: 6 * k),
                Annotation(kind: .text, start: CGPoint(x: W * 0.725, y: H * 0.255), end: .zero, color: .white, width: 7 * k, text: "Default to annual"),
                Annotation(kind: .number, start: CGPoint(x: W * 0.09, y: H * 0.42), end: .zero, color: Color(red: 0.0, green: 0.48, blue: 1.0), width: 7 * k, number: 1),
                Annotation(kind: .number, start: CGPoint(x: W * 0.355, y: H * 0.42), end: .zero, color: Color(red: 0.0, green: 0.48, blue: 1.0), width: 7 * k, number: 2),
                Annotation(kind: .highlight, start: CGPoint(x: W * 0.12, y: H * 0.165), end: CGPoint(x: W * 0.55, y: H * 0.215), color: .yellow, width: 4 * k),
            ]
            model.tool = .arrow
            await wait(1.2); try await capture(window: w, to: out, "editor")
            model.style.background = .midnight; model.style.macWindow = true; model.style.title = "Pricing — Acme"
            model.zoom = 0.62 / max(1, model.screenScale) * 2   // fit the padded canvas
            await wait(1.0); try await capture(window: w, to: out, "editor-styled")
            // Exports of the styled result for the site.
            if let rendered = model.render(), let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                _ = FastImage.writePNG(cg, to: out.appendingPathComponent("styled-export.png"))
            }
            w.orderOut(nil)
        }

        // Other apps' windows when present (Finder with the DMG, System Settings).
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
            let apps = Set(content.windows.filter { $0.frame.width > 300 }.compactMap { ($0.owningApplication?.bundleIdentifier ?? "?") + ":" + ($0.title ?? "") })
            log("visible windows: \(apps.sorted().joined(separator: " | "))")
        }
        try? await capture(app: "com.apple.finder", titlePrefix: "Dolly", to: out, "install-dmg")
        try? await capture(app: "com.apple.systempreferences", titlePrefix: nil, to: out, "install-permission")
        log("done → \(out.path)")
    }

    // MARK: capture

    private static func capture(window w: NSWindow, to dir: URL, _ name: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scw = content.windows.first(where: { $0.windowID == CGWindowID(w.windowNumber) }) else {
            log("window not found for \(name)"); return
        }
        try await capture(scWindow: scw, scale: w.backingScaleFactor, to: dir.appendingPathComponent("\(name).png"))
        log("captured \(name)")
    }

    private static func capture(app bundleID: String, titlePrefix: String?, to dir: URL, _ name: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scw = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width > 300 &&
            (titlePrefix == nil || ($0.title ?? "").hasPrefix(titlePrefix!))
        }) else { log("no \(bundleID) window; skipping \(name)"); return }
        let scale = NSScreen.screens.first { $0.frame.intersects(scw.frame) }?.backingScaleFactor ?? 2
        try await capture(scWindow: scw, scale: scale, to: dir.appendingPathComponent("\(name).png"))
        log("captured \(name)")
    }

    private static func capture(scWindow: SCWindow, scale: CGFloat, to url: URL) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = Int(scWindow.frame.width * scale)
        config.height = Int(scWindow.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.shouldBeOpaque = false
        if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        _ = FastImage.writePNG(image, to: url)
    }
}

// MARK: - Demo library

/// Synthetic recordings of a fictional analytics app ("Acme"), with cursor
/// telemetry that matches the drawn cursor so Auto-Zoom produces a real result.
enum DemoLibrary {
    struct Scene {
        let name: String
        let title: String
        let accent: CGColor
        let seconds: Double
        let waypoints: [(x: Double, y: Double, dwell: Double, click: Bool)]
        let ageHours: Double
    }

    static let size = CGSize(width: 1920, height: 1080)

    static func build(in dir: URL) async throws {
        let fm = FileManager.default
        let marker = dir.appendingPathComponent(".demo-ready")
        if fm.fileExists(atPath: marker.path) { return }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let scenes = [
            Scene(name: "Onboarding walkthrough", title: "Acme Analytics", accent: CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1), seconds: 22,
                  waypoints: [(0.14, 0.26, 1.0, false), (0.14, 0.26, 0.6, true), (0.47, 0.37, 1.2, true), (0.78, 0.37, 1.0, false), (0.62, 0.70, 1.4, true), (0.30, 0.78, 1.2, true), (0.86, 0.14, 1.0, true), (0.52, 0.52, 1.5, false)], ageHours: 3),
            Scene(name: "Checkout bug repro", title: "Acme Orders", accent: CGColor(red: 0.05, green: 0.62, blue: 0.55, alpha: 1), seconds: 12,
                  waypoints: [(0.30, 0.40, 0.8, false), (0.56, 0.62, 1.0, true), (0.56, 0.62, 0.5, true), (0.72, 0.76, 1.2, true), (0.40, 0.30, 1.0, false)], ageHours: 27),
            Scene(name: "Weekly product demo", title: "Acme Roadmap", accent: CGColor(red: 0.93, green: 0.45, blue: 0.14, alpha: 1), seconds: 31,
                  waypoints: [(0.20, 0.30, 1.2, false), (0.45, 0.42, 1.0, true), (0.80, 0.42, 1.2, true), (0.80, 0.80, 1.0, false), (0.35, 0.70, 1.4, true), (0.15, 0.18, 1.0, true), (0.60, 0.26, 1.2, true), (0.50, 0.55, 1.5, false), (0.25, 0.85, 1.0, true)], ageHours: 76),
        ]
        for scene in scenes {
            let url = dir.appendingPathComponent("\(scene.name).mov")
            try await writeMovie(scene: scene, to: url)
            try writeTelemetry(scene: scene, to: PolishExporter.telemetryURL(for: url))
            age(url, hours: scene.ageHours); age(PolishExporter.telemetryURL(for: url), hours: scene.ageHours)
        }
        // Screenshots.
        let shots: [(String, Double, (CGContext, CGSize) -> Void)] = [
            ("Pricing page", 5, { ctx, s in MockUI.pricing(ctx, size: s) }),
            ("Team settings", 30, { ctx, s in MockUI.settingsDialog(ctx, size: s) }),
            ("Acme Analytics", 50, { ctx, s in MockUI.app(ctx, size: s, title: "Acme Analytics", accent: scenes[0].accent, t: 8, cursor: nil, clickAge: nil) }),
        ]
        for (name, hours, draw) in shots {
            let s = CGSize(width: 2560, height: 1600)
            let ctx = MockUI.context(s); draw(ctx, s)
            if let cg = ctx.makeImage() {
                let url = dir.appendingPathComponent("\(name).png")
                _ = FastImage.writePNG(cg, to: url); age(url, hours: hours)
            }
        }
        // One polished example so the Polished section has content.
        let first = dir.appendingPathComponent("\(scenes[1].name).mov")
        var options = PolishExporter.Options()
        options.background = .gradient
        _ = try? await PolishExporter.polish(videoURL: first, options: options)
        age(PolishExporter.outputURL(for: first), hours: scenes[1].ageHours - 1)
        fm.createFile(atPath: marker.path, contents: nil)
    }

    private static func age(_ url: URL, hours: Double) {
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -hours * 3600)], ofItemAtPath: url.path)
    }

    /// Cursor position (0…1) and seconds since the last click at time t.
    static func cursor(_ scene: Scene, at t: Double) -> (CGPoint, Double?) {
        var time = 0.0
        var prev = scene.waypoints[0]
        var lastClick: Double? = nil
        let travel = 0.9
        for wp in scene.waypoints {
            if time + travel > t {
                let f = max(0, min(1, (t - time) / travel))
                let e = f * f * (3 - 2 * f)
                return (CGPoint(x: prev.x + (wp.x - prev.x) * e, y: prev.y + (wp.y - prev.y) * e), lastClick.map { t - $0 })
            }
            time += travel
            if wp.click { lastClick = time + 0.2 }
            if time + wp.dwell > t { return (CGPoint(x: wp.x, y: wp.y), lastClick.map { t - $0 }) }
            time += wp.dwell
            prev = wp
        }
        return (CGPoint(x: prev.x, y: prev.y), lastClick.map { t - $0 })
    }

    static func writeTelemetry(scene: Scene, to url: URL) throws {
        var samples: [TelemetryRecorder.Sample] = []
        var clicked = Set<Int>()
        let hz = 60
        for i in 0..<Int(scene.seconds * Double(hz)) {
            let t = Double(i) / Double(hz)
            let (p, age) = cursor(scene, at: t)
            var click = false
            if let age, age >= 0, age < 1.0 / Double(hz) + 0.001 {
                let key = Int((t - age) * 10)
                if !clicked.contains(key) { clicked.insert(key); click = true }
            }
            samples.append(.init(t: t, x: p.x * size.width, y: p.y * size.height, click: click))
        }
        let sidecar = TelemetryRecorder.Sidecar(version: 1, recordingStartedAt: Date(), sampleRateHz: hz,
                                                displayPixelWidth: Int(size.width), displayPixelHeight: Int(size.height), samples: samples)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(sidecar).write(to: url)
    }

    static func writeMovie(scene: Scene, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)])
        // Real recordings always carry system audio; give the demo a silent track.
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        audio.expectsMediaDataInRealTime = false
        writer.add(input); writer.add(audio); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let fps = 30
        let frames = Int(scene.seconds * Double(fps))
        let silence = makeSilence(seconds: scene.seconds)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached(priority: .userInitiated) {
                func note(_ s: String) {
                    let line = "demo \(scene.name): \(s) (writer \(writer.status.rawValue) \(writer.error.map { "\($0)" } ?? ""))\n"
                    FileHandle.standardError.write(Data(line.utf8))
                    let log = url.deletingLastPathComponent().appendingPathComponent("build.log")
                    if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? line.write(to: log, atomically: true, encoding: .utf8) }
                }
                /// Waits up to 5 s for an input; false means the writer is stuck or failed.
                func ready(_ i: AVAssetWriterInput) -> Bool {
                    var waited = 0
                    while !i.isReadyForMoreMediaData { usleep(2000); waited += 1; if waited > 2500 || writer.status != .writing { return false } }
                    return true
                }
                var nextAudio = 0
                for i in 0..<frames {
                    // Keep audio a second ahead of video; the writer interleaves.
                    while nextAudio < silence.count, nextAudio <= i / fps + 1 {
                        guard ready(audio) else { note("audio input not ready at second \(nextAudio)"); break }
                        if !audio.append(silence[nextAudio]) { note("audio append failed at second \(nextAudio)"); break }
                        nextAudio += 1
                    }
                    guard ready(input) else { note("video input not ready at frame \(i)"); break }
                    guard let pool = adaptor.pixelBufferPool else { note("no pixel buffer pool at frame \(i)"); break }
                    var pb: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                    guard let buffer = pb else { note("no pixel buffer at frame \(i)"); break }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                           bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                        let t = Double(i) / Double(fps)
                        let (p, age) = cursor(scene, at: t)
                        MockUI.app(ctx, size: size, title: scene.title, accent: scene.accent, t: t,
                                   cursor: CGPoint(x: p.x * size.width, y: p.y * size.height), clickAge: age)
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
                }
                input.markAsFinished()
                audio.markAsFinished()
                writer.finishWriting { note("finished"); cont.resume() }
            }
        }
    }
}

extension DemoLibrary {
    /// One-second PCM silence buffers covering `seconds`.
    static func makeSilence(seconds: Double) -> [CMSampleBuffer] {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1,
            mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var fmt: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
        guard let fmt else { return [] }
        var out: [CMSampleBuffer] = []
        let frames = 48_000
        for second in 0..<Int(seconds.rounded(.up)) {
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 2, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frames * 2, flags: 0, blockBufferOut: &block)
            guard let block else { continue }
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: frames * 2)
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: fmt, sampleCount: frames,
                presentationTimeStamp: CMTime(value: CMTimeValue(second * frames), timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &sample)
            if let sample { out.append(sample) }
        }
        return out
    }
}

// MARK: - Mock application artwork

/// Draws a fictional SaaS product so demo media looks like real work without
/// containing anyone's real screen. All coordinates top-left origin.
enum MockUI {
    static func context(_ size: CGSize) -> CGContext {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx
    }

    private static func flipped(_ ctx: CGContext, _ size: CGSize, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        body()
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    private static func fill(_ ctx: CGContext, _ r: CGRect, _ c: CGColor, radius: CGFloat = 0) {
        ctx.setFillColor(c)
        if radius > 0 { ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath() }
        else { ctx.fill(r) }
    }

    private static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = NSColor(white: 0.12, alpha: 1), width: CGFloat? = nil) {
        let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        if let width { str.draw(in: CGRect(x: p.x, y: p.y, width: width, height: size * 1.5)) } else { str.draw(at: p) }
    }

    private static let gray  = CGColor(red: 0.96, green: 0.965, blue: 0.975, alpha: 1)
    private static let line  = CGColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1)
    private static let white = CGColor(gray: 1, alpha: 1)
    private static let ink   = NSColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    private static let muted = NSColor(red: 0.45, green: 0.47, blue: 0.53, alpha: 1)

    static func app(_ ctx: CGContext, size: CGSize, title: String, accent: CGColor, t: Double, cursor: CGPoint?, clickAge: Double?) {
        flipped(ctx, size) {
            let u = size.width / 1920   // unit scale
            fill(ctx, CGRect(origin: .zero, size: size), gray)
            // Sidebar
            fill(ctx, CGRect(x: 0, y: 0, width: 232 * u, height: size.height), white)
            fill(ctx, CGRect(x: 232 * u, y: 0, width: 1, height: size.height), line)
            fill(ctx, CGRect(x: 24 * u, y: 24 * u, width: 28 * u, height: 28 * u), accent, radius: 7 * u)
            text(title, at: CGPoint(x: 62 * u, y: 26 * u), size: 17 * u, weight: .semibold, color: ink)
            let items = ["Overview", "Customers", "Revenue", "Funnels", "Reports", "Alerts", "Settings"]
            for (i, item) in items.enumerated() {
                let y = (92 + CGFloat(i) * 44) * u
                if i == 2 { fill(ctx, CGRect(x: 12 * u, y: y - 8 * u, width: 208 * u, height: 36 * u), CGColor(red: 0.93, green: 0.94, blue: 0.98, alpha: 1), radius: 8 * u) }
                fill(ctx, CGRect(x: 26 * u, y: y + 2 * u, width: 16 * u, height: 16 * u), i == 2 ? accent : CGColor(gray: 0.75, alpha: 1), radius: 4 * u)
                text(item, at: CGPoint(x: 54 * u, y: y - 1 * u), size: 14 * u, weight: i == 2 ? .semibold : .regular, color: i == 2 ? ink : muted)
            }
            // Top bar
            fill(ctx, CGRect(x: 233 * u, y: 0, width: size.width - 233 * u, height: 60 * u), white)
            fill(ctx, CGRect(x: 233 * u, y: 60 * u, width: size.width, height: 1), line)
            text("Revenue", at: CGPoint(x: 268 * u, y: 18 * u), size: 18 * u, weight: .semibold, color: ink)
            fill(ctx, CGRect(x: size.width - 300 * u, y: 14 * u, width: 180 * u, height: 32 * u), gray, radius: 8 * u)
            text("Last 30 days  ▾", at: CGPoint(x: size.width - 286 * u, y: 21 * u), size: 13 * u, color: muted)
            fill(ctx, CGRect(x: size.width - 100 * u, y: 12 * u, width: 36 * u, height: 36 * u), accent, radius: 18 * u)
            text("RP", at: CGPoint(x: size.width - 91 * u, y: 21 * u), size: 12 * u, weight: .bold, color: .white)
            // KPI cards
            let kpis = [("MRR", "$128,450", "+8.2%"), ("Active customers", "3,214", "+124"), ("Churn", "1.9%", "−0.3 pt"), ("Avg. order", "$86.20", "+2.1%")]
            let cardW = (size.width - 233 * u - 36 * u * 2 - 24 * u * 3) / 4
            for (i, k) in kpis.enumerated() {
                let x = 233 * u + 36 * u + CGFloat(i) * (cardW + 24 * u)
                let r = CGRect(x: x, y: 96 * u, width: cardW, height: 120 * u)
                fill(ctx, r, white, radius: 12 * u)
                text(k.0, at: CGPoint(x: x + 20 * u, y: 112 * u), size: 13 * u, color: muted)
                text(k.1, at: CGPoint(x: x + 20 * u, y: 138 * u), size: 28 * u, weight: .semibold, color: ink)
                text(k.2, at: CGPoint(x: x + 20 * u, y: 182 * u), size: 12 * u, weight: .medium, color: NSColor(red: 0.12, green: 0.6, blue: 0.35, alpha: 1))
            }
            // Chart card
            let chart = CGRect(x: 269 * u, y: 244 * u, width: size.width - 269 * u - 36 * u - 400 * u - 24 * u, height: size.height - 244 * u - 40 * u)
            fill(ctx, chart, white, radius: 12 * u)
            text("Monthly recurring revenue", at: CGPoint(x: chart.minX + 20 * u, y: chart.minY + 18 * u), size: 15 * u, weight: .semibold, color: ink)
            let bars = 12
            let barArea = chart.insetBy(dx: 28 * u, dy: 64 * u).offsetBy(dx: 0, dy: 20 * u)
            let bw = barArea.width / CGFloat(bars) * 0.58
            for i in 0..<bars {
                let base = 0.35 + 0.5 * (Double(i) / Double(bars - 1))
                let anim = min(1, t / 1.2 + 0.15)
                let h = barArea.height * CGFloat(base * anim) * CGFloat(0.9 + 0.1 * sin(Double(i) * 1.7))
                let x = barArea.minX + (barArea.width / CGFloat(bars)) * (CGFloat(i) + 0.21)
                fill(ctx, CGRect(x: x, y: barArea.maxY - h, width: bw, height: h), i == bars - 1 ? accent : CGColor(red: 0.80, green: 0.82, blue: 0.95, alpha: 1), radius: 4 * u)
            }
            for i in 0...4 { fill(ctx, CGRect(x: barArea.minX, y: barArea.minY + barArea.height * CGFloat(i) / 4, width: barArea.width, height: 1), line) }
            // Table card
            let table = CGRect(x: chart.maxX + 24 * u, y: 244 * u, width: 400 * u, height: chart.height)
            fill(ctx, table, white, radius: 12 * u)
            text("Top customers", at: CGPoint(x: table.minX + 20 * u, y: table.minY + 18 * u), size: 15 * u, weight: .semibold, color: ink)
            let rows = [("Northwind Traders", "$12,400"), ("Globex", "$9,870"), ("Initech", "$8,120"), ("Umbrella Health", "$7,455"), ("Vandelay Imports", "$6,980"), ("Hooli", "$6,210"), ("Stark Industries", "$5,900"), ("Wonka Foods", "$5,110")]
            for (i, row) in rows.enumerated() {
                let y = table.minY + (62 + CGFloat(i) * 52) * u
                fill(ctx, CGRect(x: table.minX + 20 * u, y: y + 44 * u, width: table.width - 40 * u, height: 1), line)
                fill(ctx, CGRect(x: table.minX + 20 * u, y: y + 6 * u, width: 26 * u, height: 26 * u), CGColor(red: 0.85 - Double(i) * 0.04, green: 0.88, blue: 0.95, alpha: 1), radius: 13 * u)
                text(row.0, at: CGPoint(x: table.minX + 58 * u, y: y + 10 * u), size: 13.5 * u, color: ink)
                text(row.1, at: CGPoint(x: table.maxX - 100 * u, y: y + 10 * u), size: 13.5 * u, weight: .medium, color: ink)
            }
            // Cursor + click ring
            if let c = cursor {
                if let age = clickAge, age >= 0, age < 0.45 {
                    let r = CGFloat(10 + age * 70) * u
                    ctx.setStrokeColor(CGColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1 - age / 0.45)); ctx.setLineWidth(3 * u)
                    ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                }
                let p = CGMutablePath()
                p.move(to: c); p.addLine(to: CGPoint(x: c.x, y: c.y + 24 * u)); p.addLine(to: CGPoint(x: c.x + 6.5 * u, y: c.y + 18.5 * u))
                p.addLine(to: CGPoint(x: c.x + 11 * u, y: c.y + 27 * u)); p.addLine(to: CGPoint(x: c.x + 14.5 * u, y: c.y + 25.5 * u))
                p.addLine(to: CGPoint(x: c.x + 10 * u, y: c.y + 17 * u)); p.addLine(to: CGPoint(x: c.x + 18 * u, y: c.y + 17 * u)); p.closeSubpath()
                ctx.addPath(p); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.setStrokeColor(white); ctx.setLineWidth(1.6 * u)
                ctx.drawPath(using: .fillStroke)
            }
        }
    }

    static func pricing(_ ctx: CGContext, size: CGSize) {
        flipped(ctx, size) {
            let u = size.width / 1920
            fill(ctx, CGRect(origin: .zero, size: size), white)
            fill(ctx, CGRect(x: 0, y: 0, width: size.width, height: 72 * u), white)
            fill(ctx, CGRect(x: 0, y: 72 * u, width: size.width, height: 1), line)
            fill(ctx, CGRect(x: 160 * u, y: 22 * u, width: 28 * u, height: 28 * u), CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1), radius: 7 * u)
            text("Acme", at: CGPoint(x: 198 * u, y: 24 * u), size: 18 * u, weight: .semibold, color: ink)
            for (i, item) in ["Product", "Customers", "Pricing", "Docs", "Blog"].enumerated() {
                text(item, at: CGPoint(x: (820 + CGFloat(i) * 110) * u, y: 26 * u), size: 15 * u, weight: i == 2 ? .semibold : .regular, color: i == 2 ? ink : muted)
            }
            fill(ctx, CGRect(x: size.width - 300 * u, y: 18 * u, width: 140 * u, height: 36 * u), CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1), radius: 8 * u)
            text("Start free trial", at: CGPoint(x: size.width - 282 * u, y: 27 * u), size: 14 * u, weight: .semibold, color: .white)
            text("Simple pricing for every team", at: CGPoint(x: 160 * u, y: 150 * u), size: 52 * u, weight: .bold, color: ink)
            text("Start free. Upgrade when the whole company wants in. Switch to annual billing and save 20%.", at: CGPoint(x: 160 * u, y: 228 * u), size: 20 * u, color: muted)
            // Billing toggle
            fill(ctx, CGRect(x: 160 * u, y: 290 * u, width: 300 * u, height: 44 * u), gray, radius: 22 * u)
            fill(ctx, CGRect(x: 164 * u, y: 294 * u, width: 146 * u, height: 36 * u), white, radius: 18 * u)
            text("Monthly", at: CGPoint(x: 206 * u, y: 302 * u), size: 15 * u, weight: .semibold, color: ink)
            text("Annual  −20%", at: CGPoint(x: 330 * u, y: 302 * u), size: 15 * u, color: muted)
            let plans = [("Starter", "$0", "For individuals getting started", ["1 workspace", "Up to 3 dashboards", "Community support"], false),
                         ("Team", "$24", "Per seat, billed monthly", ["Unlimited dashboards", "Funnels & cohorts", "Slack alerts", "Priority support"], true),
                         ("Enterprise", "Custom", "Security, scale and control", ["SSO / SAML", "Audit log", "Dedicated success manager", "99.9% SLA"], false)]
            let cardW = (size.width - 320 * u - 48 * u) / 3
            for (i, plan) in plans.enumerated() {
                let r = CGRect(x: 160 * u + CGFloat(i) * (cardW + 24 * u), y: 390 * u, width: cardW, height: 560 * u)
                fill(ctx, r, plan.4 ? CGColor(red: 0.12, green: 0.13, blue: 0.22, alpha: 1) : white, radius: 18 * u)
                if !plan.4 { ctx.setStrokeColor(line); ctx.setLineWidth(1.5 * u); ctx.addPath(CGPath(roundedRect: r, cornerWidth: 18 * u, cornerHeight: 18 * u, transform: nil)); ctx.strokePath() }
                let fg: NSColor = plan.4 ? .white : ink
                let sub: NSColor = plan.4 ? NSColor(white: 0.75, alpha: 1) : muted
                text(plan.0, at: CGPoint(x: r.minX + 36 * u, y: r.minY + 36 * u), size: 20 * u, weight: .semibold, color: fg)
                text(plan.1, at: CGPoint(x: r.minX + 36 * u, y: r.minY + 76 * u), size: 54 * u, weight: .bold, color: fg)
                text(plan.2, at: CGPoint(x: r.minX + 36 * u, y: r.minY + 150 * u), size: 15 * u, color: sub)
                fill(ctx, CGRect(x: r.minX + 36 * u, y: r.minY + 200 * u, width: r.width - 72 * u, height: 46 * u),
                     plan.4 ? CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1) : gray, radius: 10 * u)
                text(plan.4 ? "Start 14-day trial" : (i == 0 ? "Create account" : "Talk to sales"), at: CGPoint(x: r.minX + 60 * u, y: r.minY + 212 * u), size: 15 * u, weight: .semibold, color: plan.4 ? .white : ink)
                for (j, feat) in plan.3.enumerated() {
                    let y = r.minY + (280 + CGFloat(j) * 40) * u
                    fill(ctx, CGRect(x: r.minX + 36 * u, y: y + 3 * u, width: 18 * u, height: 18 * u), CGColor(red: 0.12, green: 0.6, blue: 0.35, alpha: 1), radius: 9 * u)
                    text(feat, at: CGPoint(x: r.minX + 66 * u, y: y), size: 15 * u, color: fg)
                }
            }
        }
    }

    static func settingsDialog(_ ctx: CGContext, size: CGSize) {
        flipped(ctx, size) {
            let u = size.width / 1920
            fill(ctx, CGRect(origin: .zero, size: size), gray)
            let r = CGRect(x: 420 * u, y: 160 * u, width: 1080 * u, height: 760 * u)
            fill(ctx, r, white, radius: 16 * u)
            text("Team settings", at: CGPoint(x: r.minX + 40 * u, y: r.minY + 34 * u), size: 24 * u, weight: .semibold, color: ink)
            for (i, tab) in ["General", "Members", "Billing", "Security", "Integrations"].enumerated() {
                let x = r.minX + 40 * u + CGFloat(i) * 130 * u
                text(tab, at: CGPoint(x: x, y: r.minY + 96 * u), size: 15 * u, weight: i == 1 ? .semibold : .regular, color: i == 1 ? ink : muted)
                if i == 1 { fill(ctx, CGRect(x: x, y: r.minY + 124 * u, width: 70 * u, height: 2 * u), CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1)) }
            }
            fill(ctx, CGRect(x: r.minX, y: r.minY + 126 * u, width: r.width, height: 1), line)
            let members = [("Priya Natarajan", "Owner"), ("Diego Álvarez", "Admin"), ("Mei Chen", "Editor"), ("Tom Okafor", "Editor"), ("Sara Lindqvist", "Viewer"), ("Noah Berg", "Viewer")]
            for (i, m) in members.enumerated() {
                let y = r.minY + (160 + CGFloat(i) * 72) * u
                fill(ctx, CGRect(x: r.minX + 40 * u, y: y, width: 40 * u, height: 40 * u), CGColor(red: 0.80, green: 0.84 - Double(i) * 0.05, blue: 0.95, alpha: 1), radius: 20 * u)
                text(m.0, at: CGPoint(x: r.minX + 96 * u, y: y + 2 * u), size: 16 * u, weight: .medium, color: ink)
                text(m.0.lowercased().replacingOccurrences(of: " ", with: ".").folding(options: .diacriticInsensitive, locale: nil) + "@acme.io", at: CGPoint(x: r.minX + 96 * u, y: y + 24 * u), size: 13 * u, color: muted)
                fill(ctx, CGRect(x: r.maxX - 200 * u, y: y + 6 * u, width: 120 * u, height: 30 * u), gray, radius: 8 * u)
                text(m.1 + "  ▾", at: CGPoint(x: r.maxX - 186 * u, y: y + 12 * u), size: 13 * u, color: ink)
                fill(ctx, CGRect(x: r.minX + 40 * u, y: y + 56 * u, width: r.width - 80 * u, height: 1), line)
            }
            fill(ctx, CGRect(x: r.maxX - 220 * u, y: r.maxY - 76 * u, width: 180 * u, height: 44 * u), CGColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1), radius: 10 * u)
            text("Invite member", at: CGPoint(x: r.maxX - 190 * u, y: r.maxY - 64 * u), size: 15 * u, weight: .semibold, color: .white)
        }
    }
}
