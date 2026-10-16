# Dolly

**The screen recorder that follows you.** Developed by Rahul Patel.

Dolly records a clean stream plus a cursor-telemetry sidecar, then applies zoom,
cursor framing, click emphasis, webcam picture-in-picture and silence removal
*afterwards* — nothing is burned into the pixels, so any recording can be
re-polished. It also has a screenshot editor with OCR, blur, numbered steps,
pin-to-screen and configurable hotkeys.

| Folder | What | Status |
|---|---|---|
| [`ScreenRecorder/`](ScreenRecorder) | The macOS app (Swift, ScreenCaptureKit, AVFoundation, CoreImage) | Shipping — `build.sh --release` |
| [`Windows/`](Windows) | C# polish engine (tested) + Windows capture app (compiles, not yet run on Windows) | In progress |
| [`website/`](website) | Next.js site with light/dark theme, deployed on Vercel | [screen-recorder-site.vercel.app](https://screen-recorder-site.vercel.app) |

**Download:** see [Releases](../../releases) for the latest `Dolly-x.y.z.dmg`.
**Install guide:** [ScreenRecorder/INSTALL.md](ScreenRecorder/INSTALL.md).

macOS 14 Sonoma or later · Apple Silicon and Intel · MIT-style use as you see fit.
