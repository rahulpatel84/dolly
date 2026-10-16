using Windows.Graphics.Capture;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// Orchestrates one recording: capture + writer + audio + telemetry.
/// The Windows counterpart of CaptureEngine.swift.
/// </summary>
public sealed class CaptureSession : IDisposable
{
    public sealed record Result(string VideoPath, string? TelemetryPath, TimeSpan Duration, int FramesWritten, int FramesDropped, int Clicks);

    private readonly ScreenCapture _capture;
    private readonly RecordingWriter _writer;
    private readonly AudioCapture _audio;
    private readonly TelemetryRecorder _telemetry;
    private readonly string _rawPath, _finalPath;
    private readonly DateTime _started = DateTime.Now;
    private bool _paused;

    public bool IsPaused => _paused;

    public static string RecordingsDirectory()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "Screen Recordings");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public CaptureSession(GraphicsCaptureItem item, int originX, int originY, bool includeMicrophone, uint fps = 60)
    {
        var (d3d, ctx, device) = Direct3DInterop.CreateDevice();
        _capture = new ScreenCapture(device, item);
        var size = _capture.Size;

        // Encoders reject odd dimensions.
        int w = size.Width & ~1, h = size.Height & ~1;
        var stem = Path.Combine(RecordingsDirectory(), $"Recording {DateTime.Now:yyyy-MM-dd 'at' HH.mm.ss}");
        _rawPath = stem + ".video.mp4";
        _finalPath = stem + ".mp4";

        _writer = new RecordingWriter(_rawPath, w, h, fps, d3d, ctx);
        _audio = new AudioCapture(_finalPath, includeMicrophone);
        _telemetry = new TelemetryRecorder(originX, originY, w, h);
        _capture.FrameArrived += f => { if (!_paused) _writer.Append(f); };
    }

    public async Task StartAsync()
    {
        await _writer.StartAsync();
        _audio.Start();
        _telemetry.Start();
        _capture.Start();
    }

    public void Pause() { _paused = true; _telemetry.Pause(); }
    public void Resume() { _paused = false; _telemetry.Resume(); }

    public async Task<Result> StopAsync()
    {
        if (_paused) Resume();
        _capture.Dispose();
        _audio.Stop();
        await _writer.FinishAsync();
        var telemetry = _telemetry.StopAndWrite(_finalPath);

        await Muxer.MuxAsync(_rawPath, _audio.SystemPath, _audio.MicPath, _finalPath);
        File.Delete(_rawPath);
        File.Delete(_audio.SystemPath);
        if (_audio.MicPath is not null) File.Delete(_audio.MicPath);

        return new Result(_finalPath, telemetry, DateTime.Now - _started,
            _writer.FramesWritten, _writer.FramesDropped, _telemetry.ClickCount);
    }

    public void Dispose() { _capture.Dispose(); _writer.Dispose(); _audio.Dispose(); _telemetry.Dispose(); }
}
