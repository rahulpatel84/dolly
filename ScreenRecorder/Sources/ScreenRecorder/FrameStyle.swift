import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decoration around a screenshot: background, padding, corners, shadow, and
/// an optional macOS-style window frame. Applied in the editor preview and
/// identically in the export.
struct FrameStyle: Equatable {
    enum Background: String, CaseIterable, Identifiable {
        case none, midnight, sunset, ocean, mint, graphite, paper
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// Two gradient stops, top-left → bottom-right.
        var colors: (CGColor, CGColor)? {
            switch self {
            case .none: return nil
            case .midnight: return (CGColor(red: 0.16, green: 0.20, blue: 0.42, alpha: 1), CGColor(red: 0.42, green: 0.16, blue: 0.38, alpha: 1))
            case .sunset: return (CGColor(red: 0.98, green: 0.45, blue: 0.30, alpha: 1), CGColor(red: 0.60, green: 0.20, blue: 0.55, alpha: 1))
            case .ocean: return (CGColor(red: 0.12, green: 0.55, blue: 0.85, alpha: 1), CGColor(red: 0.10, green: 0.80, blue: 0.70, alpha: 1))
            case .mint: return (CGColor(red: 0.75, green: 0.95, blue: 0.85, alpha: 1), CGColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1))
            case .graphite: return (CGColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1), CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
            case .paper: return (CGColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1), CGColor(red: 0.88, green: 0.87, blue: 0.84, alpha: 1))
            }
        }
    }

    var background: Background = .none
    /// Fraction of the image width used as margin on each side.
    var padding: CGFloat = 0.06
    /// Corner radius as a fraction of the shorter image side.
    var cornerRadius: CGFloat = 0.025
    var shadow = true
    /// Draw a macOS title bar with traffic lights above the image.
    var macWindow = false
    var title = ""

    var isActive: Bool { background != .none }

    /// Height of the title bar in image pixels.
    func titleBarHeight(for imageWidth: CGFloat) -> CGFloat { macWindow ? max(28, imageWidth * 0.028) : 0 }

    /// Output canvas size for an image of `size`.
    func canvasSize(for size: CGSize) -> CGSize {
        guard isActive else { return size }
        let pad = size.width * padding
        return CGSize(width: size.width + pad * 2, height: size.height + pad * 2 + titleBarHeight(for: size.width))
    }

    /// Where the image lands inside the canvas (top-left origin).
    func imageOrigin(for size: CGSize) -> CGPoint {
        guard isActive else { return .zero }
        let pad = size.width * padding
        return CGPoint(x: pad, y: pad + titleBarHeight(for: size.width))
    }
}

/// Draws the decoration around an already-annotated image, in CoreGraphics.
enum Decorator {
    static func decorate(_ image: CGImage, style: FrameStyle) -> CGImage? {
        guard style.isActive, let stops = style.background.colors else { return image }
        let size = CGSize(width: image.width, height: image.height)
        let canvas = style.canvasSize(for: size)
        let origin = style.imageOrigin(for: size)
        let bar = style.titleBarHeight(for: size.width)
        guard let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
        // Flip to top-left origin.
        ctx.translateBy(x: 0, y: canvas.height); ctx.scaleBy(x: 1, y: -1)

        // Background gradient.
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [stops.0, stops.1] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: canvas.width, y: canvas.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        // The card: image area plus title bar, rounded.
        let card = CGRect(x: origin.x, y: origin.y - bar, width: size.width, height: size.height + bar)
        let radius = min(size.width, size.height) * style.cornerRadius
        let path = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if style.shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: size.width * 0.012), blur: size.width * 0.03,
                          color: CGColor(gray: 0, alpha: 0.45))
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.addPath(path); ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        if style.macWindow {
            // Title bar: a light grey chrome with traffic lights.
            ctx.setFillColor(CGColor(red: 0.91, green: 0.91, blue: 0.92, alpha: 1))
            ctx.fill(CGRect(x: card.minX, y: card.minY, width: card.width, height: bar))
            let r = bar * 0.21, cy = card.minY + bar / 2
            for (i, c) in [(0.99, 0.38, 0.36), (0.99, 0.74, 0.18), (0.16, 0.78, 0.26)].enumerated() {
                ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
                let cx = card.minX + bar * 0.6 + CGFloat(i) * r * 2.9
                ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }
            if !style.title.isEmpty {
                let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
                let str = NSAttributedString(string: style.title, attributes: [
                    .font: NSFont.systemFont(ofSize: bar * 0.42, weight: .medium),
                    .foregroundColor: NSColor(white: 0.25, alpha: 1)])
                let sz = str.size()
                str.draw(at: CGPoint(x: card.midX - sz.width / 2, y: cy - sz.height / 2))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // The image (un-flip for drawing).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas.height); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: origin.x, y: canvas.height - origin.y - size.height, width: size.width, height: size.height))
        ctx.restoreGState()
        ctx.restoreGState()
        return ctx.makeImage()
    }
}

/// Export formats for screenshots, with size estimation for the lossy ones.
enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic, webp, tiff, pdf
    var id: String { rawValue }
    var label: String {
        switch self {
        case .png: return "PNG"; case .jpeg: return "JPEG"; case .heic: return "HEIC"
        case .webp: return "WebP"; case .tiff: return "TIFF"; case .pdf: return "PDF"
        }
    }
    var ext: String { rawValue == "jpeg" ? "jpg" : rawValue }
    var isLossy: Bool { self == .jpeg || self == .heic || self == .webp }
    var utType: UTType {
        switch self {
        case .png: return .png; case .jpeg: return .jpeg; case .heic: return .heic
        case .webp: return .webP; case .tiff: return .tiff; case .pdf: return .pdf
        }
    }
    /// Formats ImageIO can actually write on this Mac.
    static var available: [ImageFormat] {
        let ids = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return allCases.filter { $0 == .pdf || ids.contains($0.utType.identifier) }
    }
}

enum ImageEncoder {
    /// Encoded bytes. `quality` 0…1 applies to lossy formats.
    static func encode(_ cg: CGImage, format: ImageFormat, quality: Double) -> Data? {
        switch format {
        case .pdf:
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
            ctx.beginPDFPage(nil)
            ctx.draw(cg, in: box)
            ctx.endPDFPage(); ctx.closePDF()
            return data as Data
        case .png:
            return FastImage.pngData(cg)
        default:
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else { return nil }
            let props: [CFString: Any] = format.isLossy ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
            CGImageDestinationAddImage(dest, cg, props as CFDictionary)
            return CGImageDestinationFinalize(dest) ? data as Data : nil
        }
    }
}
