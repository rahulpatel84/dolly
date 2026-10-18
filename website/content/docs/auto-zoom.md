# Auto-Zoom polish

^ Auto-Zoom turns a raw recording into a presentation-ready video. The camera glides toward where you click and type, the cursor gets a soft halo, clicks ripple, silences are cut, and the whole thing can sit on a gradient with rounded corners and a shadow.

![A polished export with the Midnight background](/shots/styled-export.png "A polished frame: background padding, rounded corners, shadow.")

## Run it

In the dashboard, select a recording and click **Auto-Zoom** in the inspector — or **Auto-Zoom All** in the toolbar to polish everything that has not been polished yet. Progress is shown on the recording. The result is saved beside the original as `<name> (polished).mov`; the original is never changed, so you can re-polish with different settings any time. **Play Polished** previews it; **Export** offers *Original* or *Polished* as the source.

## Tune it

![Auto-Zoom settings](/shots/settings-polish.png "Settings → Auto-Zoom.")

| Setting | Effect |
|---|---|
| **Preset** | *Subtle*, *Balanced* or *Dramatic* set strength and smoothing together. |
| **Zoom strength** | How far the camera pushes in, 1.3× to 3×. |
| **Smoothing** | Seconds the camera takes to settle, 0.5–3 s. Higher is calmer. |
| **Highlight cursor** | Soft halo around the pointer and expanding rings on clicks. |
| **Remove silences** | Cuts stretches quieter than the threshold (default −45 dB) that last longer than the minimum (default 1.2 s), keeping 0.25 s of padding around speech. |
| **Background** | *None*, *Gradient* or *Solid*: pads the video on a canvas with rounded corners and shadow. |
| **Export resolution** | Keep the source size, or scale to 1080p, 1440p or 4K. |

## How the camera decides where to look

The telemetry sidecar records the cursor 60 times a second and marks clicks. The planner groups activity into *focus windows*, ignores idle drift, and only moves the camera when attention has clearly shifted — so a video of you reading does not swim around. Clicks pull the camera in; long pauses let it ease back out. The webcam movie, if present, is placed as a rounded picture-in-picture in the lower right.

## Performance

Rendering uses a shared Metal-backed CoreImage context with the static frame layers cached once per export. On Apple silicon a one-minute clip takes about a minute; silence removal adds a lossless second pass. You can keep using Dolly while it renders.
