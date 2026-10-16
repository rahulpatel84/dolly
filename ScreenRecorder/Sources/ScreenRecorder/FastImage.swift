import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image operations that are on the user's critical path, done with
/// Accelerate (vImage) instead of CoreGraphics drawing. On a 31-megapixel
/// capture that is the difference between ~2 s and ~100 ms.
enum FastImage {

    private static var format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        version: 0, decode: nil, renderingIntent: .defaultIntent)

    /// High-quality Lanczos downscale. Returns the input when already small enough.
    static func downscale(_ cg: CGImage, maxWidth: Int) -> CGImage? {
        guard cg.width > maxWidth else { return cg }
        let w = maxWidth
        let h = Int(Double(cg.height) * Double(maxWidth) / Double(cg.width))
        var src = vImage_Buffer()
        var fmt = format
        fmt.colorSpace = Unmanaged.passUnretained(cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
        guard vImageBuffer_InitWithCGImage(&src, &fmt, nil, cg, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        defer { free(src.data) }
        var dst = vImage_Buffer()
        guard vImageBuffer_Init(&dst, vImagePixelCount(h), vImagePixelCount(w), 32, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
        defer { free(dst.data) }
        guard vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return nil }
        var err = vImage_Error()
        let out = vImageCreateCGImageFromBuffer(&dst, &fmt, nil, nil, vImage_Flags(kvImageNoFlags), &err)
        return err == kvImageNoError ? out?.takeRetainedValue() : nil
    }

    /// PNG with filtering disabled: ~2× faster to encode, slightly larger file.
    /// Screenshots are mostly flat colour, where filters buy little.
    static func pngData(_ cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: IMAGEIO_PNG_NO_FILTERS]]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func writePNG(_ cg: CGImage, to url: URL) -> Bool {
        guard let d = pngData(cg) else { return false }
        return (try? d.write(to: url, options: .atomic)) != nil
    }
}
