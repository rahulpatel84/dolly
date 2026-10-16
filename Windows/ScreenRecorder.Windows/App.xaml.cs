using System.Runtime.InteropServices;
using System.Windows.Interop;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;
using StartupEventArgs = System.Windows.StartupEventArgs;
using ScreenRecorder.Windows.Core;
using Windows.Graphics.Capture;
using WinForms = System.Windows.Forms;

namespace ScreenRecorder.Windows;

/// <summary>
/// Tray-icon shell. The Windows counterpart of AppDelegate.swift: a menu, a
/// couple of global hot keys, and a result dialog. All the work is in Core.
/// </summary>
public partial class App : Application
{
    private WinForms.NotifyIcon _tray = null!;
    private CaptureSession? _session;
    private HotKeyWindow _hotKeys = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Single instance, same reasoning as the Mac app's LaunchGuards.
        if (System.Diagnostics.Process.GetProcessesByName("ScreenRecorder").Length > 1)
        {
            MessageBox.Show("Screen Recorder is already running in the tray.", "Screen Recorder");
            Shutdown();
            return;
        }

        _tray = new WinForms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Visible = true,
            Text = "Screen Recorder",
        };
        BuildMenu();

        _hotKeys = new HotKeyWindow();
        _hotKeys.Pressed += async id =>
        {
            if (id == HotKeyWindow.ToggleRecording) await ToggleAsync();
            if (id == HotKeyWindow.Pause) TogglePause();
        };
    }

    private void BuildMenu()
    {
        var menu = new WinForms.ContextMenuStrip();
        if (_session is null)
        {
            menu.Items.Add("Record Screen\tCtrl+Alt+R", null, async (_, _) => await StartAsync(pickWindow: false));
            menu.Items.Add("Record Window…", null, async (_, _) => await StartAsync(pickWindow: true));
        }
        else
        {
            menu.Items.Add("Stop Recording\tCtrl+Alt+R", null, async (_, _) => await StopAsync());
            menu.Items.Add(_session.IsPaused ? "Resume\tCtrl+Alt+P" : "Pause\tCtrl+Alt+P", null, (_, _) => TogglePause());
        }
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("Open Recordings Folder", null, (_, _) =>
            System.Diagnostics.Process.Start("explorer.exe", CaptureSession.RecordingsDirectory()));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("About", null, (_, _) =>
            MessageBox.Show("Screen Recorder 0.1.0\nDeveloped by Rahul Patel\n\nRecords clean and applies zoom afterwards from captured cursor telemetry.", "About"));
        menu.Items.Add("Quit", null, async (_, _) => { if (_session is not null) await StopAsync(); _tray.Visible = false; Shutdown(); });
        _tray.ContextMenuStrip = menu;
    }

    private async Task ToggleAsync() { if (_session is null) await StartAsync(false); else await StopAsync(); }

    private void TogglePause()
    {
        if (_session is null) return;
        if (_session.IsPaused) _session.Resume(); else _session.Pause();
        BuildMenu();
    }

    private async Task StartAsync(bool pickWindow)
    {
        GraphicsCaptureItem? item;
        int originX = 0, originY = 0;

        if (pickWindow)
        {
            // The system picker: returns a window or a monitor, no permission involved.
            var picker = new GraphicsCapturePicker();
            InitializeWithWindow(picker, _hotKeys.Handle);
            item = await picker.PickSingleItemAsync();
            if (item is null) return;
        }
        else
        {
            var monitor = MonitorFromPoint(new POINT { X = 0, Y = 0 }, 1 /* MONITOR_DEFAULTTOPRIMARY */);
            item = CreateItemForMonitor(monitor);
        }

        _session = new CaptureSession(item, originX, originY, includeMicrophone: false);
        await _session.StartAsync();
        _tray.Text = "Screen Recorder — recording";
        BuildMenu();
    }

    private async Task StopAsync()
    {
        if (_session is null) return;
        var result = await _session.StopAsync();
        _session.Dispose();
        _session = null;
        _tray.Text = "Screen Recorder";
        BuildMenu();

        double drop = result.FramesWritten + result.FramesDropped > 0
            ? 100.0 * result.FramesDropped / (result.FramesWritten + result.FramesDropped) : 0;
        MessageBox.Show(
            $"{System.IO.Path.GetFileName(result.VideoPath)}\n\nDuration: {result.Duration:mm\\:ss}\n" +
            $"Frames written: {result.FramesWritten}\nFrames dropped: {result.FramesDropped} ({drop:F1}%)\n" +
            $"Clicks recorded: {result.Clicks}\n" + (result.TelemetryPath is null ? "" : "Telemetry sidecar written"),
            "Recording saved");
    }

    // ---- interop for the picker and monitor capture ----
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);

    [ComImport, Guid("3E68D4BD-7135-4D10-8018-9FB6D9F33FA1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IInitializeWithWindow { void Initialize(IntPtr hwnd); }
    private static void InitializeWithWindow(object picker, IntPtr hwnd) =>
        ((IInitializeWithWindow)picker).Initialize(hwnd);

    [ComImport, Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow(IntPtr window, ref Guid iid);
        IntPtr CreateForMonitor(IntPtr monitor, ref Guid iid);
    }
    private static GraphicsCaptureItem CreateItemForMonitor(IntPtr hmon)
    {
        var factory = WinRT.ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
        var interop = factory.AsInterface<IGraphicsCaptureItemInterop>();
        var iid = typeof(GraphicsCaptureItem).GUID;
        var abi = interop.CreateForMonitor(hmon, ref iid);
        return WinRT.MarshalInterface<GraphicsCaptureItem>.FromAbi(abi);
    }
}

/// <summary>Hidden message-only window that owns the RegisterHotKey registrations.</summary>
internal sealed class HotKeyWindow
{
    public const int ToggleRecording = 1, Pause = 2;
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2;
    private readonly HwndSource _source;
    public IntPtr Handle => _source.Handle;
    public event Action<int>? Pressed;

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);

    public HotKeyWindow()
    {
        _source = new HwndSource(new HwndSourceParameters("ScreenRecorderHotKeys") { WindowStyle = 0 });
        _source.AddHook(Hook);
        RegisterHotKey(Handle, ToggleRecording, MOD_CONTROL | MOD_ALT, (uint)'R');
        RegisterHotKey(Handle, Pause, MOD_CONTROL | MOD_ALT, (uint)'P');
    }

    private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY) { Pressed?.Invoke(wParam.ToInt32()); handled = true; }
        return IntPtr.Zero;
    }
}
