# Dolly User Guide

**Dolly** — *the recorder that follows you.* Record your screen, polish the result automatically, take screenshots and annotate them, all from the menu bar or the Dolly dashboard. This guide covers every feature. Version 0.2.1 · macOS 14 or newer.

> **First launch:** macOS asks for **Screen Recording** permission (System Settings → Privacy & Security → Screen Recording). Toggle **Dolly** on, then quit and reopen Dolly once. Microphone and Camera permissions are requested only when you first use those features. If a recording ever comes out black, choose **Help → Grant Screen Recording Permission…**

---

## 1. Where things live

| Place | What you do there |
|---|---|
| **Menu-bar icon** (top right) | Start/stop/pause recording, take screenshots, open the dashboard, Settings, Quit. |
| **Dashboard window** (click the Dock icon or menu bar → *Recordings*) | Browse, play, trim, polish, export, share and delete everything Dolly has captured. |
| **Global hotkeys** | Work in any app, even when Dolly is hidden. Defaults are listed in §7; change them in Settings → Hotkeys. |
| **Screenshot editor** | Opens automatically after each screenshot (configurable). |
| **Settings** (⌘,) | General, Recording, Auto-Zoom, Screenshots, Hotkeys tabs. |
| **Files** | Recordings and screenshots are saved to `~/Movies/Screen Recordings` by default. Change the folder in Settings → General → Files. |

---

## 2. Recording

### Start a recording
- **Full screen** — menu bar → *Record Full Screen*, dashboard tile **Record Screen**, or **⌃⌘R**. With several displays you are asked which one.
- **Area** — *Record Area…*, the **Record Area** tile, or **⌃⇧⌘R**. Drag a rectangle on any display. **Click a window** instead of dragging to record exactly that window. Press **Esc** to cancel.
- **Record last area again** — **⌃⌥⌘R** reuses the previous rectangle without asking.
- **Webcam only** — dashboard tile **Webcam Only** or menu bar → *Record Webcam*: records the camera to a movie, no screen.
- **Audio only** — dashboard tile **Audio Only**: records system audio (and the mic if enabled) to an `.m4a`.
- **Scheduled** — menu bar → *Schedule Recording…* starts a full-screen recording at a chosen time.

A 3-second countdown appears before capture starts (turn it off in Settings → General). The menu-bar icon turns red while recording and shows the elapsed time.

### While recording
- **Pause / Resume** — **⌃⌘P** or the menu. Paused time is removed from the final movie; audio and webcam stay in sync.
- **Draw on screen** — **⌃⌘D** toggles a drawing layer over the screen. Drag to draw with the pointer (colours and width from the palette that appears). Your strokes are captured in the video; the palette itself is not. **Esc** stops, **C** clears, **⌘Z** undoes a stroke.
- **Stop** — **⌃⌘R** again, the menu, or click the menu-bar icon. Quitting Dolly while recording also stops and saves cleanly.
- **Auto-stop** — Settings → General → *Stop recording automatically after* (5/15/30/60 min, or never).

### What gets captured
- Video is HEVC (H.265) at 30 or 60 fps (Settings → Recording → Video). Quality: *Balanced*, *High*, or *Maximum*.
- **System audio** is always included. **Microphone** is added when *Include microphone* is on (menu bar or Settings → Recording → Audio).
- **Webcam** — Settings → Recording → Webcam → *Record webcam alongside the screen*. The camera is saved as a separate movie beside the recording (`…-webcam.mov`) and composited as picture-in-picture when you polish (§3). A small live preview window shows the camera during recording.
- **Telemetry** — Dolly also saves a tiny `…telemetry.json` of cursor positions and clicks. It drives Auto-Zoom and is never shared unless you copy the file yourself.

---

## 3. Auto-Zoom polish

Auto-Zoom turns a raw recording into a presentation-ready video: the camera smoothly zooms toward where you click and type, the cursor gets a soft halo, clicks ripple, silences are cut, and the whole thing can sit on a gradient background.

**Run it:** in the dashboard select a recording → **Auto-Zoom** (inspector) or the **Auto-Zoom All** button for everything that is not polished yet. The polished movie is saved beside the original as `…-polished.mov`; the original is never changed. **Play Polished** previews it.

**Tune it** in Settings → Auto-Zoom:

| Setting | Effect |
|---|---|
| Preset | One-click Subtle / Balanced / Dramatic combinations. |
| Zoom strength | How far the camera pushes in, 1.3× to 3×. |
| Smoothing | Seconds the camera takes to settle; higher = calmer moves. |
| Highlight cursor | Soft halo around the pointer plus click rings. |
| Remove silences | Cuts stretches quieter than the threshold that last longer than the minimum, keeping a little padding around speech. |
| Background | *None*, *Gradient* or *Solid* — pads the video on a coloured canvas with rounded corners and shadow. |
| Export resolution | Keep original, or scale to 1080p / 1440p / 4K. |

The webcam movie (if any) is placed as a rounded picture-in-picture in the lower-right corner of the polished export.

> Rendering runs at roughly real time on Apple Silicon (a 1-minute clip takes about a minute). Progress is shown in the dashboard; you can keep using Dolly meanwhile.

---

## 4. Dashboard

The dashboard is Dolly's home window.

- **Sidebar:** *Recordings*, *Polished*, *Screenshots*. Audio-only captures appear under Recordings.
- **Toolbar:** search by name, sort (Newest, Oldest, Longest, Largest, Name), **grid / list** view, and the inspector toggle.
- **Quick-action strip:** Record Screen · Record Area · Screenshot · Screenshot Area · Audio Only · Webcam Only.
- **Inspector** (right pane) shows the file's details and all actions:

| Action | What it does |
|---|---|
| **Play** / **Play Polished** | Opens Dolly's own player window. |
| **Auto-Zoom** | Runs the polish engine (§3). |
| **Trim…** | Opens the trimmer (below). |
| **Export ▸** | QuickTime (.mov) · MP4 · MP4 no audio · MP4 compressed H.264 1080p · Audio only (.m4a) · Animated GIF. Choose *Original* or *Polished* as the source. |
| **Share** | macOS share sheet — AirDrop, Messages, Mail, Notes, or any app that accepts files. |
| **Edit** (screenshots) | Re-opens the screenshot in the editor. |
| **Copy Image / Copy Path / Show in Finder / Open** | Clipboard and Finder helpers. |
| **Rename…** | Renames the file and its sidecars (webcam, telemetry, polished) together. |
| **Pin on Screen** (screenshots) | Floats the image above all windows. |
| **Move to Trash** | Deletes the file and its sidecars. |

### Trimmer
Drag the two handles (or type times) to select a range, pick **Keep selection** or **Remove selection**, preview, then **Trim**. The result is saved as a new file; sidecars are cut to match so Auto-Zoom still lines up.

---

## 5. Screenshots

### Capture
- **Screen** — **⌃⌘S**, menu bar → *Screenshot Screen*, or the **Screenshot** tile. With several displays, the one under the pointer is captured.
- **Area** — **⌃⌘A** or *Screenshot Area…* Every display dims; drag a rectangle on any of them. **Click** (no drag) on a window to capture that window exactly. **Esc** cancels. The size readout follows the pointer.
- **Window** — **⌃⌘W** or *Screenshot Window…* then click a window. Settings → Screenshots → *Window screenshots → Background* chooses what surrounds it: system shadow, transparent, solid colour, gradient, or trimmed.

Screenshots are captured at full native resolution (Retina pixels). Turn on *Downscale Retina screenshots to 1×* only if you want smaller files. Default save format is PNG (lossless); JPEG and HEIC are available in Settings → Screenshots → Saving.

### After capture
Settings → Screenshots → *After capture → Then*:
- **Open editor** (default) — the editor below appears immediately.
- **Show preview** — a small thumbnail slides in at the bottom-right for a few seconds; click it to edit, drag it into another app, or let it fade.
- **Copy only** — copies to the clipboard and saves silently.
- **Nothing** — just saves.

### The editor

The toolbar, left to right: **Copy** · **Save ▾** · **Pin** · **Share** · tools · **Undo / Redo** · **Copy Text** · size readout · **Zoom** · **Style** · **Export** · **Done**. Hover over any control for a description (it also appears in the hint line at the bottom).

| Tool | Key | Use |
|---|---|---|
| Colour picker | **P** | Click a pixel to copy its hex colour. |
| Arrow | **A** | Drag tail → head. Choose single, double, or plain line in the strip below. |
| Rectangle | **R** | Drag to outline. |
| Ellipse | **O** | Drag to circle. |
| Line | **L** | Straight line. |
| Highlighter | **H** | Translucent band over text. |
| Blur | **B** | Pixelates anything sensitive. |
| Text | **T** | Click, type, click away. |
| Number | **N** | Drops 1, 2, 3… step badges. |
| Crop | **C** | Drag the area to keep; Done applies it. |

Colours and stroke width (also keys **1–9**) are in the strip under the toolbar. **⌘Z / ⇧⌘Z** undo and redo. **⌘+ / ⌘−** zoom; click the percentage for *Fit* or *100 %*. **Copy Text** runs OCR on the whole image and copies every recognised word.

**Style (paint-palette button)** decorates the screenshot:
- **Background** — none, or one of six gradients (Midnight, Sunset, Ocean, Mint, Graphite, Paper).
- **Padding** and **Corners** sliders, **Shadow** toggle.
- **macOS window frame** — adds a title bar with traffic lights, and an optional window title.
The decoration is drawn live in the editor and is applied to Copy, Save, Share and Export alike. Annotations stay inside the image.

**Export (document-arrow button)** saves in another format:
- **PNG** or **TIFF** (lossless), **JPEG**, **HEIC** or **WebP** with a **quality slider** (the estimated file size updates as you drag — HEIC and WebP are roughly half the size of JPEG at the same quality), or **PDF** (single page at the image's pixel size).
- Press **Export…**, pick a location, done. The Finder reveals the new file.

**Finishing:** **Copy** (⇧⌘C) puts the image on the clipboard; **Save ▾** offers *Save as New* or *Overwrite Original*; **Share** opens the macOS share sheet; **Pin** floats a copy above every window (drag it anywhere, click ✕ to dismiss); **Done** (⏎) saves, copies and closes.

---

## 6. Settings reference

**General** — Launch at login · 3-second countdown · Stop recording automatically after · Recordings folder · About.
**Recording** — Frame rate (30/60) · Quality · Include microphone · Webcam on/off + camera choice · Drawing-on-screen help.
**Auto-Zoom** — Presets · Zoom strength (1.3–3.0×) · Smoothing (0.5–3 s) · Highlight cursor · Remove silences (threshold dB, minimum length) · Background · Export resolution.
**Screenshots** — Save folder · Save format (PNG/JPEG/HEIC) · Downscale Retina · After capture (editor / preview / save) · Preview duration · Window background.
**Hotkeys** — every shortcut below. Click a field, press the new combination, done. Fields that macOS or another app already owns are flagged in orange; use the ↺ button to restore one default or *Reset all shortcuts to defaults*.

---

## 7. Default hotkeys

| Action | Shortcut |
|---|---|
| Record / stop (full screen) | **⌃⌘R** |
| Record area | **⌃⇧⌘R** |
| Record last area again | **⌃⌥⌘R** |
| Pause / resume | **⌃⌘P** |
| Draw on screen while recording | **⌃⌘D** |
| Screenshot screen | **⌃⌘S** |
| Screenshot area | **⌃⌘A** |
| Screenshot window | **⌃⌘W** |

Inside the editor: tools **P A R O L H B T N C**, width **1–9**, **⌘Z/⇧⌘Z**, **⌘+/⌘−**, **⇧⌘C** copy, **⏎** done. While drawing on screen during a recording: **Esc** stops, **C** clears, **⌘Z** undoes.

> Shortcuts macOS reserves — ⇧⌘3, ⇧⌘4, ⇧⌘5, ⌘Space, ⌃↑/↓ and others — cannot be assigned. Dolly's hotkeys do not require Accessibility permission.

---

## 8. Tips & troubleshooting

- **Black or empty recording** → Screen Recording permission is missing or stale. *Help → Grant Screen Recording Permission…*, then quit and reopen Dolly.
- **No microphone in the recording** → Enable *Include microphone* and allow the Microphone permission when asked. macOS 15 or newer is needed for mic capture through this pipeline.
- **Webcam not listed** → Another app may be using it. Close that app and reopen Settings → Recording.
- **Hotkey does nothing** → Settings → Hotkeys shows it in orange when the system refused it; pick another combination.
- **Editor feels soft/blurry** → You are zoomed past 100 %. Click the zoom percentage and choose *100 %* to see native pixels.
- **Large files** → Use *Export → MP4, compressed H.264 1080p*, or for screenshots *Export → HEIC/WebP* with a lower quality.
- **Logs** — `~/Library/Logs/ScreenRecorder.log` records unexpected capture stops; include it when reporting a problem.

Dolly is open source: <https://github.com/rahulpatel84/dolly>. Website: <https://screen-recorder-site.vercel.app>. Developer: Rahul Patel.
