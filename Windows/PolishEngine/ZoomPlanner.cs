namespace PolishEngine;

/// <summary>A zoom state at a point in time. Centre in top-left-origin frame pixels.</summary>
public readonly record struct ZoomKeyframe(double T, double Scale, double CenterX, double CenterY);

public readonly record struct ClickEvent(double T, double X, double Y);

/// <summary>
/// A smooth camera path over a recording. Port of ZoomPlan in ZoomPlanner.swift.
/// Keyframes are already heavily smoothed, so linear interpolation is enough
/// and avoids the overshoot a spline would add — overshoot reads as the camera "bouncing".
/// </summary>
public sealed class ZoomPlan
{
    public IReadOnlyList<ZoomKeyframe> Keyframes { get; }
    public IReadOnlyList<ClickEvent> Clicks { get; }
    public double FrameWidth { get; }
    public double FrameHeight { get; }
    private readonly IReadOnlyList<TelemetrySample> _cursor;

    internal ZoomPlan(
        IReadOnlyList<ZoomKeyframe> keyframes, IReadOnlyList<ClickEvent> clicks,
        double frameWidth, double frameHeight, IReadOnlyList<TelemetrySample> cursor)
    {
        Keyframes = keyframes;
        Clicks = clicks;
        FrameWidth = frameWidth;
        FrameHeight = frameHeight;
        _cursor = cursor;
    }

    public (double Scale, double CenterX, double CenterY) StateAt(double time)
    {
        if (Keyframes.Count == 0) return (1.0, FrameWidth / 2, FrameHeight / 2);
        var first = Keyframes[0];
        if (time <= first.T) return (first.Scale, first.CenterX, first.CenterY);
        var last = Keyframes[^1];
        if (time >= last.T) return (last.Scale, last.CenterX, last.CenterY);

        int lo = 0, hi = Keyframes.Count - 1;
        while (hi - lo > 1)
        {
            int mid = (lo + hi) / 2;
            if (Keyframes[mid].T <= time) lo = mid; else hi = mid;
        }
        var a = Keyframes[lo];
        var b = Keyframes[hi];
        double span = b.T - a.T;
        double f = span > 0 ? (time - a.T) / span : 0;
        return (
            a.Scale + (b.Scale - a.Scale) * f,
            a.CenterX + (b.CenterX - a.CenterX) * f,
            a.CenterY + (b.CenterY - a.CenterY) * f);
    }

    /// <summary>Raw (unsmoothed) cursor position, for the pointer highlight.</summary>
    public (double X, double Y)? CursorAt(double time)
    {
        if (_cursor.Count == 0) return null;
        if (time <= _cursor[0].T) return (_cursor[0].X, _cursor[0].Y);
        int hi = _cursor.Count - 1;
        if (time >= _cursor[hi].T) return (_cursor[hi].X, _cursor[hi].Y);
        int lo = 0;
        while (hi - lo > 1)
        {
            int mid = (lo + hi) / 2;
            if (_cursor[mid].T <= time) lo = mid; else hi = mid;
        }
        var a = _cursor[lo];
        var b = _cursor[hi];
        double span = b.T - a.T;
        double f = span > 0 ? (time - a.T) / span : 0;
        return (a.X + (b.X - a.X) * f, a.Y + (b.Y - a.Y) * f);
    }
}

/// <summary>
/// Turns raw cursor telemetry into a smooth camera path.
///
/// This is the product. Capture is a commodity; deciding where to look and when
/// is what makes a raw screencast watchable. It is arithmetic over the sidecar —
/// no OS APIs — which is why this one file is shared between macOS and Windows.
/// </summary>
public static class ZoomPlanner
{
    public sealed record Settings
    {
        /// <summary>Window over which cursor activity is assessed.</summary>
        public double WindowSeconds { get; init; } = 0.5;
        /// <summary>Zoom applied when the cursor is working in a tight area.</summary>
        public double MaxScale { get; init; } = 2.0;
        /// <summary>Zoom applied for moderate activity.</summary>
        public double MidScale { get; init; } = 1.4;
        /// <summary>Smoothing half-life. Larger is calmer but slower to follow.</summary>
        public double SmoothingSeconds { get; init; } = 1.4;
        /// <summary>A click forces attention regardless of movement.</summary>
        public double ClickHoldSeconds { get; init; } = 1.0;

        public static Settings Default { get; } = new();
    }

    public static ZoomPlan Plan(TelemetrySidecar sidecar, double duration, Settings? settings = null)
    {
        settings ??= Settings.Default;
        double frameW = sidecar.DisplayPixelWidth;
        double frameH = sidecar.DisplayPixelHeight;
        var samples = sidecar.Samples;

        if (samples.Count == 0 || frameW <= 0 || frameH <= 0)
            return new ZoomPlan(Array.Empty<ZoomKeyframe>(), Array.Empty<ClickEvent>(), frameW, frameH, samples);

        var clicks = samples.Where(s => s.Click).Select(s => new ClickEvent(s.T, s.X, s.Y)).ToList();

        // 1. Bucket the timeline into fixed windows.
        double end = Math.Max(duration, samples[^1].T);
        int windowCount = Math.Max(1, (int)Math.Ceiling(end / settings.WindowSeconds));
        var targets = new List<(double T, double Scale, double Cx, double Cy)>(windowCount);
        double lastCx = frameW / 2, lastCy = frameH / 2;

        for (int i = 0; i < windowCount; i++)
        {
            double start = i * settings.WindowSeconds;
            double stop = start + settings.WindowSeconds;
            double mid = start + settings.WindowSeconds / 2;
            var inWindow = samples.Where(s => s.T >= start && s.T < stop).ToList();

            if (inWindow.Count == 0)
            {
                // No data: hold the previous position, pull back to full view.
                targets.Add((mid, 1.0, lastCx, lastCy));
                continue;
            }

            double cx = inWindow.Average(s => s.X);
            double cy = inWindow.Average(s => s.Y);
            lastCx = cx; lastCy = cy;

            // Spread: how far the cursor roamed from its own centre.
            double spread = inWindow.Max(s => Math.Sqrt((s.X - cx) * (s.X - cx) + (s.Y - cy) * (s.Y - cy)));
            double tight = frameW * 0.12;
            double loose = frameW * 0.28;

            // A click nearby forces the close view: the strongest available
            // signal that something important just happened.
            bool clickNear = clicks.Any(c =>
                c.T >= start - settings.ClickHoldSeconds && c.T < stop + settings.ClickHoldSeconds);

            double scale = clickNear || spread < tight ? settings.MaxScale
                         : spread < loose ? settings.MidScale
                         : 1.0;
            targets.Add((mid, scale, cx, cy));
        }

        // 2. Smooth forwards then backwards. The second pass cancels the phase
        //    lag of the first, so the camera neither trails nor anticipates.
        double alpha = 1 - Math.Exp(-settings.WindowSeconds / Math.Max(0.05, settings.SmoothingSeconds));
        var scales = targets.Select(t => t.Scale).ToArray();
        var xs = targets.Select(t => t.Cx).ToArray();
        var ys = targets.Select(t => t.Cy).ToArray();

        for (int pass = 0; pass < 2; pass++)
        {
            var order = pass == 0 ? Enumerable.Range(0, scales.Length) : Enumerable.Range(0, scales.Length).Reverse();
            double sAcc = double.NaN, xAcc = 0, yAcc = 0;
            foreach (int i in order)
            {
                if (double.IsNaN(sAcc)) { sAcc = scales[i]; xAcc = xs[i]; yAcc = ys[i]; }
                sAcc += alpha * (scales[i] - sAcc);
                xAcc += alpha * (xs[i] - xAcc);
                yAcc += alpha * (ys[i] - yAcc);
                scales[i] = sAcc; xs[i] = xAcc; ys[i] = yAcc;
            }
        }

        // 3. Clamp so the zoomed view never runs off the edge of the frame.
        var keyframes = new List<ZoomKeyframe>(targets.Count);
        for (int i = 0; i < targets.Count; i++)
        {
            double scale = Math.Max(1.0, scales[i]);
            double halfW = frameW / scale / 2;
            double halfH = frameH / scale / 2;
            double cx = Math.Clamp(xs[i], halfW, frameW - halfW);
            double cy = Math.Clamp(ys[i], halfH, frameH - halfH);
            keyframes.Add(new ZoomKeyframe(targets[i].T, scale, cx, cy));
        }

        return new ZoomPlan(keyframes, clicks, frameW, frameH, samples);
    }
}
