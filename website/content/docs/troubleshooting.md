# Troubleshooting

## The recording is black or empty

Screen Recording permission is missing or was granted to a previous copy of the app. Choose **Help → Grant Screen Recording Permission…**, make sure **Dolly** is on, then **quit and reopen Dolly**. See [Permissions](/docs/permissions).

## No microphone in the recording

Turn on *Include microphone* (menu bar or Settings → Recording) and accept the Microphone prompt. If you declined once, enable it in System Settings → Privacy & Security → Microphone. Native microphone capture needs macOS 15 or newer.

## The webcam is not listed

Another app is probably using the camera. Close it and reopen Settings → Recording. Check System Settings → Privacy & Security → Camera.

## A hotkey does nothing

Open Settings → Hotkeys. An orange field means macOS or another app owns that combination — choose another. If a field will not record a new combination, press [[Esc]] and try again; Dolly pauses its own shortcuts while listening.

## The editor looks soft

You are zoomed past 100 %. Click the zoom percentage and choose *100 %* to see native pixels. The preview itself is always the full-resolution image (down-sampled only above 4096 px wide).

## Files are large

For video, use **Export → MP4, compressed H.264 1080p**, or set *Export resolution* in Auto-Zoom to 1080p. For screenshots, **Export → HEIC** or **WebP** at 70–85 % quality is typically a quarter of the PNG size.

## A recording stopped by itself

If the capture stream is interrupted (display disconnected, system sleep), Dolly finalises what it has so the file stays playable, and notes the reason in `~/Library/Logs/ScreenRecorder.log`.

## Two copies of Dolly

Dolly refuses to run twice and explains why. If you see a stale icon in Launchpad or the Dock after moving the app, run the installed copy once from `/Applications`; it re-registers itself.

## Getting help

Open an issue at <https://github.com/rahulpatel84/dolly/issues> with your macOS version, the Dolly version (About Dolly) and the relevant lines from `~/Library/Logs/ScreenRecorder.log`.
