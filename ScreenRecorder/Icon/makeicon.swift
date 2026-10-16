import AppKit
import CoreGraphics
import Foundation
import ImageIO

// Draws the app icon at any size and writes a PNG.
// Dark rounded square, a screen outline, and a red record dot.
func drawIcon(size: CGFloat) -> CGImage? {
    let w = Int(size), h = Int(size)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    let inset = size * 0.085
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let small = size <= 64
    let navy = CGColor(red: 0.11, green: 0.13, blue: 0.22, alpha: 1)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let red = CGColor(red: 0.95, green: 0.22, blue: 0.24, alpha: 1)

    // Flat navy ground.
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(navy); ctx.fillPath()

    // The rail: a white track the camera rides along, slightly below centre.
    let railY = rect.minY + rect.height * (small ? 0.36 : 0.30)
    let railH = rect.height * (small ? 0.075 : 0.05)
    let railX0 = rect.minX + rect.width * 0.12, railX1 = rect.maxX - rect.width * 0.12
    ctx.setFillColor(white)
    ctx.addPath(CGPath(roundedRect: CGRect(x: railX0, y: railY - railH / 2, width: railX1 - railX0, height: railH),
                       cornerWidth: railH / 2, cornerHeight: railH / 2, transform: nil))
    ctx.fillPath()
    if !small {
        // Three ticks under the rail: enough to say "track", not a fence.
        for i in 0..<3 {
            let x = railX0 + (railX1 - railX0) * (CGFloat(i) + 0.5) / 3
            ctx.addPath(CGPath(roundedRect: CGRect(x: x - railH * 0.35, y: railY - railH * 2.0, width: railH * 0.7, height: railH * 1.3),
                               cornerWidth: railH * 0.3, cornerHeight: railH * 0.3, transform: nil)); ctx.fillPath()
        }
    }

    // The camera: a white ring with a red core, sitting on the rail.
    let cx = rect.minX + rect.width * (small ? 0.40 : 0.38)
    let r = rect.width * (small ? 0.21 : 0.22)
    let cy = railY + r + railH * 0.3
    let ringW = rect.width * (small ? 0.065 : 0.06)
    ctx.setStrokeColor(white); ctx.setLineWidth(ringW)
    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    let core = r - ringW * (small ? 1.5 : 1.8)
    ctx.setFillColor(red)
    ctx.fillEllipse(in: CGRect(x: cx - core, y: cy - core, width: core * 2, height: core * 2))

    // The cursor it follows, ahead and slightly above, with a dotted trail.
    if !small {
        let ax = rect.maxX - rect.width * 0.24, ay = cy + r * 1.05
        let a = rect.width * 0.21
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: ax, y: ay))
        arrow.addLine(to: CGPoint(x: ax, y: ay - a))
        arrow.addLine(to: CGPoint(x: ax + a * 0.27, y: ay - a * 0.70))
        arrow.addLine(to: CGPoint(x: ax + a * 0.47, y: ay - a * 1.05))
        arrow.addLine(to: CGPoint(x: ax + a * 0.63, y: ay - a * 0.96))
        arrow.addLine(to: CGPoint(x: ax + a * 0.44, y: ay - a * 0.62))
        arrow.addLine(to: CGPoint(x: ax + a * 0.76, y: ay - a * 0.62))
        arrow.closeSubpath()
        ctx.setFillColor(white); ctx.setStrokeColor(navy); ctx.setLineWidth(size * 0.012)
        ctx.addPath(arrow); ctx.drawPath(using: .fillStroke)
        // Trail: three dots from the camera toward the cursor.
        let dots = 3
        for i in 1...dots {
            let t = CGFloat(i) / CGFloat(dots + 1)
            let x = cx + r + (ax - (cx + r)) * t, y = cy + (ay - a * 0.5 - cy) * t
            let dr = rect.width * 0.018
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
            ctx.fillEllipse(in: CGRect(x: x - dr, y: y - dr, width: dr * 2, height: dr * 2))
        }
    }
    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// Menu-bar glyph: a template image (black + alpha), 18pt. macOS recolours
/// it to match the menu bar, so it must carry no colour of its own.
func drawMenuGlyph(scale: CGFloat) -> CGImage? {
    let pt: CGFloat = 18
    let px = Int(pt * scale)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale); ctx.setShouldAntialias(true)
    let ink = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ctx.setFillColor(ink)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: 3.2, width: 14, height: 1.6), cornerWidth: 0.8, cornerHeight: 0.8, transform: nil)); ctx.fillPath()
    ctx.setStrokeColor(ink); ctx.setLineWidth(1.6)
    ctx.strokeEllipse(in: CGRect(x: 3.2, y: 5.6, width: 9.6, height: 9.6))
    ctx.fillEllipse(in: CGRect(x: 5.9, y: 8.3, width: 4.2, height: 4.2))
    return ctx.makeImage()
}

if let g1 = drawMenuGlyph(scale: 1) { write(g1, to: "MenuBarIcon.png"); print("  MenuBarIcon.png (18px, template)") }
if let g2 = drawMenuGlyph(scale: 2) { write(g2, to: "MenuBarIcon@2x.png"); print("  MenuBarIcon@2x.png (36px, template)") }

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let dir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, size) in sizes {
    if let img = drawIcon(size: size) {
        write(img, to: "\(dir)/\(name).png")
        print("  \(name).png (\(Int(size))px)")
    }
}
print("done")
