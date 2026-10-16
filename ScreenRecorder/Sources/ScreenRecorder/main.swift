import AVFoundation
import AppKit
import Vision
import ScreenCaptureKit
import Foundation
import SwiftUI

// Benchmark: ScreenRecorder --bench <video.mov> <big.png>
// Times every stage a user waits on. Run before and after an optimisation.
if let index = CommandLine.arguments.firstIndex(of: "--bench") {
    guard CommandLine.arguments.indices.contains(index + 2) else { exit(2) }
    let video = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let png = URL(fileURLWithPath: CommandLine.arguments[index + 2])
    let done = DispatchSemaphore(value: 0)
    func ms(_ t: CFAbsoluteTime) -> String { String(format: "%6.0f ms", (CFAbsoluteTimeGetCurrent() - t) * 1000) }
    Task {
        var out: [String] = []
        // 1. Auto-Zoom render throughput.
        let asset = AVURLAsset(url: video)
        let dur = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        var t = CFAbsoluteTimeGetCurrent()
        var opts = PolishExporter.Options(); opts.background = .gradient
        if let o = try? await PolishExporter.polish(videoURL: video, options: opts) {
            let el = CFAbsoluteTimeGetCurrent() - t
            out.append(String(format: "polish %.0fs clip, zoom+halo+frame: %6.0f ms  (%.1fx realtime)", dur, el * 1000, dur / el))
            try? FileManager.default.removeItem(at: o)
        }
        // 2. Silence removal pass alone.
        t = CFAbsoluteTimeGetCurrent()
        _ = try? await SilenceDetector.keptRanges(asset: asset, thresholdDB: -45, minSilence: 1.2, padding: 0.25)
        out.append("silence analysis: " + ms(t))
        // 3. GIF export.
        t = CFAbsoluteTimeGetCurrent()
        if let g = try? await GifExporter.export(videoURL: video) { out.append("gif export: " + ms(t)); try? FileManager.default.removeItem(at: g) }
        // 4. Screenshot pipeline at full res: decode, PNG encode, clipboard encode, downscale, OCR.
        t = CFAbsoluteTimeGetCurrent()
        guard let src = CGImageSourceCreateWithURL(png as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }
        out.append("png decode \(cg.width)x\(cg.height): " + ms(t))
        t = CFAbsoluteTimeGetCurrent()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bench.png")
        if let d = CGImageDestinationCreateWithURL(tmp as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d) }
        out.append("png encode: " + ms(t) + String(format: "  (%.1f MB)", Double((try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0) / 1e6))
        t = CFAbsoluteTimeGetCurrent()
        let (tiff, pngData) = Clipboard.encode(cg)
        out.append("clipboard encode (png now, tiff on demand): " + ms(t) + String(format: "  (png %.1f MB)", Double(pngData?.count ?? 0) / 1e6))
        _ = tiff
        t = CFAbsoluteTimeGetCurrent()
        _ = ScreenshotEditorModel.downscale(cg, maxWidth: 2560)
        out.append("display downscale to 2560: " + ms(t))
        t = CFAbsoluteTimeGetCurrent()
        _ = ScreenshotEditorModel.pixelate(cg, scale: 40)
        out.append("pixelate (blur tool prep): " + ms(t))
        t = CFAbsoluteTimeGetCurrent()
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        out.append("ocr: " + ms(t) + "  (\((req.results ?? []).count) lines)")
        t = CFAbsoluteTimeGetCurrent()
        _ = await RecordingsStore.imageThumbnail(png)
        out.append("thumbnail: " + ms(t))
        try? FileManager.default.removeItem(at: tmp)
        print(out.joined(separator: "\n"))
        done.signal()
    }
    done.wait(); exit(0)
}

// Self-test: ScreenRecorder --selftest-selector
// Presents the area-selection overlay and reports whether each window covers
// its screen exactly (menu bar and notch included).
if CommandLine.arguments.contains("--selftest-selector") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let sel = RegionSelector()
        sel.present { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            var rows: [String] = []
            var allMatch = true
            for (screen, win) in sel.debugFrames() {
                let match = screen.equalTo(win)
                allMatch = allMatch && match
                rows.append("{\"screen\": \"\(Int(screen.minX)),\(Int(screen.minY)) \(Int(screen.width))x\(Int(screen.height))\", \"window\": \"\(Int(win.minX)),\(Int(win.minY)) \(Int(win.width))x\(Int(win.height))\", \"covers_screen\": \(match)}")
            }
            print("{\"ok\": \(allMatch), \"windows\": [" + rows.joined(separator: ", ") + "]}")
            exit(allMatch ? 0 : 1)
        }
        app.run()
    }
}

// Self-test: ScreenRecorder --selftest-region
// Captures a known region via sourceRect and compares it with crops of a full
// display capture under two hypotheses: sourceRect in points, or in pixels.
if CommandLine.arguments.contains("--selftest-region") {
    let reportURL = CaptureEngine.recordingsDirectory().appendingPathComponent("last-region-test.json")
    try? FileManager.default.removeItem(at: reportURL)
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            var report: [String: Any] = ["permission": Permissions.hasScreenRecording]
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var perDisplay: [[String: Any]] = []
                for display in content.displays {
                var report: [String: Any] = [:]
                let bounds = CGDisplayBounds(display.displayID)
                let (pw, ph) = display.pixelSize
                let scale = Double(pw) / bounds.width
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                // Full display.
                let full = SCStreamConfiguration(); full.width = pw; full.height = ph; full.showsCursor = false; full.captureResolution = .best
                let fullImg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                // Region in points: a 400x300 box at (300,200).
                let rect = CGRect(x: 300, y: 200, width: 400, height: 300)
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = rect
                cfg.width = Int(rect.width * scale); cfg.height = Int(rect.height * scale)
                cfg.showsCursor = false; cfg.captureResolution = .best
                let regionImg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                func gray(_ img: CGImage, _ crop: CGRect?) -> [Double] {
                    var src = img
                    if let crop, let c = img.cropping(to: crop) { src = c }
                    let w = 64, h = 48
                    var px = [UInt8](repeating: 0, count: w * h * 4)
                    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.interpolationQuality = .medium
                    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
                    var out: [Double] = []
                    out.reserveCapacity(w * h)
                    var i = 0
                    while i < px.count {
                        let v: Double = (Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 3.0
                        out.append(v)
                        i += 4
                    }
                    return out
                }
                let r = gray(regionImg, nil)
                func diff(_ a: [Double], _ b: [Double]) -> Double {
                    var total = 0.0
                    for k in 0..<min(a.count, b.count) { total += abs(a[k] - b[k]) }
                    return total / Double(max(1, a.count))
                }
                let asPoints = gray(fullImg, CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
                let asPixels = gray(fullImg, rect)
                report["scale"] = scale
                report["display_points"] = "\(Int(bounds.width))x\(Int(bounds.height))"
                report["display_pixels"] = "\(pw)x\(ph)"
                report["region_pixels"] = "\(regionImg.width)x\(regionImg.height)"
                report["diff_if_points"] = (diff(r, asPoints) * 100).rounded() / 100
                report["diff_if_pixels"] = (diff(r, asPixels) * 100).rounded() / 100
                report["display"] = display.displayID
                perDisplay.append(report)
                }
                report["displays"] = perDisplay
                report["ok"] = true
            } catch { report["ok"] = false; report["error"] = error.localizedDescription }
            try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: reportURL)
            exit(0)
        }
        app.run()
    }
}

// Self-test: ScreenRecorder --selftest-hotkeys
// Registers every shortcut and reports which the system accepted.
if CommandLine.arguments.contains("--selftest-hotkeys") {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let hk = HotKeys()
        hk.register { _ in }
        let s = AppSettings.shared
        let table: [(HotKeys.Action, String)] = [
            (.toggleRecording, s.hkToggleRecording), (.recordArea, s.hkRecordArea), (.pause, s.hkPause),
            (.screenshot, s.hkScreenshot), (.screenshotArea, s.hkScreenshotArea), (.screenshotWindow, s.hkScreenshotWindow)]
        var out: [String] = []
        for (a, stored) in table {
            out.append("\"\(a)\": {\"keys\": \"\(HotKeyField.describe(stored))\", \"registered\": \(hk.registered[a] ?? false)}")
        }
        print("{" + out.joined(separator: ", ") + "}")
        exit(hk.registered.values.allSatisfy { $0 } ? 0 : 1)
    }
}

// Self-test: ScreenRecorder --selftest-screenshot
// Captures the main display through the real after-capture path (editor window).
if CommandLine.arguments.contains("--selftest-screenshot") {
    let reportURL = CaptureEngine.recordingsDirectory().appendingPathComponent("last-screenshot-test.json")
    try? FileManager.default.removeItem(at: reportURL)
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            var report: [String: Any] = ["permission": Permissions.hasScreenRecording]
            do {
                guard let display = (try? await ShareableTargets.current())?.displays.first else { throw Screenshotter.ShotError.noDisplay }
                let shot = try await Screenshotter.captureImage(target: .display(display))
                report["ok"] = true
                report["file"] = shot.url.path
                report["bytes"] = (try? FileManager.default.attributesOfItem(atPath: shot.url.path)[.size] as? Int) ?? 0
                report["pixels"] = "\(shot.image.representations.first?.pixelsWide ?? 0)x\(shot.image.representations.first?.pixelsHigh ?? 0)"
                ScreenshotEditorWindows.shared.open(image: shot.image, sourceURL: shot.url)
                report["editor_opened"] = NSApp.windows.contains { $0.title == shot.url.lastPathComponent }
                try? FileManager.default.removeItem(at: shot.url)
            } catch {
                report["ok"] = false
                report["error"] = error.localizedDescription
            }
            try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: reportURL)
            exit(0)
        }
        app.run()
    }
}

// Self-test: ScreenRecorder --selftest-editor <png in> <png out>
// Renders a fixed set of annotations through the editor pipeline.
if let index = CommandLine.arguments.firstIndex(of: "--selftest-editor") {
    guard CommandLine.arguments.indices.contains(index + 2),
          let image = NSImage(contentsOfFile: CommandLine.arguments[index + 1]) else { exit(2) }
    let out = URL(fileURLWithPath: CommandLine.arguments[index + 2])
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: image, sourceURL: nil)
        let w = model.pixelSize.width, h = model.pixelSize.height
        // A 1200 pt wide editor window showing this image.
        model.viewScale = 1200 / w
        let k = 1 / model.viewScale   // image pixels per screen point
        model.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: w * 0.1, y: h * 0.8), end: CGPoint(x: w * 0.4, y: h * 0.5), color: .red, width: 6 * k),
            Annotation(kind: .rect, start: CGPoint(x: w * 0.5, y: h * 0.2), end: CGPoint(x: w * 0.9, y: h * 0.45), color: .yellow, width: 5 * k),
            Annotation(kind: .highlight, start: CGPoint(x: w * 0.1, y: h * 0.1), end: CGPoint(x: w * 0.45, y: h * 0.2), color: .yellow, width: 4 * k),
            Annotation(kind: .blur, start: CGPoint(x: w * 0.55, y: h * 0.6), end: CGPoint(x: w * 0.9, y: h * 0.9), color: .red, width: 4 * k),
            Annotation(kind: .text, start: CGPoint(x: w * 0.12, y: h * 0.3), end: .zero, color: .white, width: 6 * k, text: "Step one"),
            Annotation(kind: .number, start: CGPoint(x: w * 0.5, y: h * 0.55), end: .zero, color: .blue, width: 6 * k, number: 1),
            Annotation(kind: .ellipse, start: CGPoint(x: w * 0.6, y: h * 0.05), end: CGPoint(x: w * 0.8, y: h * 0.18), color: .green, width: 4 * k),
        ]
        // Timing: opening cost and 60 drag updates through the real view.
        let t0 = CFAbsoluteTimeGetCurrent()
        let host = NSHostingView(rootView: ScreenshotEditorView(model: model) {})
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()
        let tOpen = CFAbsoluteTimeGetCurrent() - t0
        let t1 = CFAbsoluteTimeGetCurrent()
        model.tool = .arrow
        model.begin(at: CGPoint(x: 10, y: 10))
        for i in 0..<60 { model.update(to: CGPoint(x: 10 + Double(i) * 5, y: 10 + Double(i) * 3)); host.layoutSubtreeIfNeeded() }
        model.commit()
        let tDrag = CFAbsoluteTimeGetCurrent() - t1
        FileHandle.standardError.write(Data(String(format: "open %.0f ms, 60 drag updates %.0f ms\n", tOpen * 1000, tDrag * 1000).utf8))
        // Copy: pasteboard must end up holding an image.
        NSPasteboard.general.clearContents()
        let countBefore = NSPasteboard.general.changeCount
        model.copyToClipboard()
        let deadline = Date(timeIntervalSinceNow: 20)
        var copied = false
        while !copied && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            copied = NSPasteboard.general.changeCount != countBefore
                && NSPasteboard.general.data(forType: .png) != nil
        }
        // Done: with a simulated pending save, it must wait, overwrite, and close.
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-original.png")
        try? FileManager.default.removeItem(at: tmpURL)
        model.pendingURL = tmpURL
        model.pendingSave = Task.detached { () -> Bool in
            try? await Task.sleep(nanoseconds: 300_000_000)
            try? Data([0x89, 0x50]).write(to: tmpURL)   // a stand-in "original"
            return true
        }
        var closed = false
        model.finish { closed = true }
        let d2 = Date(timeIntervalSinceNow: 15)
        while !closed && Date() < d2 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        let overwritten = ((try? FileManager.default.attributesOfItem(atPath: tmpURL.path)[.size] as? Int) ?? 0) > 1000
        let t2 = CFAbsoluteTimeGetCurrent()
        _ = model.render()
        let tRender = CFAbsoluteTimeGetCurrent() - t2
        FileHandle.standardError.write(Data(String(format: "export render %.0f ms\n", tRender * 1000).utf8))
        FileHandle.standardError.write(Data("copy=\(copied) done_closed=\(closed) overwrote_original=\(overwritten)\n".utf8))
        try? FileManager.default.removeItem(at: tmpURL)
        // Decoration + formats.
        model.style.background = .midnight; model.style.macWindow = true; model.style.title = "Dolly"
        var sizes: [String] = []
        if let deco = model.render(), let dcg = deco.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            for f in ImageFormat.available {
                let t0 = CFAbsoluteTimeGetCurrent()
                let d = ImageEncoder.encode(dcg, format: f, quality: 0.8)
                sizes.append(String(format: "%@=%.1fMB/%.0fms", f.label, Double(d?.count ?? 0) / 1e6, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
            }
            FileHandle.standardError.write(Data("decorated \(dcg.width)x\(dcg.height): \(sizes.joined(separator: " "))\n".utf8))
            if let dest = CGImageDestinationCreateWithURL(out.deletingLastPathComponent().appendingPathComponent("decorated.png") as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, dcg, nil); CGImageDestinationFinalize(dest)
            }
        }
        model.style = FrameStyle()
        guard let rendered = model.render(), let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else {
            print("{\"ok\": false}"); exit(1)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        print("{\"ok\": true, \"width\": \(cg.width), \"height\": \(cg.height), \"annotations\": \(model.annotations.count)}")
        exit(0)
    }
}

// Self-test: ScreenRecorder --selftest-unexpected-stop <seconds>
// Records, then fakes ScreenCaptureKit ending the stream. The file must still
// come out finalised with a telemetry sidecar.
if let index = CommandLine.arguments.firstIndex(of: "--selftest-unexpected-stop") {
    let seconds = Double(CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "3") ?? 3
    let reportURL = CaptureEngine.recordingsDirectory().appendingPathComponent("last-unexpected-stop-test.json")
    try? FileManager.default.removeItem(at: reportURL)
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { delegate.selfTestStartRecording() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + seconds) {
            let active = ActiveRecording.shared.url
            delegate.selfTestSimulateUnexpectedStop()
            // Give finalisation a moment, then inspect the file ourselves.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                var report: [String: Any] = ["active": active?.path ?? ""]
                if let active, let data = try? Data(contentsOf: active) {
                    report["bytes"] = data.count
                    report["moov"] = data.range(of: Data("moov".utf8)) != nil
                    report["telemetry"] = FileManager.default.fileExists(
                        atPath: PolishExporter.telemetryURL(for: active).path)
                }
                try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: reportURL)
                exit(0)
            }
        }
        app.run()
    }
}

// Self-test: ScreenRecorder --selftest-quit <seconds>
// Starts a real recording through the app delegate, then quits the app the
// way ⌘Q does. Proves the file is finalised and the sidecar written on quit.
if let index = CommandLine.arguments.firstIndex(of: "--selftest-quit") {
    let seconds = Double(CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "3") ?? 3
    let reportURL = CaptureEngine.recordingsDirectory().appendingPathComponent("last-quit-test.json")
    try? FileManager.default.removeItem(at: reportURL)
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            delegate.selfTestStartRecording()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + seconds) {
            // Record which file is active, then quit exactly like the menu does.
            let active = ActiveRecording.shared.url
            try? JSONSerialization.data(withJSONObject: ["active": active?.path ?? ""])
                .write(to: reportURL)
            NSApp.terminate(nil)
        }
        app.run()
    }
}

// Self-test: ScreenRecorder --selftest-player <path to .mov>
// Instantiates the in-app player view inside a real NSHostingView, which is
// the exact path that aborted when AVKit was not linked. Exits 0 if it survives.
if let index = CommandLine.arguments.firstIndex(of: "--selftest-player") {
    guard CommandLine.arguments.indices.contains(index + 1) else { exit(2) }
    let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let model = DashboardModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        window.orderBack(nil)
        model.reload()
        let fake = Recording(
            id: url, url: url, name: url.deletingPathExtension().lastPathComponent,
            created: Date(), bytes: 0, duration: nil, hasTelemetry: false, isPolished: false,
            polishedURL: nil)
        model.play(fake, polished: false)
        // Let the sheet build and lay out, then report.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let rate = model.player?.rate ?? -1
            let status = model.player?.currentItem?.status.rawValue ?? -1
            print("{\"ok\": true, \"player_rate\": \(rate), \"item_status\": \(status), \"sheet_presented\": \(model.playing != nil)}")
            exit(0)
        }
        app.run()
    }
}

// Headless trim: ScreenRecorder --trim <path to .mov> <start s> <end s>
if let index = CommandLine.arguments.firstIndex(of: "--trim") {
    let args = CommandLine.arguments
    guard args.indices.contains(index + 3),
        let a = Double(args[index + 2]), let b = Double(args[index + 3])
    else {
        FileHandle.standardError.write(Data("usage: --trim <path> <start> <end>\n".utf8))
        exit(2)
    }
    let input = URL(fileURLWithPath: args[index + 1])
    let done = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        do {
            let output = try await TrimExporter.trim(videoURL: input, start: a, end: b)
            let asset = AVURLAsset(url: output)
            let d = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
            let report: [String: Any] = [
                "ok": true, "output": output.path, "duration_s": (d * 100).rounded() / 100,
                "telemetry_exists": FileManager.default.fileExists(
                    atPath: PolishExporter.telemetryURL(for: output).path),
                "webcam_exists": FileManager.default.fileExists(
                    atPath: WebcamRecorder.sidecarURL(for: output).path),
            ]
            FileHandle.standardOutput.write(
                try JSONSerialization.data(
                    withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Trim failed: \(error.localizedDescription)\n".utf8))
            code = 1
        }
        done.signal()
    }
    done.wait()
    exit(code)
}

// Headless GIF export: ScreenRecorder --gif <path to .mov>
if let index = CommandLine.arguments.firstIndex(of: "--gif") {
    guard CommandLine.arguments.indices.contains(index + 1) else {
        FileHandle.standardError.write(Data("usage: --gif <path to .mov>\n".utf8))
        exit(2)
    }
    let input = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let done = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Task {
        do {
            let started = Date()
            let output = try await GifExporter.export(videoURL: input)
            let attrs = try? FileManager.default.attributesOfItem(atPath: output.path)
            let report: [String: Any] = [
                "ok": true, "output": output.path,
                "bytes": (attrs?[.size] as? Int) ?? 0,
                "render_seconds": (Date().timeIntervalSince(started) * 100).rounded() / 100,
            ]
            FileHandle.standardOutput.write(
                try JSONSerialization.data(
                    withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("GIF failed: \(error.localizedDescription)\n".utf8))
            code = 1
        }
        done.signal()
    }
    done.wait()
    exit(code)
}

// Headless polish: ScreenRecorder --polish <path to .mov>
// Needs no Screen Recording permission -- it only reads existing files.
if let index = CommandLine.arguments.firstIndex(of: "--polish") {
    guard CommandLine.arguments.indices.contains(index + 1) else {
        FileHandle.standardError.write(Data("usage: --polish <path to .mov>\n".utf8))
        exit(2)
    }
    let input = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let done = DispatchSemaphore(value: 0)
    var code: Int32 = 0

    Task {
        do {
            let started = Date()
            var options = PolishExporter.Options()
            let args = CommandLine.arguments
            options.removeSilence = args.contains("--remove-silence")
            if let i = args.firstIndex(of: "--background"), args.indices.contains(i + 1) {
                options.background = PolishExporter.Background(rawValue: args[i + 1]) ?? .none
            }
            if let i = args.firstIndex(of: "--height"), args.indices.contains(i + 1) {
                options.exportHeight = Int(args[i + 1]) ?? 0
            }
            let output = try await PolishExporter.polish(videoURL: input, options: options) { fraction in
                FileHandle.standardError.write(
                    Data("  \(Int(fraction * 100))%\r".utf8))
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: output.path)
            let report: [String: Any] = [
                "ok": true,
                "input": input.path,
                "output": output.path,
                "bytes": (attrs?[.size] as? Int) ?? 0,
                "render_seconds": (Date().timeIntervalSince(started) * 100).rounded() / 100,
            ]
            let json = try JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Polish failed: \(error.localizedDescription)\n".utf8))
            code = 1
        }
        done.signal()
    }
    done.wait()
    exit(code)
}

// Headless capture mode, so the pipeline can be verified without clicking a
// menu: ScreenRecorder --record <seconds> [--mic]
if let index = CommandLine.arguments.firstIndex(of: "--record") {
    let seconds = Double(
        CommandLine.arguments.indices.contains(index + 1)
            ? CommandLine.arguments[index + 1] : "5") ?? 5
    let withMic = CommandLine.arguments.contains("--mic")

    let reportURL = CaptureEngine.recordingsDirectory()
        .appendingPathComponent("last-test-report.json")

    func writeReport(_ object: [String: Any], exitCode: Int32) -> Never {
        if let json = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        {
            try? json.write(to: reportURL, options: .atomic)
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(exitCode)
    }

    guard Permissions.hasScreenRecording else {
        writeReport(
            [
                "ok": false,
                "error": "screen_recording_permission_denied",
                "hint":
                    "System Settings > Privacy & Security > Screen & System Audio Recording, enable Screen Recorder, then relaunch.",
            ], exitCode: 2)
    }

    let engine = CaptureEngine()

    // A real run loop is required even headless: blocking the main thread on a
    // semaphore stops ScreenCaptureKit's callbacks being serviced, and the
    // writer is then torn down mid-finalise, leaving an unplayable file.
    let app = MainActor.assumeIsolated { () -> NSApplication in
        let a = NSApplication.shared
        a.setActivationPolicy(.prohibited)
        return a
    }

    Task { @MainActor in
        do {
            let targets = try await ShareableTargets.current()
            guard let display = targets.displays.first else {
                writeReport(["ok": false, "error": "no_display"], exitCode: 1)
            }
            let url = try await engine.start(
                target: .display(display), captureMicrophone: withMic)
            FileHandle.standardError.write(
                Data("Recording \(seconds)s to \(url.lastPathComponent)\n".utf8))
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

            guard let result = await engine.stop() else {
                writeReport(["ok": false, "error": "stop_returned_no_result"], exitCode: 1)
            }

            let total = result.framesWritten + result.framesDropped
            let dropRate = total > 0 ? Double(result.framesDropped) / Double(total) * 100 : 0
            let attrs = try? FileManager.default.attributesOfItem(atPath: result.videoURL.path)
            let size = (attrs?[.size] as? Int) ?? 0

            let report: [String: Any] = [
                "ok": true,
                "video": result.videoURL.path,
                "telemetry": result.telemetryURL?.path ?? "",
                "bytes": size,
                "duration_s": (result.duration * 100).rounded() / 100,
                "frames_written": result.framesWritten,
                "frames_dropped": result.framesDropped,
                "drop_rate_pct": (dropRate * 100).rounded() / 100,
                "clicks": result.clickCount,
            ]
            writeReport(report, exitCode: 0)
        } catch {
            writeReport(
                ["ok": false, "error": "capture_failed", "detail": error.localizedDescription],
                exitCode: 1)
        }
    }

    MainActor.assumeIsolated { app.run() }
}

// NSApplication.delegate is a weak reference, so the delegate is held here at
// top level rather than inside the closure, where it would be deallocated.
let delegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.delegate = delegate
    // A regular app: Dock icon and its own menu bar. The status-bar icon
    // stays as a shortcut, so recording is reachable from any app.
    app.setActivationPolicy(.regular)
    app.run()
}
