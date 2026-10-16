import CoreGraphics
import Foundation

/// The telemetry sidecar written during capture.
struct TelemetrySidecar: Decodable {
    struct Sample: Decodable {
        let t: Double
        let x: Double
        let y: Double
        let click: Bool
    }
    let version: Int
    let sampleRateHz: Int
    let displayPixelWidth: Int
    let displayPixelHeight: Int
    let samples: [Sample]

    static func load(from url: URL) throws -> TelemetrySidecar {
        try JSONDecoder().decode(TelemetrySidecar.self, from: Data(contentsOf: url))
    }
}

/// A zoom state at a point in time. Centre is in top-left-origin frame pixels,
/// the same space the sidecar uses.
struct ZoomKeyframe {
    let t: Double
    let scale: Double
    let center: CGPoint
}

struct ClickEvent {
    let t: Double
    let point: CGPoint
}

/// Turns raw cursor telemetry into a smooth camera path.
///
/// This is the product. Capture is a commodity; deciding *where to look and
/// when* is the part that makes a raw screencast watchable. It is also
/// entirely platform-independent arithmetic -- no OS APIs -- which is why it
/// is the piece worth writing once and reusing on Windows.
struct ZoomPlan {
    let keyframes: [ZoomKeyframe]
    let clicks: [ClickEvent]
    let frameSize: CGSize
    /// Raw cursor positions, kept for the pointer highlight. The zoom uses the
    /// smoothed path; the halo must sit on the actual pointer or it looks
    /// detached from it.
    let cursor: [(t: Double, x: Double, y: Double)]

    /// Nearest raw cursor sample, or nil when telemetry does not cover `time`.
    func sample(at time: Double) -> (x: Double, y: Double)? {
        guard !cursor.isEmpty else { return nil }
        var lo = 0
        var hi = cursor.count - 1
        if time <= cursor[0].t { return (cursor[0].x, cursor[0].y) }
        if time >= cursor[hi].t { return (cursor[hi].x, cursor[hi].y) }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cursor[mid].t <= time { lo = mid } else { hi = mid }
        }
        let a = cursor[lo]
        let b = cursor[hi]
        let span = b.t - a.t
        let f = span > 0 ? (time - a.t) / span : 0
        return (a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
    }

    /// Linear interpolation between keyframes. The keyframes are already
    /// heavily smoothed, so linear is enough and avoids the overshoot a spline
    /// would introduce -- overshoot reads as the camera "bouncing".
    func state(at time: Double) -> (scale: Double, center: CGPoint) {
        guard let first = keyframes.first else {
            return (1.0, CGPoint(x: frameSize.width / 2, y: frameSize.height / 2))
        }
        if time <= first.t { return (first.scale, first.center) }
        guard let last = keyframes.last else { return (first.scale, first.center) }
        if time >= last.t { return (last.scale, last.center) }

        var lo = 0
        var hi = keyframes.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].t <= time { lo = mid } else { hi = mid }
        }
        let a = keyframes[lo]
        let b = keyframes[hi]
        let span = b.t - a.t
        let f = span > 0 ? (time - a.t) / span : 0
        return (
            a.scale + (b.scale - a.scale) * f,
            CGPoint(
                x: a.center.x + (b.center.x - a.center.x) * f,
                y: a.center.y + (b.center.y - a.center.y) * f)
        )
    }
}

enum ZoomPlanner {

    struct Settings {
        /// Window over which cursor activity is assessed.
        var windowSeconds: Double = 0.5
        /// Zoom applied when the cursor is working in a tight area.
        var maxScale: Double = 2.0
        /// Zoom applied for moderate activity.
        var midScale: Double = 1.4
        /// Smoothing half-life. Larger is calmer but slower to follow.
        var smoothingSeconds: Double = 1.4
        /// A click forces attention regardless of movement.
        var clickHoldSeconds: Double = 1.0

        static let `default` = Settings()
    }

    static func plan(
        from sidecar: TelemetrySidecar, duration: Double, settings: Settings = .default
    ) -> ZoomPlan {
        let frameSize = CGSize(
            width: Double(sidecar.displayPixelWidth), height: Double(sidecar.displayPixelHeight))
        let samples = sidecar.samples
        guard !samples.isEmpty, frameSize.width > 0, frameSize.height > 0 else {
            return ZoomPlan(keyframes: [], clicks: [], frameSize: frameSize, cursor: [])
        }

        let clicks = samples.filter(\.click).map {
            ClickEvent(t: $0.t, point: CGPoint(x: $0.x, y: $0.y))
        }

        // 1. Bucket the timeline into fixed windows.
        let end = max(duration, samples.last?.t ?? duration)
        let windowCount = max(1, Int(ceil(end / settings.windowSeconds)))
        var targets: [(t: Double, scale: Double, center: CGPoint)] = []
        targets.reserveCapacity(windowCount)

        var lastCenter = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)

        for i in 0..<windowCount {
            let start = Double(i) * settings.windowSeconds
            let stop = start + settings.windowSeconds
            let inWindow = samples.filter { $0.t >= start && $0.t < stop }

            let mid = start + settings.windowSeconds / 2
            guard !inWindow.isEmpty else {
                // No data: hold the previous position, pull back to full view.
                targets.append((mid, 1.0, lastCenter))
                continue
            }

            let cx = inWindow.map(\.x).reduce(0, +) / Double(inWindow.count)
            let cy = inWindow.map(\.y).reduce(0, +) / Double(inWindow.count)
            let centroid = CGPoint(x: cx, y: cy)
            lastCenter = centroid

            // Spread: how far the cursor roamed from its own centre.
            let spread = inWindow.map { hypot($0.x - cx, $0.y - cy) }.max() ?? 0
            let tight = frameSize.width * 0.12
            let loose = frameSize.width * 0.28

            // A click nearby forces the close view: it is the strongest
            // available signal that something important just happened.
            let clickNear = clicks.contains {
                $0.t >= start - settings.clickHoldSeconds && $0.t < stop + settings.clickHoldSeconds
            }

            let scale: Double
            if clickNear || spread < tight {
                scale = settings.maxScale
            } else if spread < loose {
                scale = settings.midScale
            } else {
                scale = 1.0
            }
            targets.append((mid, scale, centroid))
        }

        // 2. Smooth forwards then backwards. The second pass cancels the phase
        //    lag the first introduces, so the camera neither trails the cursor
        //    nor anticipates it.
        let alpha = 1 - exp(-settings.windowSeconds / max(0.05, settings.smoothingSeconds))
        var scales = targets.map(\.scale)
        var xs = targets.map { $0.center.x }
        var ys = targets.map { $0.center.y }

        for pass in 0..<2 {
            let order = pass == 0 ? Array(scales.indices) : Array(scales.indices.reversed())
            var sAcc = scales[order[0]]
            var xAcc = xs[order[0]]
            var yAcc = ys[order[0]]
            for i in order {
                sAcc += alpha * (scales[i] - sAcc)
                xAcc += alpha * (xs[i] - xAcc)
                yAcc += alpha * (ys[i] - yAcc)
                scales[i] = sAcc
                xs[i] = xAcc
                ys[i] = yAcc
            }
        }

        // 3. Clamp so the zoomed view never runs off the edge of the frame.
        var keyframes: [ZoomKeyframe] = []
        keyframes.reserveCapacity(targets.count)
        for i in targets.indices {
            let scale = max(1.0, scales[i])
            let halfW = frameSize.width / scale / 2
            let halfH = frameSize.height / scale / 2
            let cx = min(max(xs[i], halfW), frameSize.width - halfW)
            let cy = min(max(ys[i], halfH), frameSize.height - halfH)
            keyframes.append(
                ZoomKeyframe(t: targets[i].t, scale: scale, center: CGPoint(x: cx, y: cy)))
        }

        return ZoomPlan(
            keyframes: keyframes, clicks: clicks, frameSize: frameSize,
            cursor: samples.map { (t: $0.t, x: $0.x, y: $0.y) })
    }
}
