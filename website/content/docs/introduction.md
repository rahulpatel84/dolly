# Introduction

^ Dolly is a native macOS screen recorder that does the editing for you. It records a clean stream plus a small cursor-telemetry file, then applies zoom, cursor emphasis and silence removal afterwards — so any recording can be re-polished later, and nothing is burned into the pixels.

![The Dolly dashboard with three recordings, one already polished](/shots/dashboard.png "The dashboard: library on the left, quick actions on top, details and actions on the right.")

## What Dolly does

- **Records** your screen (full display, an area, or a single window), system audio, your microphone and your webcam — up to 4K at 60 fps, HEVC.
- **Polishes automatically.** Auto-Zoom follows where you click and type, highlights the cursor, ripples on clicks, cuts dead air and frames the video on a background. One click.
- **Takes screenshots** and opens them in an editor with arrows, shapes, highlighter, blur, text, numbered steps, crop, colour picker and OCR. Decorate with a macOS window frame on a gradient; export as PNG, JPEG, HEIC, WebP, TIFF or PDF with a quality slider.
- **Manages everything** in a dashboard: play, trim, export (MOV, MP4, muted, compressed, M4A, GIF), share, rename, delete.
- **Works from anywhere** with permission-free global hotkeys and a menu-bar icon.

## What Dolly does not do

Dolly is deliberately local and small. It has **no account, no cloud, no upload** — sharing uses the macOS share sheet. It does not record scrolling captures, it does not show keystrokes on screen, and the Windows build is work in progress. See the [comparison](/compare) for how that stacks up against Loom, Movavi, CleanShot X and others.

## How it works

Every recording is three files: the movie (`.mov`), a telemetry sidecar (`.telemetry.json`, cursor positions and clicks at 60 Hz) and, if enabled, the webcam movie. Auto-Zoom reads the telemetry, plans camera moves with a smoothing model, and renders a new movie with CoreImage on the GPU. The original is never modified.

## Requirements

- macOS 14 Sonoma or newer (microphone capture through the native pipeline needs macOS 15).
- Apple silicon or Intel. Polishing runs at roughly real time on Apple silicon.
- Screen Recording permission; Microphone and Camera only if you use them.

Next: [Install Dolly](/docs/install).
