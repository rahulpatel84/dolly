# Permissions

^ Dolly asks for exactly what it uses, when it first uses it. Nothing is requested at install time.

| Permission | When it is asked | What it is used for |
|---|---|---|
| **Screen Recording** | First recording or screenshot | Capturing displays and windows through ScreenCaptureKit. Also lets Dolly list window titles for *Record Window* / *Screenshot Window*. |
| **Microphone** | First time *Include microphone* is on | Adding your voice to a recording or an audio-only capture. |
| **Camera** | First time webcam recording is on | The webcam sidecar movie and the picture-in-picture in polished exports. |
| **Accessibility** | Never | Global hotkeys use the Carbon hot-key API, which needs no Accessibility access. |

## Screen Recording

1. Open **System Settings → Privacy & Security → Screen Recording** (or choose **Help → Grant Screen Recording Permission…** in Dolly, which opens the same pane).
2. Turn on **Dolly**. If it is not listed, click **+** and pick `/Applications/Dolly.app`.
3. **Quit and reopen Dolly.** macOS only applies the grant to a freshly launched process. Recordings made before the restart come out black.

> Recent macOS versions ask you to re-confirm screen recording periodically ("Dolly is requesting to bypass the system private window picker"). Click **Continue to Allow**. Dolly uses the system APIs, so this prompt is macOS policy, not a Dolly bug.

## Why permission can be lost

Screen Recording permission is bound to the app's location and code signature. It is lost if Dolly is moved to a different folder, if the bundle is replaced by an unsigned build, or after you click **Reset** in the permission list. Dolly's release builds keep the same signature between versions, so updating by dragging over the old app keeps the grant.

## Microphone and Camera

These behave like any other app: a one-time system prompt, then a toggle in **System Settings → Privacy & Security**. If you declined once, Dolly cannot ask again — flip the switch there. Microphone capture through the native pipeline requires macOS 15 or newer; on macOS 14 the option is hidden.

## What Dolly never does

Dolly has no network code. Nothing is uploaded, no analytics are collected, and the telemetry sidecar (cursor positions) stays beside the recording on your disk. Sharing goes through the macOS share sheet to apps you choose.
