import AppKit
import AVFoundation
import Carbon.HIToolbox
import ImageIO
import SwiftUI

/// `--selftest-features <dir>`: drives the real app objects through every
/// user-facing operation and reports what passed. No UI clicking — the same
/// model methods the buttons call, plus a check that every menu item has a
/// live target. Writes <dir>/report.json and exits with the failure count.
@MainActor
enum FeatureAudit {
    static var dir: URL?

    struct Check: Codable { let name: String; let ok: Bool; let detail: String; let ms: Int }
    private static var checks: [Check] = []

    static func runIfRequested(delegate: AppDelegate) {
        guard let dir else { return }
        Task { @MainActor in
            await run(delegate: delegate, dir: dir)
            let failures = checks.filter { !$0.ok }.count
            let data = try? JSONEncoder().encode(checks)
            try? data?.write(to: dir.appendingPathComponent("report.json"))
            var lines = checks.map { "\($0.ok ? "PASS" : "FAIL")  \($0.name.padding(toLength: 44, withPad: " ", startingAt: 0)) \(String($0.ms).leftPad(6)) ms  \($0.detail)" }
            lines.append("\(checks.count - failures)/\(checks.count) passed")
            let text = lines.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(text.utf8))
            try? text.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(Int32(failures))
        }
    }

    private static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    /// Runs one check, recording pass/fail and timing. A thrown error fails it.
    private static func check(_ name: String, _ body: () async throws -> String) async {
        let t0 = CFAbsoluteTimeGetCurrent()
        progress("… \(name)")
        do { let d = try await body(); checks.append(.init(name: name, ok: true, detail: d, ms: Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))) }
        catch { checks.append(.init(name: name, ok: false, detail: "\(error)", ms: Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))) }
        let c = checks.last!
        progress("\(c.ok ? "PASS" : "FAIL") \(name) (\(c.ms) ms) \(c.detail)")
    }

    private static func progress(_ line: String) {
        guard let dir else { return }
        let url = dir.appendingPathComponent("progress.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
        else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
    }
    struct Fail: Error, CustomStringConvertible { let description: String; init(_ d: String) { description = d } }
    private static func expect(_ cond: Bool, _ msg: String) throws { if !cond { throw Fail(msg) } }

    private static func duration(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }
    private static func size(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }

    // MARK: run

    private static func run(delegate: AppDelegate, dir: URL) async {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let library = CaptureEngine.recordingsDirectory()
        let outDir = dir.appendingPathComponent("exports"); try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        await check("demo library") {
            try await DemoLibrary.build(in: library)
            let files = try fm.contentsOfDirectory(atPath: library.path)
            try expect(files.filter { $0.hasSuffix(".mov") }.count >= 4, "movies: \(files)")
            for name in ["Onboarding walkthrough", "Checkout bug repro", "Weekly product demo"] {
                let d = try await duration(library.appendingPathComponent("\(name).mov"))
                try expect(d > 10, "\(name) truncated: \(d) s")
            }
            return "\(files.count) files"
        }

        // ---- Menus: every item has a live target ----
        await check("menu items have targets") {
            var missing: [String] = [], total = 0, seenKeys: [String: String] = [:], dupes: [String] = []
            func walk(_ menu: NSMenu, _ path: String) {
                for item in menu.items {
                    if let sub = item.submenu { walk(sub, path + "/" + item.title); continue }
                    guard let action = item.action, !item.isSeparatorItem else { continue }
                    total += 1
                    // Standard responder-chain items (Undo, Copy, Close Window…) resolve
                    // against whichever window is key; they have no fixed target.
                    let responderChain: Set<String> = ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "performClose:", "performMiniaturize:", "performZoom:", "delete:"]
                    let target = item.target ?? NSApp.target(forAction: action, to: nil, from: item)
                    if !responderChain.contains(NSStringFromSelector(action)), target == nil || !((target as AnyObject).responds(to: action)) { missing.append(path + "/" + item.title) }
                    if !item.keyEquivalent.isEmpty {
                        let key = "\(item.keyEquivalentModifierMask.rawValue):\(item.keyEquivalent)"
                        // The status-bar menu mirrors the main menu; the same action twice is fine.
                        let ident = NSStringFromSelector(action)
                        if let other = seenKeys[key], other != ident { dupes.append("\(other) ↔ \(ident)") } else { seenKeys[key] = ident }
                    }
                }
            }
            if let main = NSApp.mainMenu { walk(main, "") }
            if let status = delegate.statusItem.menu { walk(status, "status") }
            try expect(missing.isEmpty, "no target: \(missing)")
            try expect(dupes.isEmpty, "duplicate shortcuts: \(dupes)")
            return "\(total) actionable items"
        }

        // ---- Dashboard ----
        let dash = delegate.dashboard
        dash.show()
        dash.model.reload()
        await wait(3)
        await check("dashboard scan") {
            let m = dash.model
            try expect(m.recordings.count == 3, "recordings=\(m.recordings.count)")
            try expect(m.screenshots.count == 3, "screenshots=\(m.screenshots.count)")
            try expect(m.recordings.filter(\.isPolished).count == 1, "polished=\(m.recordings.filter(\.isPolished).count)")
            try expect(m.recordings.allSatisfy { $0.duration != nil }, "durations missing")
            try expect(m.recordings.allSatisfy { m.thumbnails[$0.url] != nil }, "thumbnails missing")
            return "3 recordings · 3 screenshots · 1 polished"
        }
        guard let short = dash.model.recordings.first(where: { $0.name == "Checkout bug repro" }) else { return }
        let shortDuration = (try? await duration(short.url)) ?? 0

        for format in ExportService.Format.allCases {
            await check("export \(format.rawValue)") {
                let out = outDir.appendingPathComponent("export.\(format.ext)")
                try await ExportService.export(source: short.url, to: out, format: format)
                try expect(size(out) > 1000, "size \(size(out))")
                if format == .gif {
                    let src = CGImageSourceCreateWithURL(out as CFURL, nil)
                    try expect((src.map { CGImageSourceGetCount($0) } ?? 0) > 10, "gif frames")
                } else {
                    let d = try await duration(out)
                    try expect(abs(d - shortDuration) < 0.6, "duration \(d) vs source \(shortDuration)")
                }
                return ByteCountFormatter.string(fromByteCount: Int64(size(out)), countStyle: .file)
            }
        }
        await check("trim keep 2–5 s") {
            let out = try await TrimExporter.trim(videoURL: short.url, start: 2, end: 5)
            let d = try await duration(out); try expect(abs(d - 3) < 0.4, "duration \(d)")
            try? fm.removeItem(at: out); try? fm.removeItem(at: PolishExporter.telemetryURL(for: out))
            return String(format: "%.2f s", d)
        }
        await check("trim remove 2–5 s") {
            let out = try await TrimExporter.trim(videoURL: short.url, start: 2, end: 5, remove: true)
            let d = try await duration(out); try expect(abs(d - (shortDuration - 3)) < 0.4, "duration \(d) vs \(shortDuration - 3)")
            try? fm.removeItem(at: out); try? fm.removeItem(at: PolishExporter.telemetryURL(for: out))
            return String(format: "%.2f s", d)
        }
        await check("rename with sidecars") {
            let renamed = try ExportService.rename(short, to: "Renamed clip")
            try expect(fm.fileExists(atPath: renamed.path), "video not renamed")
            try expect(fm.fileExists(atPath: PolishExporter.telemetryURL(for: renamed).path), "telemetry did not follow")
            try expect(fm.fileExists(atPath: PolishExporter.outputURL(for: renamed).path), "polished did not follow")
            dash.model.reload(); await wait(0.5)
            guard let r = dash.model.recordings.first(where: { $0.url == renamed }) else { throw Fail("not in library after rename") }
            _ = try ExportService.rename(r, to: short.name)
            dash.model.reload()
            return "renamed and restored"
        }
        await check("auto-zoom polish") {
            guard let rec = dash.model.recordings.first(where: { $0.name == "Onboarding walkthrough" }) else { throw Fail("missing") }
            let out = try await PolishExporter.polish(videoURL: rec.url, options: AppSettings.shared.polishOptions)
            let d = try await duration(out); try expect(d > 5, "duration \(d)")
            dash.model.reload()
            return String(format: "%.1f s output", d)
        }
        await check("play / close player") {
            dash.model.play(short, polished: true); await wait(1.5)
            try expect(dash.model.playing != nil && dash.playerWindow?.isVisible == true, "player not shown")
            dash.model.closePlayer(); await wait(0.5)
            try expect(dash.model.playing == nil, "player still open")
            return "ok"
        }
        await check("trim sheet open / cancel") {
            dash.model.beginTrim(short); await wait(1.5)
            try expect(dash.trimWindow?.isVisible == true, "trim window not shown")
            dash.model.seekTrim(to: 3)
            dash.model.cancelTrim(); await wait(0.3)
            try expect(dash.model.trimming == nil, "still trimming")
            return "ok"
        }
        await check("copy screenshot to clipboard") {
            guard let shot = dash.model.screenshots.first else { throw Fail("no screenshot") }
            dash.model.copyScreenshot(shot); await wait(0.3)
            try expect(NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil), "no image on pasteboard")
            return shot.name
        }
        await check("delete screenshot") {
            let tmp = library.appendingPathComponent("Delete me.png")
            try fm.copyItem(at: dash.model.screenshots[0].url, to: tmp)
            dash.model.reload(); await wait(0.5)
            guard let s = dash.model.screenshots.first(where: { $0.url == tmp }) else { throw Fail("copy not scanned") }
            dash.model.deleteScreenshot(s)
            try expect(!fm.fileExists(atPath: tmp.path), "still exists")
            return "trashed"
        }
        await check("section / sort / search state") {
            let m = dash.model
            for s in LibrarySection.allCases { m.section = s }
            for s in SortOrder.allCases { m.sort = s }
            m.section = .recordings
            return "\(LibrarySection.allCases.count) sections · \(SortOrder.allCases.count) sort orders"
        }

        // ---- Settings persistence + hotkeys ----
        await check("settings persist") {
            let s = AppSettings.shared
            let before = (s.frameRate, s.countdownEnabled, s.removeSilence)
            s.frameRate = 60; s.countdownEnabled = false; s.removeSilence = true
            let d = UserDefaults.standard
            try expect(d.integer(forKey: "frameRate") == 60 && d.bool(forKey: "countdown") == false && d.bool(forKey: "removeSilence") == true, "not written")
            try expect(s.polishOptions.removeSilence, "polishOptions ignores setting")
            s.frameRate = before.0; s.countdownEnabled = before.1; s.removeSilence = before.2
            for tab in ["general", "recording", "polish", "screenshots", "hotkeys"] { s.settingsTab = tab }
            return "3 keys round-tripped"
        }
        await check("hotkeys registered") {
            guard let hk = HotKeys.active else { throw Fail("no HotKeys instance") }
            let bad = hk.registered.filter { !$0.value }.map { "\($0.key)" }
            try expect(bad.isEmpty, "not registered: \(bad)")
            hk.suspend(); hk.resume()
            try expect(hk.registered.values.allSatisfy { $0 }, "lost after suspend/resume")
            let s = "\(kVK_ANSI_Q):\(cmdKey | controlKey)"
            try expect(HotKeyField.describe(s) == "⌃⌘Q", "describe → \(HotKeyField.describe(s))")
            return "\(hk.registered.count) shortcuts"
        }

        // ---- Screenshot editor ----
        let shotURL = library.appendingPathComponent("Pricing page.png")
        guard let image = NSImage(contentsOf: shotURL) else { return }
        let (model, win) = ScreenshotEditorWindows.shared.open(image: image, sourceURL: shotURL)
        await wait(1)
        let W = model.pixelSize.width, H = model.pixelSize.height
        for kind in AnnotationKind.allCases where kind != .picker && kind != .crop {
            await check("editor tool: \(kind.label)") {
                model.tool = kind
                model.annotations = [Annotation(kind: kind, start: CGPoint(x: W * 0.2, y: H * 0.2), end: CGPoint(x: W * 0.6, y: H * 0.6), color: .red, width: 8, text: "Hello", number: 1)]
                guard let out = model.render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Fail("render nil") }
                try expect(cg.width == Int(W) && cg.height == Int(H), "size \(cg.width)x\(cg.height)")
                return "rendered \(cg.width)×\(cg.height)"
            }
        }
        await check("editor: colour picker") {
            model.tool = .picker
            model.pick(at: CGPoint(x: W * 0.5, y: H * 0.05))
            try expect(NSPasteboard.general.string(forType: .string)?.hasPrefix("#") == true, "no hex on pasteboard")
            return NSPasteboard.general.string(forType: .string) ?? ""
        }
        await check("editor: crop") {
            model.annotations = []
            model.crop = CGRect(x: 0, y: 0, width: W / 2, height: H / 2)
            guard let out = model.render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Fail("render nil") }
            try expect(cg.width == Int(W / 2), "width \(cg.width)")
            model.crop = nil
            return "\(cg.width)×\(cg.height)"
        }
        await check("editor: undo / redo / clear") {
            model.annotations = []
            model.tool = .rect
            model.begin(at: CGPoint(x: 10, y: 10)); model.update(to: CGPoint(x: 200, y: 200)); model.commit()
            try expect(model.annotations.count == 1, "commit did not add")
            model.undo(); try expect(model.annotations.isEmpty, "undo failed")
            model.redo(); try expect(model.annotations.count == 1, "redo failed")
            model.clear(); try expect(model.annotations.isEmpty, "clear failed")
            return "ok"
        }
        await check("editor: zoom") {
            model.zoomIn(); let a = model.zoom; model.zoomOut(); model.zoomFit()
            try expect(a != nil && model.zoom == nil, "zoom state")
            return "ok"
        }
        await check("editor: style decoration") {
            model.style.background = .ocean; model.style.macWindow = true; model.style.title = "Audit"
            guard let out = model.render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Fail("render nil") }
            let expected = model.style.canvasSize(for: CGSize(width: W, height: H))
            try expect(cg.width == Int(expected.width) && cg.height == Int(expected.height), "size \(cg.width)x\(cg.height) vs \(expected)")
            model.style = FrameStyle()
            return "\(cg.width)×\(cg.height)"
        }
        model.annotations = [Annotation(kind: .arrow, start: CGPoint(x: W * 0.7, y: H * 0.3), end: CGPoint(x: W * 0.6, y: H * 0.5), color: .red, width: 8)]
        await check("editor: copy to clipboard") {
            NSPasteboard.general.clearContents()
            model.copyToClipboard()
            for _ in 0..<40 { if NSPasteboard.general.data(forType: .png) != nil || NSPasteboard.general.data(forType: .tiff) != nil { break }; await wait(0.1) }
            try expect(NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil), "no image")
            return "image on pasteboard"
        }
        await check("editor: save as new") {
            guard let url = model.save(overwrite: false) else { throw Fail("nil url") }
            for _ in 0..<40 { if size(url) > 0 { break }; await wait(0.1) }
            try expect(size(url) > 1000, "size \(size(url))")
            try? fm.removeItem(at: url)
            return url.lastPathComponent
        }
        for format in ImageFormat.available {
            await check("editor: export \(format.label)") {
                guard let out = model.render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Fail("render nil") }
                let url = outDir.appendingPathComponent("shot.\(format.ext)")
                let bytes = await ScreenshotEditorModel.export(cg, to: url, format: format, quality: 0.8)
                try expect(bytes > 500, "bytes \(bytes)")
                if format != .pdf {
                    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { throw Fail("unreadable") }
                    try expect((props[kCGImagePropertyPixelWidth] as? Int) == Int(W), "width \(String(describing: props[kCGImagePropertyPixelWidth]))")
                }
                let est = await model.estimateSize(format: format, quality: 0.8) ?? 0
                return "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) (est. \(ByteCountFormatter.string(fromByteCount: Int64(est), countStyle: .file)))"
            }
        }
        await check("editor: OCR copy text") {
            NSPasteboard.general.clearContents()
            model.copyText()
            var text = ""
            for _ in 0..<100 { if let t = NSPasteboard.general.string(forType: .string), !t.isEmpty { text = t; break }; await wait(0.1) }
            try expect(text.lowercased().contains("pricing"), "text: '\(text.prefix(80))' message: \(model.message ?? "-") busy: \(model.busy ?? "-")")
            return "\(text.split(separator: " ").count) words"
        }
        await check("editor: pin on screen") {
            let before = PinnedScreenshots.shared.count
            PinnedScreenshots.shared.pin(model.render() ?? image)
            try expect(PinnedScreenshots.shared.count == before + 1, "count \(PinnedScreenshots.shared.count)")
            return "pinned"
        }
        await check("editor: done closes") {
            var closed = false
            model.finish { closed = true; win.close() }
            for _ in 0..<60 { if closed { break }; await wait(0.1) }
            try expect(closed, "finish never completed")
            return "ok"
        }
        await check("screenshot preview thumbnail") {
            ScreenshotPreview.shared.show(image: image, url: shotURL); await wait(0.5)
            ScreenshotPreview.shared.dismiss()
            return "ok"
        }

        // ---- Live capture through the real menu actions ----
        let settings = AppSettings.shared
        let savedFolder = settings.screenshotFolderPath; settings.screenshotFolderPath = ""
        await check("screenshot screen (menu action)") {
            let before = Set((try? fm.contentsOfDirectory(atPath: library.path)) ?? [])
            delegate.perform(NSSelectorFromString("screenshotScreenTapped"))
            await wait(3)
            let after = Set((try? fm.contentsOfDirectory(atPath: library.path)) ?? []).subtracting(before)
            let png = after.first { $0.hasPrefix("Screenshot") }
            try expect(png != nil, "no new screenshot: \(after)")
            try expect(size(library.appendingPathComponent(png!)) > 10_000, "tiny file")
            ScreenshotEditorWindows.shared.closeAll()
            return png!
        }
        await check("record full screen → stop (menu actions)") {
            let before = Set((try? fm.contentsOfDirectory(atPath: library.path)) ?? [])
            let countdown = settings.countdownEnabled; settings.countdownEnabled = false
            let t0 = CFAbsoluteTimeGetCurrent()
            delegate.perform(NSSelectorFromString("startTapped"))
            // A system re-authorisation prompt can hold the stream start; wait for it.
            for _ in 0..<1200 { if delegate.engineIsRecording { break }; await wait(0.25) }
            let startSeconds = CFAbsoluteTimeGetCurrent() - t0
            try expect(delegate.engineIsRecording, "engine not recording after \(Int(startSeconds)) s")
            await wait(3)
            delegate.perform(NSSelectorFromString("pauseTapped")); await wait(1)
            delegate.perform(NSSelectorFromString("pauseTapped")); await wait(1)
            delegate.perform(NSSelectorFromString("stopTapped"))
            for _ in 0..<60 { if !delegate.engineIsRecording { break }; await wait(0.25) }
            await wait(1.5)
            settings.countdownEnabled = countdown
            let after = Set((try? fm.contentsOfDirectory(atPath: library.path)) ?? []).subtracting(before)
            guard let mov = after.first(where: { $0.hasSuffix(".mov") && $0.hasPrefix("Recording") }) else { throw Fail("no recording: \(after)") }
            let url = library.appendingPathComponent(mov)
            let d = try await duration(url); try expect(d > 2.5, "duration \(d)")
            try expect(fm.fileExists(atPath: PolishExporter.telemetryURL(for: url).path), "no telemetry sidecar")
            return String(format: "%@ · %.1f s (1 s paused) · stream started after %.1f s", mov, d, startSeconds)
        }
        settings.screenshotFolderPath = savedFolder
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}
