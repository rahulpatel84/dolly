using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;
using Windows.Storage.Streams;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// Encodes captured frames to an MP4 through MediaStreamSource + MediaTranscoder.
///
/// Pure WinRT: no SharpDX, no Media Foundation interop. Hardware HEVC/H.264 is
/// selected automatically by the transcoder. Frames are read back from the GPU
/// into a byte buffer per sample -- simpler than keeping everything on the GPU,
/// and comfortably fast enough for 1080p60 on any machine with a hardware encoder.
///
/// Mirrors RecordingWriter.swift: clean video only, no effects baked in. The
/// telemetry sidecar carries everything the polish engine needs.
/// </summary>
public sealed class RecordingWriter : IDisposable
{
    private readonly BlockingCollection<(byte[] pixels, TimeSpan pts)> _queue = new(boundedCapacity: 8);
    private readonly int _width, _height, _stride;
    private readonly uint _fps;
    private readonly IntPtr _d3dDevice, _d3dContext;
    private IntPtr _staging;
    private TimeSpan? _first;
    private Task? _transcode;
    private readonly string _outputPath;

    public int FramesWritten { get; private set; }
    public int FramesDropped { get; private set; }

    public RecordingWriter(string outputPath, int width, int height, uint fps, IntPtr d3dDevice, IntPtr d3dContext)
    {
        _outputPath = outputPath;
        _width = width; _height = height; _stride = width * 4; _fps = fps;
        _d3dDevice = d3dDevice; _d3dContext = d3dContext;
    }

    public async Task StartAsync()
    {
        var props = VideoEncodingProperties.CreateUncompressed(MediaEncodingSubtypes.Bgra8, (uint)_width, (uint)_height);
        props.FrameRate.Numerator = _fps;
        props.FrameRate.Denominator = 1;
        var descriptor = new VideoStreamDescriptor(props);
        var mss = new MediaStreamSource(descriptor) { BufferTime = TimeSpan.Zero };
        mss.SampleRequested += OnSampleRequested;

        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
        profile.Video.Width = (uint)_width;
        profile.Video.Height = (uint)_height;
        profile.Video.FrameRate.Numerator = _fps;
        profile.Video.FrameRate.Denominator = 1;
        // Screen content: HEVC compresses flat colour and text far better than H.264.
        profile.Video.Subtype = MediaEncodingSubtypes.Hevc;
        profile.Audio = null;  // audio is captured separately and muxed afterwards

        var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(_outputPath)!);
        var output = await folder.CreateFileAsync(Path.GetFileName(_outputPath), CreationCollisionOption.ReplaceExisting);
        using var stream = await output.OpenAsync(FileAccessMode.ReadWrite);

        var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = true };
        var prep = await transcoder.PrepareMediaStreamSourceTranscodeAsync(mss, stream, profile);
        if (!prep.CanTranscode)
            throw new InvalidOperationException($"Transcoder refused: {prep.FailureReason}");
        _transcode = prep.TranscodeAsync().AsTask();
    }

    /// <summary>Called on the capture thread for every frame.</summary>
    public void Append(ScreenCapture.Frame frame)
    {
        var pixels = ReadBack(frame.Surface);
        if (pixels is null) { FramesDropped++; return; }
        _first ??= frame.SystemRelativeTime;
        var pts = frame.SystemRelativeTime - _first.Value;
        if (!_queue.TryAdd((pixels, pts)))
        {
            // Encoder is behind. Dropping is correct; blocking would stall capture.
            FramesDropped++;
        }
    }

    private void OnSampleRequested(MediaStreamSource sender, MediaStreamSourceSampleRequestedEventArgs args)
    {
        var deferral = args.Request.GetDeferral();
        try
        {
            if (_queue.TryTake(out var item, Timeout.Infinite) && !_queue.IsCompleted)
            {
                var buffer = item.pixels.AsBuffer();
                var sample = MediaStreamSample.CreateFromBuffer(buffer, item.pts);
                sample.Duration = TimeSpan.FromSeconds(1.0 / _fps);
                args.Request.Sample = sample;
                FramesWritten++;
            }
            else
            {
                args.Request.Sample = null;  // end of stream
            }
        }
        catch (InvalidOperationException)
        {
            args.Request.Sample = null;
        }
        finally { deferral.Complete(); }
    }

    public async Task FinishAsync()
    {
        _queue.CompleteAdding();
        if (_transcode is not null) await _transcode;
    }

    // ---- GPU readback -------------------------------------------------------
    // Copy the captured texture into a CPU-readable staging texture, map it,
    // and copy rows out. Done with raw COM vtable calls to avoid a dependency
    // on a D3D wrapper library.

    [StructLayout(LayoutKind.Sequential)]
    private struct D3D11_TEXTURE2D_DESC
    {
        public uint Width, Height, MipLevels, ArraySize, Format;
        public uint SampleCount, SampleQuality;
        public uint Usage, BindFlags, CPUAccessFlags, MiscFlags;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct D3D11_MAPPED_SUBRESOURCE { public IntPtr pData; public uint RowPitch, DepthPitch; }

    private const uint DXGI_FORMAT_B8G8R8A8_UNORM = 87;
    private const uint D3D11_USAGE_STAGING = 3;
    private const uint D3D11_CPU_ACCESS_READ = 0x20000;
    private const uint D3D11_MAP_READ = 1;

    private unsafe byte[]? ReadBack(IDirect3DSurface surface)
    {
        var texture = Direct3DInterop.GetTexture(surface);
        try
        {
            if (_staging == IntPtr.Zero)
            {
                var desc = new D3D11_TEXTURE2D_DESC
                {
                    Width = (uint)_width, Height = (uint)_height, MipLevels = 1, ArraySize = 1,
                    Format = DXGI_FORMAT_B8G8R8A8_UNORM, SampleCount = 1,
                    Usage = D3D11_USAGE_STAGING, CPUAccessFlags = D3D11_CPU_ACCESS_READ,
                };
                // ID3D11Device::CreateTexture2D is vtable slot 5.
                var create = (delegate* unmanaged[Stdcall]<IntPtr, D3D11_TEXTURE2D_DESC*, IntPtr, IntPtr*, int>)
                    (*(IntPtr**)_d3dDevice)[5];
                IntPtr staging;
                Marshal.ThrowExceptionForHR(create(_d3dDevice, &desc, IntPtr.Zero, &staging));
                _staging = staging;
            }

            // ID3D11DeviceContext::CopyResource is slot 47; Map is 14; Unmap is 15.
            var copy = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr, void>)(*(IntPtr**)_d3dContext)[47];
            copy(_d3dContext, _staging, texture);

            var map = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint, uint, D3D11_MAPPED_SUBRESOURCE*, int>)
                (*(IntPtr**)_d3dContext)[14];
            var unmap = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, void>)(*(IntPtr**)_d3dContext)[15];

            D3D11_MAPPED_SUBRESOURCE mapped;
            if (map(_d3dContext, _staging, 0, D3D11_MAP_READ, 0, &mapped) < 0) return null;
            try
            {
                var pixels = new byte[_stride * _height];
                fixed (byte* dst = pixels)
                {
                    for (int y = 0; y < _height; y++)
                        System.Buffer.MemoryCopy((byte*)mapped.pData + y * mapped.RowPitch, dst + y * _stride, _stride, _stride);
                }
                return pixels;
            }
            finally { unmap(_d3dContext, _staging, 0); }
        }
        finally { Marshal.Release(texture); }
    }

    public void Dispose()
    {
        _queue.Dispose();
        if (_staging != IntPtr.Zero) { Marshal.Release(_staging); _staging = IntPtr.Zero; }
    }
}
