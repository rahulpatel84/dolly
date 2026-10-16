using Windows.Foundation.Metadata;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// Windows.Graphics.Capture, the Windows equivalent of ScreenCaptureKit.
///
/// No permission prompt exists for this on Windows. The OS draws a yellow
/// border around a captured window (Windows 11) and that is the whole consent
/// model, which removes the entire permission milestone from the Mac plan.
/// </summary>
public sealed class ScreenCapture : IDisposable
{
    public readonly record struct Frame(IDirect3DSurface Surface, TimeSpan SystemRelativeTime, SizeInt32 Size);

    private readonly IDirect3DDevice _device;
    private readonly GraphicsCaptureItem _item;
    private Direct3D11CaptureFramePool? _pool;
    private GraphicsCaptureSession? _session;
    private SizeInt32 _size;

    public event Action<Frame>? FrameArrived;

    public ScreenCapture(IDirect3DDevice device, GraphicsCaptureItem item)
    {
        _device = device;
        _item = item;
        _size = item.Size;
    }

    public SizeInt32 Size => _size;

    public void Start(bool showCursor = true)
    {
        // Two buffers: one being encoded while the next is captured.
        _pool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, _size);
        _pool.FrameArrived += OnFrameArrived;
        _session = _pool.CreateCaptureSession(_item);
        _session.IsCursorCaptureEnabled = showCursor;
        // Windows 11 only: suppress the yellow border around the captured region.
        if (ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
            _session.IsBorderRequired = false;
        _session.StartCapture();
    }

    private void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        using var frame = sender.TryGetNextFrame();
        if (frame is null) return;

        // The window may have been resized; recreate the pool to match.
        if (frame.ContentSize.Width != _size.Width || frame.ContentSize.Height != _size.Height)
        {
            _size = frame.ContentSize;
            sender.Recreate(_device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, _size);
            return;
        }

        FrameArrived?.Invoke(new Frame(frame.Surface, frame.SystemRelativeTime, _size));
    }

    public void Dispose()
    {
        _session?.Dispose();
        _pool?.Dispose();
        _session = null;
        _pool = null;
    }
}
