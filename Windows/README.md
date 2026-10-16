# Screen Recorder for Windows

Developed by **Rahul Patel**. Status: **compiles, never executed.** Written and cross-compiled on macOS; no Windows machine has run it yet.
The compiler caught five real API mistakes before any of this was run — expect the runtime to find more.

| Project | What | Verified? |
|---|---|---|
| `PolishEngine` | The auto-zoom planner, ported from `ZoomPlanner.swift`. Pure arithmetic, no OS APIs. | **Yes** — 8 unit tests pass (`dotnet test`) |
| `ScreenRecorder.Windows.Core` | Capture, encode, audio, telemetry, mux. WinRT + NAudio. | **Compiles** against the Windows 11 SDK projections (cross-compiled from macOS); **not run** |
| `ScreenRecorder.Windows` | WPF/tray shell, hot keys, picker. | **Compiles** (cross-compiled from macOS with `EnableWindowsTargeting`); **not run** |

## Build

From macOS or Linux (type-check only, produces `dist/win-x64/ScreenRecorder.exe`):

```bash
cd Windows
dotnet test PolishEngine.Tests
dotnet publish ScreenRecorder.Windows -c Release -r win-x64 --self-contained \
    -p:EnableWindowsTargeting=true -p:PublishSingleFile=true -o dist/win-x64
```

On Windows, drop the `EnableWindowsTargeting` flag.

## Build (on Windows)

```powershell
winget install Microsoft.DotNet.SDK.10
cd Windows
dotnet test PolishEngine.Tests          # should be green anywhere
dotnet build ScreenRecorder.Windows -c Release
dotnet publish ScreenRecorder.Windows -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

Expect to spend the first session on `RecordingWriter.cs`: the MediaStreamSource →
MediaTranscoder path and the raw D3D11 readback are the two pieces with the most
unknowns, and neither can be exercised without a Windows GPU.

## What is different from the Mac app

| Concern | macOS | Windows |
|---|---|---|
| Capture | ScreenCaptureKit | `Windows.Graphics.Capture` |
| Permission | Screen Recording TCC prompt, restart required, bound to code signature | **None.** A yellow border on Win 11, that's all. |
| System audio | `capturesAudio` flag | WASAPI loopback (NAudio) |
| Encode | AVAssetWriter / VideoToolbox | MediaStreamSource → MediaTranscoder (hardware HEVC) |
| Container | `.mov` | `.mp4` |
| Audio mux | Same writer, extra tracks | Separate WAVs, muxed by `MediaComposition` on stop |
| Hot keys | Carbon `RegisterEventHotKey` (Ctrl+Cmd+R) | `RegisterHotKey` (Ctrl+Alt+R) |
| Telemetry | `NSEvent` polling | `GetCursorPos` polling |

The telemetry sidecar JSON is byte-for-byte the same schema. A recording made on
either platform can be polished by the same engine.

## Not yet ported

- The polish **renderer** (`PolishExporter.swift`). The *plan* is shared; applying
  it frame-by-frame on Windows means a `MediaComposition` overlay or a second
  `MediaStreamSource` pass. The engine tells you where to look; this is the part
  that moves the camera.
- Region capture, webcam, trim, GIF, dashboard, settings.
