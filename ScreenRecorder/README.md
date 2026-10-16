# Dolly

**Dolly** — the macOS screen recorder that follows you. Automatic cursor-aware zoom, applied after capture.

Developed by **Rahul Patel**.

Records a clean stream plus a cursor-telemetry sidecar, then applies zoom,
cursor framing and click emphasis afterwards — so effects are never burned
into the pixels and can always be recomputed.

## Installing (end users)

See **[INSTALL.md](INSTALL.md)** — also included inside the DMG as *Install Guide.md*.
Covers the Gatekeeper warning, the Screen Recording permission (and the restart
it needs), where recordings go, and how to uninstall.

## Build and run

```bash
./build.sh            # build the .app into build.noindex/
./build.sh --dmg      # build the .app and dist/Dolly-0.2.1.dmg
open build.noindex/ScreenRecorder.app
```

Look for the ⏺ icon in the menu bar. There is no Dock icon and no window —
`LSUIElement` is set.

## First run: grant permission

macOS will prompt for **Screen Recording** on first launch. After granting it:

```bash
killall ScreenRecorder && open build.noindex/ScreenRecorder.app
```

The restart is mandatory. macOS does not apply a Screen Recording grant to an
already-running process, and this trips up almost everyone the first time.

If the prompt never appeared: System Settings → Privacy & Security → Screen &
System Audio Recording → enable **Screen Recorder**.

> **Note:** each `./build.sh` re-signs the binary ad-hoc, which changes its code
> signature. macOS may then treat it as a different app and drop the permission.
> If recording stops working after a rebuild, remove the entry in System
> Settings and re-add it. A real Developer ID signature makes this stable.

## What it does

| | |
|---|---|
| Capture | Full display at native Retina resolution, 60 fps cap |
| Video | HEVC, hardware encoded via VideoToolbox |
| Audio | System audio always; microphone optional (menu toggle) |
| Output | `~/Movies/Screen Recordings/Recording <date>.mov` |
| Telemetry | `Recording <date>.telemetry.json` beside the video |
| **Auto-zoom** | Cursor-aware zoom applied after capture, rendered faster than realtime |
| **Click emphasis** | Expanding ring at each click, composited in source space so it zooms with content |
| **Cursor highlight** | Soft halo following the pointer, from the same telemetry |
| **Screenshots** | PNG to disk and clipboard, full screen or dragged area |
| **GIF export** | 12 fps, ≤900 px, from the polished render |
| **Global hotkeys** | ⌃⌘R record, ⌃⌘S screenshot — no extra permission needed |
| **Countdown** | 3·2·1 overlay so the first second isn't you leaving the menu bar |
| **Pause / resume** | ⌃⌘P. The gap is removed from the file, not frozen into it |
| **Webcam** | Recorded to a separate `.webcam.mov`, live circular preview, composited as PiP by Auto-Zoom |
| **Trim** | Lossless passthrough cut; telemetry and webcam sidecars trimmed to match |
| **Settings** | ⌘, — fps, quality, zoom presets, silence removal, background, resolution, hotkeys, screenshots, login |
| **Screenshot editor** | Arrows, boxes, blur, text, numbered steps, crop, OCR, pin |
| **Exports** | MOV, MP4, MP4 muted, MP4 compressed 1080p, audio-only M4A, GIF |
| **Remove a section** | Trim window: keep or cut the selection; sidecars follow |
| **Dashboard** | Window listing every recording with thumbnails, durations and one-click polish |
| Reporting | Dropped-frame count shown after every recording |

### Menu

```
Record Full Screen            ⌃⌘R
Record Area…                  ← drag out any region
Record Window        ▸        ← pick any open window
Record Display       ▸        ← shown when you have more than one
──────────────────
Screenshot Screen             ⌃⌘S
Screenshot Area…
──────────────────
Include Microphone
3-Second Countdown
──────────────────
Recordings…            ⌘R     ← dashboard
Open Recordings Folder
──────────────────
About
Quit                   ⌘Q
```

### Global hotkeys

| Shortcut | Action |
|---|---|
| ⌃⌘R | Start / stop recording from anywhere |
| ⌃⌘P | Pause / resume |
| ⌃⌘S | Screenshot the screen |

### Pause / resume

`RecordingClock` owns one timeline for every writer. While paused, samples are
dropped; on resume the pause duration is subtracted from every later timestamp,
so the output has no hole and no frozen frame. The webcam file shares the same
clock, which is what keeps it aligned with the screen without any later
reconciliation.

### Webcam

Deliberately **not** composited live. It records to `<name>.webcam.mov` on the
shared clock, with a draggable circular preview so you can see you are in
frame. Auto-Zoom composites it as a picture-in-picture *after* the zoom crop,
so it stays pinned to the corner while the content moves. Untick it in
Settings and it is simply left out of the export — the clean recording never
had it baked in.

### Trim

Passthrough export: no re-encode, lossless, fast. The telemetry sidecar is cut
to the same range with timestamps rebased, and the webcam file is cut
identically, so a trimmed recording can still be auto-zoomed with its PiP.

Registered through Carbon's `RegisterEventHotKey`. The API is ancient but it
is the only way to claim a system-wide shortcut **without** the Accessibility
or Input Monitoring permission — an `NSEvent` global monitor or a
`CGEventTap` would each cost another approval prompt.

### Screenshots

Full screen (⌃⌘S), dragged area (⌃⌘A), or a window (⌃⌘W — the one under the
mouse, or pick from a list). Always copied to the clipboard as well as saved.

**After capture** (Settings): a floating preview thumbnail bottom-right — click
to edit, drag it straight into Slack/Mail, auto-hides — or open the editor
directly, or just copy.

**Editor** — arrows, rectangles, ellipses, lines, highlighter, pixelate/blur,
text, numbered steps, crop. Eight colours, stroke width, undo/redo, single-key
tools (A R O L H B T N C). **Copy Text** runs OCR (Vision) over the whole
screenshot. **Pin** floats it above every window. Save as new, overwrite, copy,
share.

**Window screenshots** can have a system shadow, transparent margins, a solid
colour, a gradient, or the shadow trimmed off entirely. PNG or JPEG, optional
downscale of Retina captures to 1×, any folder.

**Hotkeys** are all rebindable in Settings — click a field, press the new combo.
Launch at login is a toggle.

### GIF export

Dashboard row menu → **Export GIF…**. Exports the polished version when one
exists, since a GIF of the zoomed render is usually what you actually want to
share. Sampled at 12 fps, max 900 px wide, capped at 30 s — GIF is a 256-colour
format, so a full-rate export would be huge and look no better.

### Capture targets

| Target | How |
|---|---|
| Full screen | `SCContentFilter(display:)` at native pixel size |
| Area | Drag-select overlay → `SCStreamConfiguration.sourceRect` |
| Window | `SCContentFilter(desktopIndependentWindow:)`, follows the window |
| Display | Submenu appears only with multiple displays |

Area selection dims every screen, punches the selection clear, and shows live
pixel dimensions. Escape or right-click cancels. Region and window sizes are
rounded to even numbers because hardware encoders reject odd dimensions.

### Playback

Recordings play **inside the dashboard** via AVKit — nothing is handed off to
QuickTime. When a polished version exists, a segmented control switches
between Original and Polished in place, which is the only practical way to
judge whether the auto-zoom helped.

### Auto-zoom

Click **Auto-Zoom** on any recording in the dashboard, or headless:

```bash
./build.noindex/ScreenRecorder.app/Contents/MacOS/ScreenRecorder \
    --polish ~/Movies/"Screen Recordings"/"Recording ... .mov"
```

Writes `<name> (polished).mov` beside the original. The original is never
modified, so you can re-polish with different settings any time.

How the camera path is chosen (`ZoomPlanner.swift`):

1. The timeline is bucketed into 0.5 s windows.
2. Each window yields a cursor centroid and a spread (how far the cursor roamed).
3. Tight spread or a nearby click → zoom in; wide roaming → pull back out.
4. The scale and centre series are smoothed **forwards then backwards**, so the
   camera neither trails the cursor nor anticipates it.
5. The centre is clamped so the zoomed view never runs off the frame edge.

Tunable via `ZoomPlanner.Settings`: `maxScale`, `midScale`, `smoothingSeconds`,
`windowSeconds`, `clickHoldSeconds`.

This stage is pure arithmetic over the sidecar and the video timeline — no
platform APIs — which is what makes it portable to Windows later.

## Verified

End-to-end test on macOS 27 / Apple Silicon, 5-second capture:

| Check | Result |
|---|---|
| Frames written / dropped | 238 / 0 (0.0%) |
| Video | 1920×1080, opens in AVFoundation, `moov` + `mdat` present |
| Tracks | 1 video + 1 audio |
| Telemetry | 303 samples, **100% inside the video frame** |
| Duration accuracy | 5.06 s video vs 5.04 s requested |

Reproduce with:

```bash
open -a "$PWD/build.noindex/ScreenRecorder.app" --args --record 5
cat ~/Movies/"Screen Recordings"/last-test-report.json
```

> Recorded frame rate reads as ~47 fps, not 60. That is correct:
> ScreenCaptureKit marks frames where nothing changed as `.idle` and we skip
> them, so a mostly-static screen yields fewer frames. Presentation timestamps
> keep playback correct, and the file is smaller for it.

## Architecture

The one decision that shapes everything: **record clean, polish afterwards.**

Nothing is baked into the pixels during capture. Cursor position and clicks go
to a separate JSON sidecar, sampled at 60 Hz. That makes automatic zoom, cursor
smoothing and click emphasis possible later — effects that can never be applied
or adjusted once they are burned into the video.

```
ScreenCaptureKit ──┬── video ──────┐
                   └── system audio ├──> AVAssetWriter ──> .mov  (clean)
AVCaptureDevice ────── microphone ──┘
NSEvent polling ────── cursor, clicks ───> .telemetry.json  (separate)
```

| File | Role |
|---|---|
| `CaptureEngine.swift` | `SCStream` setup, routes the three output types |
| `RecordingWriter.swift` | `AVAssetWriter`, video + 2 audio tracks, frame accounting |
| `TelemetryRecorder.swift` | 60 Hz cursor sampling → sidecar |
| `Permissions.swift` | TCC checks, prompts, Settings deep links |
| `AppDelegate.swift` | Menu bar UI, elapsed timer, result reporting |

### Why polling instead of `CGEventTap`

Sampling `NSEvent.mouseLocation` and `pressedMouseButtons` needs **no
permission at all**. A `CGEventTap` would need Accessibility or Input
Monitoring, and another prompt to explain. Keystroke display will need the tap
eventually; cursor telemetry does not, so it does not pay that cost yet.

### Sidecar format

```json
{
  "version": 1,
  "sampleRateHz": 60,
  "displayPixelWidth": 3456,
  "samples": [ { "t": 0.0167, "x": 1728.0, "y": 540.0, "click": false } ]
}
```

`t` is seconds from recording start. `x` and `y` are top-left-origin pixels,
matching the video frame coordinate space, so a sample maps directly onto a
frame with no further conversion.

## Not built yet

Next, in order: auto-zoom from the sidecar (milestone 6 — this is the actual
product), cursor smoothing, export presets, webcam overlay, trim UI, FFmpeg
sidecar for MKV/GIF/MP3.

Deliberately skipped: scrolling screenshots. No API, high difficulty, least
requested.

## Constraints

- **macOS 14+.** Microphone capture via `SCStreamConfiguration` needs 15+; on
  14 the mic toggle is silently inactive.
- **Not sandboxed, so not App Store.** Fine as-is, but `CGEventTap` (keystroke
  display) and a bundled FFmpeg would both make this permanent. Decide
  distribution before building either.
- **Single display.** Records `displays.first`; no picker yet.
