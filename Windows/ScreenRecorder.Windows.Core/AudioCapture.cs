using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// System audio and microphone, each to its own WAV beside the video.
///
/// WASAPI loopback is built into Windows since Vista: no virtual audio device
/// is needed, exactly as ScreenCaptureKit removed that need on macOS 13.
/// The WAVs are muxed into the MP4 by <see cref="Muxer"/> once recording stops.
/// </summary>
public sealed class AudioCapture : IDisposable
{
    private readonly WasapiLoopbackCapture _system = new();
    private readonly WasapiCapture? _mic;
    private readonly WaveFileWriter _systemWriter;
    private readonly WaveFileWriter? _micWriter;

    public string SystemPath { get; }
    public string? MicPath { get; }

    public AudioCapture(string videoPath, bool includeMicrophone)
    {
        var stem = Path.ChangeExtension(videoPath, null);
        SystemPath = stem + ".system.wav";
        _systemWriter = new WaveFileWriter(SystemPath, _system.WaveFormat);
        _system.DataAvailable += (_, e) => _systemWriter.Write(e.Buffer, 0, e.BytesRecorded);

        if (includeMicrophone)
        {
            var device = new MMDeviceEnumerator().GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);
            _mic = new WasapiCapture(device);
            MicPath = stem + ".mic.wav";
            _micWriter = new WaveFileWriter(MicPath, _mic.WaveFormat);
            _mic.DataAvailable += (_, e) => _micWriter.Write(e.Buffer, 0, e.BytesRecorded);
        }
    }

    public void Start() { _system.StartRecording(); _mic?.StartRecording(); }

    public void Stop()
    {
        _system.StopRecording();
        _mic?.StopRecording();
        _systemWriter.Flush();
        _micWriter?.Flush();
    }

    public void Dispose()
    {
        _system.Dispose(); _mic?.Dispose();
        _systemWriter.Dispose(); _micWriter?.Dispose();
    }
}
