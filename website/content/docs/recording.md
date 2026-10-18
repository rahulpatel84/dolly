# Recording

^ Start from the menu bar, the dashboard, or a hotkey. Every mode produces a standard `.mov` you can open anywhere, plus the telemetry sidecar that powers Auto-Zoom.

## Modes

| Mode | How to start | Notes |
|---|---|---|
| **Full screen** | Menu bar → *Record Full Screen* · dashboard **Record Screen** · [[⌃⌘R]] | With several displays you choose which one. |
| **Area** | *Record Area…* · **Record Area** · [[⌃⇧⌘R]] | Drag a rectangle on any display. Click a window instead of dragging to record exactly that window. [[Esc]] cancels. |
| **Last area again** | [[⌃⌥⌘R]] | Reuses the previous rectangle without asking. |
| **Window** | Menu bar → *Record Window* → pick from the list | Follows the window if it moves. |
| **Webcam only** | **Webcam Only** tile · *Record Webcam* | Camera to a movie, no screen. |
| **Audio only** | **Audio Only** tile | System audio (plus mic if enabled) to `.m4a`. |
| **Scheduled** | Menu bar → *Schedule Recording…* | Starts a full-screen recording at a chosen time. |

A three-second countdown shows before capture starts (Settings → General). The menu-bar icon turns red and shows elapsed time while recording.

## While recording

- **Pause / resume** — [[⌃⌘P]] or the menu. Paused time is cut from the movie; audio, webcam and telemetry stay aligned.
- **Draw on screen** — [[⌃⌘D]] toggles a drawing layer. Drag to draw; a small palette picks colour and width. Strokes are captured in the video, the palette is not. [[Esc]] stops drawing, [[C]] clears, [[⌘Z]] undoes a stroke.
- **Stop** — [[⌃⌘R]] again, the menu, or click the menu-bar icon. Quitting Dolly mid-recording stops and finalises the file first.
- **Auto-stop** — Settings → General → *Stop recording automatically after* 5, 15, 30 or 60 minutes.

## Quality and audio

![Recording settings](/shots/settings-recording.png "Settings → Recording: frame rate, quality, microphone, webcam.")

- **Video** is HEVC (H.265) at 30 or 60 fps. *Balanced* targets small files, *High* is the default, *Maximum* is near-lossless.
- **System audio** is always recorded. **Microphone** is added when *Include microphone* is on (menu bar or Settings → Recording).
- **Webcam** is saved as a separate movie (`…webcam.mov`) beside the recording and composited as picture-in-picture when you polish. A live preview window shows the camera while recording.

## Files

Recordings are saved to `~/Movies/Screen Recordings` as `Recording <date> at <time>.mov`. Change the folder in Settings → General → Files. Each recording may have sidecars: `.telemetry.json` (always), `.webcam.mov` (if enabled) and `… (polished).mov` after Auto-Zoom. Rename, trim and delete in the dashboard keep the sidecars together.
