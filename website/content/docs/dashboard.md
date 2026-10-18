# Dashboard

^ The dashboard is Dolly's home window: your library, quick actions, and every operation on a file.

![Dashboard with the inspector open](/shots/dashboard.png "Library, quick actions, and the inspector for the selected recording.")

## Layout

- **Sidebar** — *Recordings*, *Polished*, *Screenshots*, with live counts and total size.
- **Toolbar** — search by name; sort by Newest, Oldest, Longest, Largest or Name; grid or list view; refresh; open the folder in Finder.
- **Quick actions** — Record Screen · Record Area · Screenshot · Screenshot Area · Audio Only · Webcam Only, each showing its hotkey.
- **Inspector** — details for the selected item (date, duration, size, resolution, telemetry stats, sidecars) and its actions.

## Actions

| Action | What it does |
|---|---|
| **Play** / **Play Polished** | Opens Dolly's own player window with standard controls. |
| **Auto-Zoom** / **Re-polish** | Runs the [polish engine](/docs/auto-zoom). |
| **Trim…** | Opens the trimmer (below). |
| **Export ▸** | QuickTime (.mov) · MP4 · MP4 without audio · MP4 compressed to H.264 1080p · Audio only (.m4a) · Animated GIF. Source: *Original* or *Polished*. MOV→MP4 is a container change, no re-encode. |
| **Share** | The macOS share sheet: AirDrop, Messages, Mail, Notes, any app that accepts files. |
| **Edit** (screenshots) | Opens the [editor](/docs/editor). |
| **Copy Image** · **Copy Path** · **Show in Finder** · **Open** | Clipboard and Finder helpers. |
| **Rename…** | Renames the recording and all its sidecars together. |
| **Pin on Screen** (screenshots) | Floats the image above every window. |
| **Move to Trash** | Trashes the file and its sidecars, after confirmation. |

## Player

![Player window](/shots/player.png "The player opens in its own window sized to the video.")

## Trimmer

![Trim window](/shots/trim.png "Trim: drag the handles or type times, then keep or remove the selection.")

Drag the two handles (or type times) to select a range, choose **Keep selection** or **Remove selection**, preview, then **Trim**. The result is saved as a new file; the telemetry sidecar is cut to match, so Auto-Zoom still lines up afterwards.

## Screenshots in the library

![Screenshots section](/shots/dashboard-screenshots.png "Screenshots show as thumbnails with their pixel size.")

Screenshots taken by Dolly appear under *Screenshots*. Select one to copy, edit, pin, share or delete it.
