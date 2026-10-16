using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// Cursor path and clicks, sampled at 60 Hz to the same JSON sidecar format
/// the Mac app writes -- the contract that lets PolishEngine run unchanged.
///
/// GetCursorPos / GetAsyncKeyState need no permission on Windows. Like the Mac
/// version this deliberately polls instead of installing a low-level hook.
/// </summary>
public sealed class TelemetryRecorder : IDisposable
{
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
    private const int VK_LBUTTON = 0x01, VK_RBUTTON = 0x02;

    private sealed record Sample(double t, double x, double y, bool click);
    private readonly List<Sample> _samples = new();
    private readonly PeriodicTimer _timer = new(TimeSpan.FromMilliseconds(1000.0 / 60));
    private readonly Stopwatch _clock = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly int _originX, _originY, _pixelW, _pixelH;
    private readonly double _scale;
    private bool _lastDown;
    private TimeSpan _pausedTotal;
    private Stopwatch? _pause;
    private Task? _loop;

    /// <param name="originX">Left edge of the captured region in screen pixels.</param>
    /// <param name="scale">Captured pixels per screen pixel (1 unless DPI scaling applies).</param>
    public TelemetryRecorder(int originX, int originY, int pixelW, int pixelH, double scale = 1.0)
    {
        _originX = originX; _originY = originY; _pixelW = pixelW; _pixelH = pixelH; _scale = scale;
    }

    public void Start()
    {
        _clock.Start();
        _loop = Task.Run(async () =>
        {
            while (await _timer.WaitForNextTickAsync(_cts.Token))
            {
                if (_pause is not null) continue;
                GetCursorPos(out var p);
                bool down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0 || (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
                bool click = down && !_lastDown;  // leading edge only
                _lastDown = down;
                lock (_samples)
                {
                    _samples.Add(new Sample(
                        (_clock.Elapsed - _pausedTotal).TotalSeconds,
                        (p.X - _originX) * _scale,
                        (p.Y - _originY) * _scale,
                        click));
                }
            }
        });
    }

    public void Pause() { _pause ??= Stopwatch.StartNew(); }
    public void Resume() { if (_pause is { } p) { _pausedTotal += p.Elapsed; _pause = null; } }

    public int ClickCount { get { lock (_samples) return _samples.Count(s => s.click); } }

    public string? StopAndWrite(string videoPath)
    {
        _cts.Cancel();
        try { _loop?.Wait(500); } catch { }
        List<Sample> copy; lock (_samples) copy = _samples.ToList();
        if (copy.Count == 0) return null;

        var path = Path.ChangeExtension(videoPath, null) + ".telemetry.json";
        var sidecar = new
        {
            version = 1,
            recordingStartedAt = DateTime.UtcNow.ToString("o"),
            sampleRateHz = 60,
            displayPixelWidth = _pixelW,
            displayPixelHeight = _pixelH,
            samples = copy,
        };
        File.WriteAllText(path, JsonSerializer.Serialize(sidecar));
        return path;
    }

    public void Dispose() { _cts.Dispose(); _timer.Dispose(); }
}
