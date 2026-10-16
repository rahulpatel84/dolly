using PolishEngine;
using Xunit;

public class ZoomPlannerTests
{
    private static TelemetrySidecar Sidecar(IEnumerable<TelemetrySample> samples, int w = 1920, int h = 1080) =>
        new(1, 60, w, h, samples.ToList());

    private static IEnumerable<TelemetrySample> Still(double x, double y, double seconds, bool click = false) =>
        Enumerable.Range(0, (int)(seconds * 60)).Select(i => new TelemetrySample(i / 60.0, x, y, click && i == 10));

    [Fact]
    public void StationaryCursor_ZoomsInToMaxScale()
    {
        var plan = ZoomPlanner.Plan(Sidecar(Still(960, 540, 4)), 4);
        var (scale, _, _) = plan.StateAt(2.0);
        Assert.InRange(scale, 1.95, 2.0);
    }

    [Fact]
    public void WideRoaming_StaysAtFullView()
    {
        // Sweep the whole width within every window: spread exceeds "loose".
        var samples = Enumerable.Range(0, 240)
            .Select(i => new TelemetrySample(i / 60.0, (i % 30) * 64.0, 540, false));
        var plan = ZoomPlanner.Plan(Sidecar(samples), 4);
        var (scale, _, _) = plan.StateAt(2.0);
        Assert.InRange(scale, 1.0, 1.05);
    }

    [Fact]
    public void ZoomedView_NeverLeavesFrame()
    {
        // Cursor parked in the extreme top-left corner.
        var plan = ZoomPlanner.Plan(Sidecar(Still(5, 5, 4)), 4);
        foreach (var k in plan.Keyframes)
        {
            double halfW = plan.FrameWidth / k.Scale / 2;
            double halfH = plan.FrameHeight / k.Scale / 2;
            Assert.True(k.CenterX - halfW >= -1e-6, "view runs off the left edge");
            Assert.True(k.CenterY - halfH >= -1e-6, "view runs off the top edge");
            Assert.True(k.CenterX + halfW <= plan.FrameWidth + 1e-6);
            Assert.True(k.CenterY + halfH <= plan.FrameHeight + 1e-6);
        }
    }

    [Fact]
    public void Click_ForcesZoomEvenWhileRoaming()
    {
        var roaming = Enumerable.Range(0, 240)
            .Select(i => new TelemetrySample(i / 60.0, (i % 30) * 64.0, 540, i == 120)).ToList();
        var plan = ZoomPlanner.Plan(Sidecar(roaming), 4);
        var (atClick, _, _) = plan.StateAt(2.0);
        var (farAway, _, _) = plan.StateAt(0.3);
        Assert.True(atClick > farAway + 0.3, $"click should pull the camera in: {atClick} vs {farAway}");
    }

    [Fact]
    public void Smoothing_IsSymmetric_NoPhaseLag()
    {
        // Still for 2 s, then jump to the far side and stay still.
        var a = Still(300, 540, 2);
        var b = Enumerable.Range(0, 120).Select(i => new TelemetrySample(2 + i / 60.0, 1620, 540, false));
        var plan = ZoomPlanner.Plan(Sidecar(a.Concat(b)), 4);
        // At the jump the camera should be roughly half-way, not still at the start.
        var (_, cx, _) = plan.StateAt(2.0);
        Assert.InRange(cx, 700, 1300);
    }

    [Fact]
    public void Interpolation_IsContinuous()
    {
        var plan = ZoomPlanner.Plan(Sidecar(Still(960, 540, 4)), 4);
        double prev = plan.StateAt(0).Scale;
        for (double t = 0.01; t <= 4; t += 0.01)
        {
            double s = plan.StateAt(t).Scale;
            Assert.True(Math.Abs(s - prev) < 0.05, $"jump at t={t}: {prev} -> {s}");
            prev = s;
        }
    }

    [Fact]
    public void EmptyTelemetry_YieldsIdentity()
    {
        var plan = ZoomPlanner.Plan(Sidecar(Array.Empty<TelemetrySample>()), 4);
        var (scale, cx, cy) = plan.StateAt(1);
        Assert.Equal(1.0, scale);
        Assert.Equal(960, cx);
        Assert.Equal(540, cy);
    }

    [Fact]
    public void ParsesTheMacSidecarFormat()
    {
        const string json = """
        {"version":1,"sampleRateHz":60,"displayPixelWidth":1920,"displayPixelHeight":1080,
         "recordingStartedAt":"2026-10-13T11:11:08Z",
         "samples":[{"t":0.0167,"x":880.5,"y":53.2,"click":false},{"t":0.0333,"x":881,"y":54,"click":true}]}
        """;
        var side = TelemetrySidecar.Parse(json);
        Assert.Equal(2, side.Samples.Count);
        Assert.True(side.Samples[1].Click);
        Assert.Equal(1920, side.DisplayPixelWidth);
    }
}
