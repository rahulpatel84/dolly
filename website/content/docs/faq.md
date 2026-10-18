# FAQ

## Is Dolly free?

Yes. Dolly is free and open source; the code is on [GitHub](https://github.com/rahulpatel84/dolly). There is no trial, no watermark, no account.

## Does anything leave my Mac?

No. Dolly has no network code. Recordings, screenshots and the telemetry sidecar stay in your recordings folder. Sharing goes through the macOS share sheet to apps you choose.

## Why does macOS warn me on first launch?

Dolly is signed but not notarised with Apple, so Gatekeeper asks you to confirm once via System Settings → Privacy & Security → **Open Anyway**. Building from source avoids the dialog entirely.

## Which Macs are supported?

macOS 14 Sonoma or newer on Apple silicon or Intel. Microphone capture through the native pipeline needs macOS 15.

## Is there a Windows version?

A Windows port (Windows Graphics Capture, WASAPI, the same Auto-Zoom planner in C#) compiles but has not been released. Follow the repository for progress.

## Can I re-polish an old recording with different settings?

Yes. Effects are never burned into the original; Auto-Zoom reads the telemetry sidecar each time. Change the settings and click **Re-polish**.

## Does Dolly record scrolling screenshots or show keystrokes?

Not yet. Both are on the list; see the [comparison](/compare) for an honest view of what others offer.

## Where are my files?

`~/Movies/Screen Recordings` by default. Change it in Settings → General → Files. Each recording has a `.telemetry.json` beside it and, after polishing, a `(polished).mov`.
