using System.Runtime.InteropServices;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace ScreenRecorder.Windows.Core;

/// <summary>
/// The small amount of COM glue Windows.Graphics.Capture needs: creating a
/// WinRT IDirect3DDevice over a D3D11 device, and getting the D3D11 texture
/// out of a captured IDirect3DSurface. This is the standard pattern from the
/// Windows capture samples; there is no managed-only way around it.
/// </summary>
internal static unsafe class Direct3DInterop
{
    [DllImport("d3d11.dll", ExactSpelling = true)]
    private static extern int D3D11CreateDevice(
        IntPtr adapter, int driverType, IntPtr software, uint flags,
        IntPtr featureLevels, uint featureLevelCount, uint sdkVersion,
        out IntPtr device, out int featureLevel, out IntPtr context);

    [DllImport("d3d11.dll", ExactSpelling = true)]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr inspectable);

    [ComImport, Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface(in Guid iid);
    }

    private const int D3D_DRIVER_TYPE_HARDWARE = 1;
    private const uint D3D11_CREATE_DEVICE_BGRA_SUPPORT = 0x20;
    private const uint D3D11_SDK_VERSION = 7;
    private static readonly Guid IID_ID3D11Texture2D = new("6f15aaf2-d208-4e89-9ab4-489535d34f9c");
    private static readonly Guid IID_IDXGIDevice = new("54ec77fa-1377-44e6-8c32-88fd5f44c84c");

    /// <summary>Creates a hardware D3D11 device and its WinRT wrapper.</summary>
    public static (IntPtr d3dDevice, IntPtr d3dContext, IDirect3DDevice winrtDevice) CreateDevice()
    {
        int hr = D3D11CreateDevice(
            IntPtr.Zero, D3D_DRIVER_TYPE_HARDWARE, IntPtr.Zero, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            IntPtr.Zero, 0, D3D11_SDK_VERSION, out var device, out _, out var context);
        Marshal.ThrowExceptionForHR(hr);

        hr = Marshal.QueryInterface(device, in IID_IDXGIDevice, out var dxgiDevice);
        Marshal.ThrowExceptionForHR(hr);

        hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out var inspectable);
        Marshal.ThrowExceptionForHR(hr);
        Marshal.Release(dxgiDevice);

        var winrt = MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
        Marshal.Release(inspectable);
        return (device, context, winrt);
    }

    /// <summary>The ID3D11Texture2D behind a captured surface. Caller releases.</summary>
    public static IntPtr GetTexture(IDirect3DSurface surface)
    {
        var access = surface.As<IDirect3DDxgiInterfaceAccess>();
        return access.GetInterface(in IID_ID3D11Texture2D);
    }
}
