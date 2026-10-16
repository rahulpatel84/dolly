import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Annotation model

enum ArrowStyle: String, CaseIterable, Identifiable {
    case single, double, line
    var id: String { rawValue }
    var symbol: String {
        switch self { case .single: return "arrow.right"; case .double: return "arrow.left.and.right"; case .line: return "minus" }
    }
}

enum AnnotationKind: String, CaseIterable, Identifiable {
    case picker, arrow, rect, ellipse, line, highlight, blur, text, number, crop
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .picker: return "eyedropper"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .highlight: return "highlighter"
        case .blur: return "drop.halffull"
        case .text: return "textformat"
        case .number: return "1.circle"
        case .crop: return "crop"
        }
    }
    var label: String { rawValue.capitalized }
    /// One line shown while hovering the tool and while it is selected.
    var hint: String {
        switch self {
        case .picker: return "Colour picker — click any pixel to copy its hex value"
        case .arrow: return "Arrow — drag from tail to head; style and width below"
        case .rect: return "Rectangle — drag to outline an area"
        case .ellipse: return "Ellipse — drag to circle something"
        case .line: return "Line — drag to draw a straight line"
        case .highlight: return "Highlighter — drag a translucent band over text"
        case .blur: return "Blur — drag over anything sensitive to pixelate it"
        case .text: return "Text — click to place a label, then type"
        case .number: return "Numbered step — click to drop the next badge"
        case .crop: return "Crop — drag the area to keep; Done applies it"
        }
    }
    var key: KeyEquivalent {
        switch self {
        case .picker: return "p"
        case .arrow: return "a"; case .rect: return "r"; case .ellipse: return "o"; case .line: return "l"
        case .highlight: return "h"; case .blur: return "b"; case .text: return "t"; case .number: return "n"; case .crop: return "c"
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    /// Image-pixel coordinates, top-left origin.
    var start: CGPoint
    var end: CGPoint
    var color: Color
    var width: CGFloat
    var text: String = ""
    var number: Int = 0
    var arrowStyle: ArrowStyle = .single

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

// MARK: - Editor model

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    @Published var sourceURL: URL?
    let image: NSImage
    let cgImage: CGImage?
    let pixelSize: CGSize
    /// Built on first use of the blur tool, off the main thread.
    @Published private(set) var pixelatedCG: CGImage?
    @Published private(set) var preparingBlur = false
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    @Published var annotations: [Annotation] = []
    @Published var tool: AnnotationKind = .arrow {
        didSet { if tool == .blur { preparePixelated() } }
    }
    @Published var color: Color = .red
    @Published var width: CGFloat = 4
    @Published var draft: Annotation?
    @Published var crop: CGRect?
    @Published var selected: UUID?
    @Published var message: String?
    @Published var textEntry: String = ""
    @Published var editingText: Annotation?
    @Published var arrowStyle: ArrowStyle = .single
    /// nil = fit to window; otherwise "100% = one image pixel per screen pixel".
    @Published var zoom: CGFloat? = nil
    var zoomToFit: Bool { get { zoom == nil } set { zoom = newValue ? nil : 1 } }
    func zoomIn() { zoom = min(8, (zoom ?? fitZoom) * 1.25) }
    func zoomOut() { zoom = max(0.1, (zoom ?? fitZoom) / 1.25) }
    func zoomFit() { zoom = nil }
    /// What "fit" currently equals, so zoom steps start from it.
    var fitZoom: CGFloat = 1
    /// Backing scale of the screen the editor window is actually on. NSScreen.main
    /// is the screen with keyboard focus, which is the wrong one on a multi-display
    /// Mac whenever the editor opens on a secondary display.
    @Published var screenScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    @Published var pickedHex: String?
    @Published var busy: String?
    @Published var style = FrameStyle()
    @Published var exportFormat: ImageFormat = .png
    @Published var exportQuality: Double = 0.85
    @Published var showExport = false
    @Published var showStyle = false
    /// Set while the pointer is over a toolbar control; shown in the hint line.
    @Published var hoverHint: String?
    /// Screen points per image pixel for the current window size. The stroke
    /// slider is in screen points; annotations store image pixels, so a 6 pt
    /// arrow is 6 pt on screen AND the equivalent thickness in the export,
    /// whether the capture is 1280 or 6912 pixels wide.
    var viewScale: CGFloat = 1
    /// The capture's background save; Done waits for it before overwriting.
    var pendingSave: Task<Bool, Never>?
    var pendingURL: URL?
    private var undone: [Annotation] = []
    private var nextNumber = 1

    /// What the editor draws on screen. A 6912×4468 capture is 31 megapixels;
    /// showing it means a ~120 MB texture and a slow first frame. Annotations
    /// are stored in full-resolution coordinates, so a ≤2560 px copy is
    /// visually identical on any display and the export is still full size.
    let displayImage: NSImage

    init(image: NSImage, sourceURL: URL?) {
        self.image = image
        self.sourceURL = sourceURL
        let rep = image.representations.first
        pixelSize = CGSize(width: rep?.pixelsWide ?? Int(image.size.width),
                           height: rep?.pixelsHigh ?? Int(image.size.height))
        cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        // Display copy: only shrink what is larger than a 6K-class screen can
        // show. Anything smaller is displayed from the original so the preview
        // is pixel-sharp on Retina; the previous 2560 px cap looked soft.
        if let cg = cgImage, cg.width > 4096, let small = Self.downscale(cg, maxWidth: 4096) {
            displayImage = NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height))
        } else {
            displayImage = image
        }
    }

    nonisolated static func downscale(_ cg: CGImage, maxWidth: Int) -> CGImage? {
        FastImage.downscale(cg, maxWidth: maxWidth)
    }

    /// One pixelated copy serves every blur annotation. Computed on demand
    /// so opening the editor costs nothing for the common no-blur case.
    func preparePixelated() {
        guard pixelatedCG == nil, !preparingBlur else { return }
        // Pixelate the display-sized copy: visually identical on screen and
        // ~10× cheaper. Export re-pixelates at full resolution.
        guard let cg = displayImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        preparingBlur = true
        let scale = max(4, CGFloat(cg.width) / 160)
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.pixelate(cg, scale: scale)
            await MainActor.run {
                self?.pixelatedCG = result
                self?.preparingBlur = false
            }
        }
    }

    // Drawing
    func begin(at p: CGPoint) {
        if tool == .picker { pick(at: p); return }
        if tool == .crop { crop = CGRect(origin: p, size: .zero); draft = nil; return }
        var a = Annotation(kind: tool, start: p, end: p, color: color, width: width / max(0.02, viewScale))
        a.arrowStyle = arrowStyle
        if tool == .number { a.number = nextNumber }
        if tool == .text { a.text = "Text"; a.end = p }
        draft = a
    }
    func update(to p: CGPoint) {
        if tool == .crop, var c = crop { c.size = CGSize(width: p.x - c.origin.x, height: p.y - c.origin.y); crop = c; return }
        draft?.end = p
    }
    /// Colour picker: sample the pixel under the cursor, copy its hex.
    func pick(at p: CGPoint) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let x = Int(max(0, min(CGFloat(cg.width - 1), p.x))), y = Int(max(0, min(CGFloat(cg.height - 1), p.y)))
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        let hex = String(format: "#%02X%02X%02X", px[0], px[1], px[2])
        pickedHex = hex
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        message = "Copied \(hex)"
    }

    func commit() {
        if tool == .picker { return }
        if tool == .crop, let c = crop { crop = c.standardized; if crop!.width < 4 || crop!.height < 4 { crop = nil }; return }
        guard var a = draft else { return }
        draft = nil
        if a.kind == .number { nextNumber += 1; a.end = a.start }
        if a.kind != .text && a.kind != .number && hypot(a.end.x - a.start.x, a.end.y - a.start.y) < 3 { return }
        annotations.append(a)
        undone.removeAll()
        if a.kind == .text { editingText = a; textEntry = "" }
    }
    func applyText() {
        guard let e = editingText, let i = annotations.firstIndex(where: { $0.id == e.id }) else { return }
        if textEntry.isEmpty { annotations.remove(at: i) } else { annotations[i].text = textEntry }
        editingText = nil
    }
    func undo() { if let a = annotations.popLast() { undone.append(a); if a.kind == .number { nextNumber = max(1, nextNumber - 1) } } }
    func redo() { if let a = undone.popLast() { annotations.append(a); if a.kind == .number { nextNumber += 1 } } }
    func clear() { annotations.removeAll(); undone.removeAll(); crop = nil; nextNumber = 1 }

    // Output
    func render() -> NSImage? {
        guard let cg = cgImage else { return nil }
        // Blur annotations need the pixelated copy; build it now if it is
        // not ready yet (first use was already kicked off in the background).
        if annotations.contains(where: { $0.kind == .blur }), pixelatedCG == nil {
            pixelatedCG = Self.pixelate(cg, scale: max(8, pixelSize.width / 160))
        }
        guard var out = AnnotationRenderer.render(base: cg, pixelated: pixelatedCG, annotations: annotations, crop: crop) else { return nil }
        if style.isActive, let decorated = Decorator.decorate(out, style: style) { out = decorated }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    nonisolated static func pixelate(_ cg: CGImage, scale: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: cg)
        let f = CIFilter(name: "CIPixellate")!
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(scale, forKey: kCIInputScaleKey)
        f.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let out = f.outputImage?.cropped(to: ci.extent) else { return nil }
        return ciContext.createCGImage(out, from: ci.extent)
    }

    func copyToClipboard() {
        guard let out = render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            message = "Could not render"; return
        }
        busy = "Copying…"
        // Encode off the main thread (slow for 30 megapixels), then hand the
        // finished bytes to the pasteboard ON the main thread. Writing a lazy
        // NSImage from a background thread was unreliable.
        Task.detached(priority: .userInitiated) { [weak self] in
            let (tiff, png) = Clipboard.encode(cg)
            await MainActor.run {
                Clipboard.set(tiff: tiff, png: png, source: cg)
                self?.busy = nil
                self?.message = "Copied to clipboard"
            }
        }
    }

    /// Done: make sure the original exists, overwrite it with the edits,
    /// copy the result, then close. Waits for the background save if needed.
    func finish(then close: @escaping () -> Void) {
        busy = "Saving…"
        Task { @MainActor in
            if sourceURL == nil, let pending = pendingSave, let url = pendingURL {
                if await pending.value { sourceURL = url }
            }
            let saved = save(overwrite: sourceURL != nil)
            if let out = render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let (tiff, png) = await Task.detached { Clipboard.encode(cg) }.value
                Clipboard.set(tiff: tiff, png: png, source: cg)
            }
            busy = nil
            message = saved.map { "Saved \($0.lastPathComponent) · copied" } ?? "Save failed"
            close()
        }
    }

    func save(overwrite: Bool) -> URL? {
        guard let out = render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let url: URL
        if overwrite, let sourceURL { url = sourceURL }
        else {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            url = AppSettings.shared.screenshotFolder.appendingPathComponent("Screenshot \(f.string(from: Date())) (edited).png")
        }
        guard FastImage.writePNG(cg, to: url) else { return nil }
        message = "Saved \(url.lastPathComponent)"
        return url
    }

    /// Export in any format via a save panel; quality applies to lossy ones.
    func exportAs(_ format: ImageFormat, quality: Double) {
        guard let out = render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "Screenshot"
        panel.nameFieldStringValue = "\(base).\(format.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = "Exporting…"
        Task.detached(priority: .userInitiated) { [weak self] in
            let data = ImageEncoder.encode(cg, format: format, quality: quality)
            let ok = data.map { (try? $0.write(to: url, options: .atomic)) != nil } ?? false
            await MainActor.run {
                self?.busy = nil
                self?.message = ok ? "Exported \(url.lastPathComponent) · \(ByteCountFormatter.string(fromByteCount: Int64(data?.count ?? 0), countStyle: .file))" : "Export failed"
                if ok { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    /// Size the current render would be in `format` at `quality` — for the
    /// compression slider. Estimated on a ≤1600 px copy and scaled by area.
    func estimateSize(format: ImageFormat, quality: Double) async -> Int? {
        guard let out = render(), let full = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Task.detached(priority: .utility) { () -> Int? in
            let sample = FastImage.downscale(full, maxWidth: 1600) ?? full
            guard let d = ImageEncoder.encode(sample, format: format, quality: quality) else { return nil }
            let ratio = Double(full.width * full.height) / Double(sample.width * sample.height)
            return Int(Double(d.count) * (format == .pdf || format == .tiff ? ratio : pow(ratio, 0.9)))
        }.value
    }

    /// Renders once and hands the file to the system share picker.
    func share(from view: NSView) {
        guard let out = render(), let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot \(Int(Date().timeIntervalSince1970)).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// OCR via Vision: copies every recognised line, top to bottom.
    func copyText() {
        // Vision at 31 megapixels took over a minute; at 2000 px wide text is
        // still perfectly legible and it takes a second or two.
        guard let full = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cg = FastImage.downscale(full, maxWidth: 2000) else { return }
        busy = "Reading text…"
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                .compactMap { $0.topCandidates(1).first?.string }
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                self?.busy = nil
                self?.message = lines.isEmpty ? "No text found" : "Copied \(lines.count) lines of text"
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        }
    }
}

// MARK: - Canvas

struct AnnotationCanvas: View {
    @ObservedObject var model: ScreenshotEditorModel

    var body: some View {
        ZStack {
            // The screenshot is a plain Image layer (the ≤2560 px display
            // copy): composited once, never re-rasterised while dragging.
            Image(nsImage: model.displayImage).resizable().interpolation(.high)
            canvas
        }
    }

    private var canvas: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let scale = size.width / model.pixelSize.width
            for a in model.annotations { draw(a, in: &ctx, scale: scale) }
            if let d = model.draft { draw(d, in: &ctx, scale: scale) }
            if let c = model.crop {
                // Dim everything outside the crop.
                var outside = Path(CGRect(origin: .zero, size: size))
                outside.addRect(c.scaled(scale))
                ctx.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                ctx.stroke(Path(c.scaled(scale)), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
    }

    private func draw(_ a: Annotation, in ctx: inout GraphicsContext, scale: CGFloat) {
        let s = CGPoint(x: a.start.x * scale, y: a.start.y * scale)
        let e = CGPoint(x: a.end.x * scale, y: a.end.y * scale)
        let r = a.rect.scaled(scale)
        let lw = a.width * scale
        switch a.kind {
        case .line:
            var p = Path(); p.move(to: s); p.addLine(to: e)
            ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .arrow:
            var p = Path(); p.move(to: s); p.addLine(to: e)
            ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            if a.arrowStyle != .line {
                let head = max(10, lw * 4)
                func headPath(at tip: CGPoint, from tail: CGPoint) -> Path {
                    let angle = atan2(tip.y - tail.y, tip.x - tail.x)
                    var h = Path()
                    h.move(to: tip)
                    h.addLine(to: CGPoint(x: tip.x - head * cos(angle - .pi / 6), y: tip.y - head * sin(angle - .pi / 6)))
                    h.addLine(to: CGPoint(x: tip.x - head * cos(angle + .pi / 6), y: tip.y - head * sin(angle + .pi / 6)))
                    h.closeSubpath()
                    return h
                }
                ctx.fill(headPath(at: e, from: s), with: .color(a.color))
                if a.arrowStyle == .double { ctx.fill(headPath(at: s, from: e), with: .color(a.color)) }
            }
        case .rect:
            ctx.stroke(Path(roundedRect: r, cornerRadius: lw), with: .color(a.color), lineWidth: lw)
        case .ellipse:
            ctx.stroke(Path(ellipseIn: r), with: .color(a.color), lineWidth: lw)
        case .highlight:
            ctx.fill(Path(r), with: .color(a.color.opacity(0.35)))
        case .blur:
            if let px = model.pixelatedCG {
                ctx.drawLayer { layer in
                    layer.clip(to: Path(r))
                    layer.draw(Image(decorative: px, scale: 1), in: CGRect(origin: .zero, size: CGSize(width: model.pixelSize.width * scale, height: model.pixelSize.height * scale)))
                }
            } else {
                // Not ready yet: a translucent placeholder, replaced on the next draw.
                ctx.fill(Path(r), with: .color(.gray.opacity(0.6)))
            }
        case .text:
            let font = Font.system(size: max(12, lw * 5), weight: .semibold)
            let text = Text(a.text.isEmpty ? "Text" : a.text).font(font).foregroundStyle(a.color)
            let resolved = ctx.resolve(text)
            let sz = resolved.measure(in: CGSize(width: 2000, height: 2000))
            let bg = CGRect(x: s.x - 4, y: s.y - 2, width: sz.width + 8, height: sz.height + 4)
            ctx.fill(Path(roundedRect: bg, cornerRadius: 4), with: .color(.black.opacity(0.55)))
            ctx.draw(resolved, at: s, anchor: .topLeading)
        case .number:
            let rad = max(12, lw * 3.5)
            let circle = CGRect(x: s.x - rad, y: s.y - rad, width: rad * 2, height: rad * 2)
            ctx.fill(Path(ellipseIn: circle), with: .color(a.color))
            ctx.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: max(1.5, lw * 0.5))
            let t = ctx.resolve(Text("\(a.number)").font(.system(size: rad * 1.1, weight: .bold)).foregroundStyle(.white))
            ctx.draw(t, at: s, anchor: .center)
        case .crop, .picker:
            break
        }
    }
}

/// Full-resolution export with CoreGraphics. Several times faster than
/// rendering the SwiftUI canvas at 31 megapixels, and independent of the
/// on-screen display scale.
enum AnnotationRenderer {
    static func render(base: CGImage, pixelated: CGImage?, annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Flip to top-left origin so annotation coordinates can be used as-is.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        for a in annotations {
            let color = NSColor(a.color).cgColor
            let r = a.rect
            let lw = a.width
            switch a.kind {
            case .line, .arrow:
                ctx.setStrokeColor(color); ctx.setLineWidth(lw); ctx.setLineCap(.round)
                ctx.move(to: a.start); ctx.addLine(to: a.end); ctx.strokePath()
                if a.kind == .arrow && a.arrowStyle != .line {
                    let head = max(10, lw * 4)
                    func drawHead(tip: CGPoint, tail: CGPoint) {
                        let ang = atan2(tip.y - tail.y, tip.x - tail.x)
                        ctx.move(to: tip)
                        ctx.addLine(to: CGPoint(x: tip.x - head * cos(ang - .pi / 6), y: tip.y - head * sin(ang - .pi / 6)))
                        ctx.addLine(to: CGPoint(x: tip.x - head * cos(ang + .pi / 6), y: tip.y - head * sin(ang + .pi / 6)))
                        ctx.closePath(); ctx.setFillColor(color); ctx.fillPath()
                    }
                    drawHead(tip: a.end, tail: a.start)
                    if a.arrowStyle == .double { drawHead(tip: a.start, tail: a.end) }
                }
            case .rect:
                ctx.setStrokeColor(color); ctx.setLineWidth(lw)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: lw, cornerHeight: lw, transform: nil)); ctx.strokePath()
            case .ellipse:
                ctx.setStrokeColor(color); ctx.setLineWidth(lw); ctx.strokeEllipse(in: r)
            case .highlight:
                ctx.setFillColor(color.copy(alpha: 0.35) ?? color); ctx.fill(r)
            case .blur:
                ctx.saveGState(); ctx.clip(to: r)
                if let px = pixelated {
                    // Undo the flip for image drawing.
                    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(px, in: CGRect(x: 0, y: 0, width: w, height: h))
                } else {
                    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(r)
                }
                ctx.restoreGState()
            case .text:
                let font = NSFont.systemFont(ofSize: max(12, lw * 5), weight: .semibold)
                let str = NSAttributedString(string: a.text.isEmpty ? "Text" : a.text,
                                             attributes: [.font: font, .foregroundColor: NSColor(a.color)])
                let sz = str.size()
                let bg = CGRect(x: a.start.x - 4, y: a.start.y - 2, width: sz.width + 8, height: sz.height + 4)
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
                ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
                str.draw(at: a.start)
            case .number:
                let rad = max(12, lw * 3.5)
                let circle = CGRect(x: a.start.x - rad, y: a.start.y - rad, width: rad * 2, height: rad * 2)
                ctx.setFillColor(color); ctx.fillEllipse(in: circle)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(max(1.5, lw * 0.5)); ctx.strokeEllipse(in: circle)
                let str = NSAttributedString(string: "\(a.number)", attributes: [
                    .font: NSFont.systemFont(ofSize: rad * 1.1, weight: .bold), .foregroundColor: NSColor.white])
                let sz = str.size()
                str.draw(at: CGPoint(x: a.start.x - sz.width / 2, y: a.start.y - sz.height / 2))
            case .crop, .picker:
                break
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard var out = ctx.makeImage() else { return nil }
        if let crop, let c = out.cropping(to: crop.integral) { out = c }
        return out
    }
}

extension CGRect {
    func scaled(_ s: CGFloat) -> CGRect { CGRect(x: minX * s, y: minY * s, width: width * s, height: height * s) }
}

// MARK: - Editor view

struct ScreenshotEditorView: View {
    @ObservedObject var model: ScreenshotEditorModel
    var onClose: () -> Void

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let fit = fitSize(in: geo.size)
                ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                ScreenScaleReader { s in if abs(s - model.screenScale) > 0.01 { model.screenScale = s } }.frame(width: 0, height: 0)
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    DecoratedPreview(style: model.style, imageSize: fit) {
                    AnnotationCanvas(model: model)
                        .frame(width: fit.width, height: fit.height)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let p = imagePoint(v.location, fit: fit, in: geo.size)
                                if model.draft == nil && (model.tool != .crop || model.crop == nil || v.translation == .zero) {
                                    if v.translation == .zero { model.begin(at: p) } else { model.update(to: p) }
                                } else { model.update(to: p) }
                            }
                            .onEnded { _ in model.commit() })
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .onAppear { syncScale(fit, geo.size) }
                .onChange(of: geo.size) { _, _ in syncScale(fit, geo.size) }
                .onChange(of: model.zoom) { _, _ in syncScale(fit, geo.size) }
                .onChange(of: model.screenScale) { _, _ in syncScale(fit, geo.size) }
                }
            }
            if let m = model.message {
                Divider()
                Text(m).font(.system(size: 11)).foregroundStyle(.secondary).padding(6)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(item: $model.editingText) { _ in
            VStack(spacing: 12) {
                Text("Text").font(.headline)
                TextField("Type here", text: $model.textEntry).frame(width: 320)
                    .onSubmit { model.applyText() }
                HStack { Button("Cancel") { model.textEntry = ""; model.applyText() }
                         Button("Add") { model.applyText() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }.padding(20)
        }
    }

    private func fitSize(in area: CGSize) -> CGSize {
        let pad: CGFloat = 24
        let avail = CGSize(width: max(1, area.width - pad * 2), height: max(1, area.height - pad * 2))
        let scale = model.screenScale
        let fitF = min(avail.width / model.pixelSize.width, avail.height / model.pixelSize.height, 1)
        let f = model.zoom.map { $0 / scale } ?? fitF
        return CGSize(width: model.pixelSize.width * f, height: model.pixelSize.height * f)
    }

    private func syncScale(_ fit: CGSize, _ area: CGSize) {
        let scale = model.screenScale
        let pad: CGFloat = 24
        let avail = CGSize(width: max(1, area.width - pad * 2), height: max(1, area.height - pad * 2))
        fitFraction = min(avail.width / model.pixelSize.width, avail.height / model.pixelSize.height, 1)
        model.fitZoom = fitFraction * scale
        model.viewScale = fit.width / model.pixelSize.width
    }

    private var zoomPercent: Int {
        let scale = model.screenScale
        return Int(((model.zoom ?? fitFraction * scale) * 100).rounded())
    }
    @State private var fitFraction: CGFloat = 1

    private func imagePoint(_ p: CGPoint, fit: CGSize, in area: CGSize) -> CGPoint {
        let s = model.pixelSize.width / fit.width
        return CGPoint(x: max(0, min(model.pixelSize.width, p.x * s)), y: max(0, min(model.pixelSize.height, p.y * s)))
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // File actions
                Button { model.copyToClipboard() } label: { Image(systemName: "doc.on.doc") }.help("Copy (⇧⌘C)").onHover { model.hoverHint = $0 ? "Copy the finished image to the clipboard (⇧⌘C)" : nil }.keyboardShortcut("c", modifiers: [.command, .shift])
                Menu { Button("Save as New") { _ = model.save(overwrite: false) }
                       Button("Overwrite Original") { _ = model.save(overwrite: true) }.disabled(model.sourceURL == nil) }
                    label: { Image(systemName: "square.and.arrow.down") }.frame(width: 44).help("Save").onHover { model.hoverHint = $0 ? "Save — Save as New, or Overwrite Original" : nil }
                Button { PinnedScreenshots.shared.pin(model.render() ?? model.image) } label: { Image(systemName: "pin") }.help("Pin on screen").onHover { model.hoverHint = $0 ? "Pin a floating copy on screen, above other windows" : nil }
                Button { model.showStyle.toggle() } label: { Image(systemName: "paintpalette") }
                    .tint(model.style.isActive ? .accentColor : nil).help("Background and frame style").onHover { model.hoverHint = $0 ? "Style — gradient background, padding, corners, shadow, macOS window frame" : nil }
                    .popover(isPresented: $model.showStyle, arrowEdge: .bottom) { StylePopover(model: model) }
                Button { model.showExport = true } label: { Image(systemName: "arrow.down.doc") }.help("Export as PNG, JPEG, HEIC, WebP, TIFF or PDF").onHover { model.hoverHint = $0 ? "Export — choose PNG, JPEG, HEIC, WebP, TIFF or PDF and a compression level" : nil }
                    .popover(isPresented: $model.showExport, arrowEdge: .bottom) { ExportPopover(model: model) }
                ShareButton(model: model)
                Divider().frame(height: 18)
                // Tools
                ForEach(AnnotationKind.allCases) { kind in
                    Button { model.tool = kind } label: { Image(systemName: kind.symbol).frame(width: 20, height: 18) }
                        .buttonStyle(.bordered).tint(model.tool == kind ? .accentColor : nil)
                        .help("\(kind.hint) · key \(String(kind.key.character).uppercased())")
                        .onHover { model.hoverHint = $0 ? "\(kind.hint) · key \(String(kind.key.character).uppercased())" : nil }
                        .keyboardShortcut(kind.key, modifiers: [])
                }
                Divider().frame(height: 18)
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z", modifiers: [.command]).help("Undo").onHover { model.hoverHint = $0 ? "Undo (⌘Z)" : nil }
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo").onHover { model.hoverHint = $0 ? "Redo (⇧⌘Z)" : nil }
                Button("Copy Text") { model.copyText() }.help("OCR: recognise and copy all text").onHover { model.hoverHint = $0 ? "Copy Text — recognise every word in the image (OCR) and copy it" : nil }
                Spacer()
                // Readouts
                HStack(spacing: 14) {
                    if let hex = model.pickedHex {
                        HStack(spacing: 5) {
                            Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(hex).font(.system(size: 11, weight: .medium)).monospaced()
                                Text("Copied").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(model.pixelSize.width))×\(Int(model.pixelSize.height))px").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Text("Image size").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 2) {
                        Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }.keyboardShortcut("-", modifiers: [.command]).help("Zoom out (⌘−)").onHover { model.hoverHint = $0 ? "Zoom out (⌘−)" : nil }
                        Menu {
                            Button("Fit to window") { model.zoomFit() }.keyboardShortcut("0", modifiers: [.command])
                            Button("50%") { model.zoom = 0.5 }
                            Button("100%") { model.zoom = 1 }
                            Button("200%") { model.zoom = 2 }
                            Button("400%") { model.zoom = 4 }
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(zoomPercent)%").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                Text(model.zoom == nil ? "Fit" : "Zoom").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }.menuStyle(.borderlessButton).frame(width: 52)
                        Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }.keyboardShortcut("=", modifiers: [.command]).help("Zoom in (⌘+)").onHover { model.hoverHint = $0 ? "Zoom in (⌘+) · click the percentage for Fit / 100%" : nil }
                    }
                }
                if let b = model.busy { ProgressView().controlSize(.mini); Text(b).font(.system(size: 10)).foregroundStyle(.secondary) }
                Button("Done") { model.finish(then: onClose) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.busy != nil).help("Save, copy to clipboard, close (⏎)").onHover { model.hoverHint = $0 ? "Done — save, copy to clipboard and close (⏎)" : nil }
            }
            // Second row: style for the current tool.
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(palette, id: \.self) { c in
                        Circle().fill(c).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.primary.opacity(model.color == c ? 0.9 : 0.15), lineWidth: 1.5))
                            .onTapGesture { model.color = c }
                    }
                }
                Divider().frame(height: 16)
                Image(systemName: "lineweight").foregroundStyle(.secondary)
                Slider(value: $model.width, in: 1...14).frame(width: 110).help("Stroke width").onHover { model.hoverHint = $0 ? "Stroke width (also keys 1–9)" : nil }
                if model.tool == .arrow || model.tool == .line {
                    Divider().frame(height: 16)
                    Picker("", selection: $model.arrowStyle) {
                        ForEach(ArrowStyle.allCases) { st in Image(systemName: st.symbol).tag(st) }
                    }.pickerStyle(.segmented).frame(width: 120).help("Arrow style").onHover { model.hoverHint = $0 ? "Arrow style — single, double, or plain line" : nil }
                }
                Spacer()
                if model.preparingBlur { ProgressView().controlSize(.mini); Text("Preparing blur…").font(.system(size: 10)).foregroundStyle(.secondary) }
                Text(hint).font(.system(size: 10)).foregroundStyle(model.hoverHint == nil ? .tertiary : .secondary).lineLimit(1)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var hint: String {
        if let h = model.hoverHint { return h }
        return model.tool.hint + " · keys: " + AnnotationKind.allCases.map { String($0.key.character).uppercased() }.joined(separator: " ")
    }
}

/// Live decoration around the editing canvas: same geometry as Decorator.
struct DecoratedPreview<Content: View>: View {
    let style: FrameStyle
    let imageSize: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        if style.isActive, let stops = style.background.colors {
            let pad = imageSize.width * style.padding
            let bar = style.titleBarHeight(for: imageSize.width) * (imageSize.width / max(1, imageSize.width))
            let radius = min(imageSize.width, imageSize.height) * style.cornerRadius
            ZStack {
                LinearGradient(colors: [Color(cgColor: stops.0), Color(cgColor: stops.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    if style.macWindow {
                        ZStack {
                            Color(white: 0.91)
                            HStack(spacing: bar * 0.3) {
                                Circle().fill(Color(red: 0.99, green: 0.38, blue: 0.36))
                                Circle().fill(Color(red: 0.99, green: 0.74, blue: 0.18))
                                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.26))
                            }
                            .frame(height: bar * 0.42).padding(.leading, bar * 0.5).frame(maxWidth: .infinity, alignment: .leading)
                            if !style.title.isEmpty { Text(style.title).font(.system(size: bar * 0.42, weight: .medium)).foregroundStyle(Color(white: 0.25)) }
                        }
                        .frame(width: imageSize.width, height: bar)
                    }
                    content()
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(style.shadow ? 0.45 : 0), radius: imageSize.width * 0.03, y: imageSize.width * 0.012)
                .padding(pad)
            }
            .fixedSize()
        } else {
            content().shadow(radius: 8)
        }
    }
}

struct StylePopover: View {
    @ObservedObject var model: ScreenshotEditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(FrameStyle.Background.allCases) { bg in
                    Button { model.style.background = bg } label: {
                        ZStack {
                            if let c = bg.colors {
                                LinearGradient(colors: [Color(cgColor: c.0), Color(cgColor: c.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                Image(systemName: "slash.circle").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(model.style.background == bg ? Color.accentColor : .primary.opacity(0.15), lineWidth: 2))
                    }.buttonStyle(.plain).help(bg.label)
                }
            }
            Group {
                HStack { Text("Padding").frame(width: 70, alignment: .leading); Slider(value: $model.style.padding, in: 0.02...0.2) }
                HStack { Text("Corners").frame(width: 70, alignment: .leading); Slider(value: $model.style.cornerRadius, in: 0...0.06) }
                Toggle("Shadow", isOn: $model.style.shadow)
                Toggle("macOS window frame", isOn: $model.style.macWindow)
                if model.style.macWindow { TextField("Window title (optional)", text: $model.style.title) }
            }
            .disabled(!model.style.isActive)
            .font(.system(size: 12))
            Text("Applied to Copy, Save, Share and Export. Annotations stay inside the image.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(14).frame(width: 340)
    }
}

struct ExportPopover: View {
    @ObservedObject var model: ScreenshotEditorModel
    @State private var estimate: Int?
    @State private var estimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Picker("", selection: $model.exportFormat) {
                ForEach(ImageFormat.available) { f in Text(f.label).tag(f) }
            }.pickerStyle(.segmented).labelsHidden()
            if model.exportFormat.isLossy {
                HStack {
                    Text("Quality").frame(width: 60, alignment: .leading)
                    Slider(value: $model.exportQuality, in: 0.3...1.0)
                    Text("\(Int(model.exportQuality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }.font(.system(size: 12))
            }
            HStack {
                Text(estimating ? "Estimating…" : estimate.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Export…") { model.exportAs(model.exportFormat, quality: model.exportQuality); model.showExport = false }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            Text(model.exportFormat == .pdf ? "A single-page PDF at the image's pixel size." :
                 model.exportFormat.isLossy ? "Lower quality = smaller file. HEIC and WebP are roughly half the size of JPEG at the same quality." :
                 "Lossless.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(14).frame(width: 360)
        .task(id: "\(model.exportFormat.rawValue)-\(Int(model.exportQuality * 20))") {
            estimating = true
            estimate = await model.estimateSize(format: model.exportFormat, quality: model.exportQuality)
            estimating = false
        }
    }
}

/// Reports the backing scale of whichever screen the hosting window is on,
/// and keeps it current when the window moves between displays.
struct ScreenScaleReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak v] n in
            guard let v, let w = v.window, (n.object as? NSWindow) === w else { return }
            MainActor.assumeIsolated { onChange(w.backingScaleFactor) }
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { onChange(w.backingScaleFactor) } }
    }
}

/// Pasteboard helpers. PNG goes on eagerly (fast, small). TIFF is promised
/// through a data provider and only encoded if some app actually asks for it:
/// an uncompressed 31-megapixel TIFF is 93 MB, and almost nothing wants it.
enum Clipboard {
    static func encode(_ cg: CGImage) -> (tiff: Data?, png: Data?) {
        (nil, FastImage.pngData(cg))
    }

    @MainActor
    static func set(tiff: Data?, png: Data?, source: CGImage? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        if let png { item.setData(png, forType: .png) }
        if let tiff { item.setData(tiff, forType: .tiff) }
        else if let source {
            let provider = LazyTIFF(image: source)
            item.setDataProvider(provider, forTypes: [.tiff])
            providers.append(provider)
            if providers.count > 4 { providers.removeFirst() }
        }
        pb.writeObjects([item])
    }

    /// Keeps providers alive while their pasteboard entry can still be read.
    @MainActor private static var providers: [LazyTIFF] = []

    final class LazyTIFF: NSObject, NSPasteboardItemDataProvider {
        let image: CGImage
        init(image: CGImage) { self.image = image }
        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .tiff else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            if let tiff = rep.tiffRepresentation(using: .lzw, factor: 1) { item.setData(tiff, forType: .tiff) }
        }
    }
}

/// NSSharingServicePicker needs a real view to anchor to.
struct ShareButton: NSViewRepresentable {
    @ObservedObject var model: ScreenshotEditorModel
    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")!,
                         target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        b.bezelStyle = .rounded; b.controlSize = .small; b.toolTip = "Share"
        return b
    }
    func updateNSView(_ v: NSButton, context: Context) { context.coordinator.model = model }
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    @MainActor final class Coordinator: NSObject {
        var model: ScreenshotEditorModel
        init(model: ScreenshotEditorModel) { self.model = model }
        @objc func tap(_ sender: NSButton) { model.share(from: sender) }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt32(h, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension Annotation: Equatable { static func == (a: Annotation, b: Annotation) -> Bool { a.id == b.id } }

// MARK: - Editor window

@MainActor
final class ScreenshotEditorWindows {
    static let shared = ScreenshotEditorWindows()
    private var windows: [NSWindow] = []

    func open(image: NSImage, sourceURL: URL?, saved: Task<Bool, Never>? = nil) {
        let model = ScreenshotEditorModel(image: image, sourceURL: saved == nil ? sourceURL : nil)
        model.pendingSave = saved
        model.pendingURL = sourceURL
        if let saved, let sourceURL {
            Task { @MainActor in
                if await saved.value { model.sourceURL = sourceURL; model.message = "Saved \(sourceURL.lastPathComponent) · copied to clipboard" }
            }
        }
        var windowRef: NSWindow?
        let view = ScreenshotEditorView(model: model) { windowRef?.close() }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        windowRef = w
        w.title = sourceURL?.lastPathComponent ?? "Screenshot"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = target?.backingScaleFactor ?? 2
        model.screenScale = scale
        let f = min(0.8 * visible.width / (model.pixelSize.width / scale), 0.8 * visible.height / (model.pixelSize.height / scale), 1) / scale
        let size = NSSize(width: min(visible.width - 40, max(760, model.pixelSize.width * f + 48)),
                          height: min(visible.height - 40, max(520, model.pixelSize.height * f + 130)))
        w.setContentSize(size)
        w.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows.append(w)
    }
}

// MARK: - Pinned screenshots (always on top)

@MainActor
final class PinnedScreenshots {
    static let shared = PinnedScreenshots()
    private var windows: [NSWindow] = []

    func pin(_ image: NSImage) {
        let maxW: CGFloat = 480
        let f = min(1, maxW / max(1, image.size.width))
        let size = NSSize(width: image.size.width * f, height: image.size.height * f)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.frame = NSRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        let close = NSButton(title: "✕", target: self, action: #selector(closePinned(_:)))
        close.bezelStyle = .circular; close.frame = NSRect(x: size.width - 26, y: size.height - 26, width: 22, height: 22)
        view.addSubview(close)
        w.contentView = view
        w.center()
        w.orderFrontRegardless()
        windows.append(w)
    }

    @objc private func closePinned(_ sender: NSButton) {
        sender.window?.orderOut(nil)
        windows.removeAll { $0 == sender.window }
    }
}

// MARK: - Floating preview thumbnail after capture

@MainActor
final class ScreenshotPreview {
    static let shared = ScreenshotPreview()
    private var window: NSWindow?
    private var timer: Timer?

    func show(image: NSImage, url: URL) {
        dismiss()
        let maxW: CGFloat = 260
        let f = min(1, maxW / max(1, image.size.width))
        let size = NSSize(width: image.size.width * f, height: image.size.height * f)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(x: screen.maxX - size.width - 20, y: screen.minY + 20, width: size.width, height: size.height)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PreviewThumbView(image: image, url: url) { [weak self] in
            self?.dismiss()
            ScreenshotEditorWindows.shared.open(image: image, sourceURL: url)
        } onClose: { [weak self] in self?.dismiss() }
        w.contentView = NSHostingView(rootView: view)
        w.orderFrontRegardless()
        window = w
        let seconds = AppSettings.shared.previewSeconds
        if seconds > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    func dismiss() { timer?.invalidate(); timer = nil; window?.orderOut(nil); window = nil }
}

private struct PreviewThumbView: View {
    let image: NSImage
    let url: URL
    let onOpen: () -> Void
    let onClose: () -> Void
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7), lineWidth: 1.5))
                .onTapGesture { onOpen() }
                .onDrag { NSItemProvider(object: url as NSURL) }
                .help("Click to edit · drag to drop into another app")
            if hover {
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
                    .buttonStyle(.plain).foregroundStyle(.white).shadow(radius: 2).padding(4)
            }
        }
        .onHover { hover = $0 }
    }
}
