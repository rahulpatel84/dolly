# Installing Dolly

Developed by Rahul Patel · macOS 14 Sonoma or later · Apple Silicon and Intel

## 1. Install

1. Open `Dolly-0.2.0.dmg`.
2. Drag **ScreenRecorder** onto the **Applications** shortcut in the window.
3. Eject the disk image.
4. Open **Screen Recorder** from Applications, Spotlight, or Launchpad.

If you open it from Downloads instead, the app offers to move itself to
Applications. Say yes: macOS ties the Screen Recording permission to the app's
location, so keeping it in one place means never having to grant it twice.

## 2. First launch: the Gatekeeper warning

This build is signed locally rather than notarised by Apple, so the first launch
shows *"Dolly" cannot be opened because Apple cannot check it for
malicious software.*

- **Right-click** the app → **Open** → **Open** in the dialog. Once.
- Or: System Settings → Privacy & Security → scroll down → **Open Anyway**.

After that it opens normally.

## 3. Grant Screen Recording

On first launch macOS asks for **Screen Recording** permission.

1. Click **Open System Settings** (or go to System Settings → Privacy &
   Security → **Screen & System Audio Recording**).
2. Turn on **Dolly**.
3. **Quit and reopen the app.** macOS does not apply the grant to a running
   process. This step is the one everybody misses.

Microphone and Camera prompts appear only when you first enable those features.

## 4. Record

The app lives in the menu bar (look for the small monitor icon at the top right)
and opens its **Recordings** window on launch.

| Action | Where |
|---|---|
| Record the whole screen | Menu bar → **Record Full Screen**, or **⌃⌘R** |
| Record part of the screen | Menu bar → **Record Area…**, then drag |
| Record one window | Menu bar → **Record Window** → pick it |
| Pause / resume | **⌃⌘P** |
| Stop | Click the menu bar icon → **Stop Recording**, or **⌃⌘R** |
| Screenshot | **⌃⌘S** (saved to disk *and* copied to the clipboard) |
| See all recordings | **⌘R**, or menu bar → **Recordings…** |
| Settings | **⌘,** |

Recordings are saved to `~/Movies/Screen Recordings`.

## 5. Make it look good

In the Recordings window, click **Auto-Zoom** on any recording. The app follows
your cursor, zooms in on what you were doing, highlights clicks, and renders a
polished copy beside the original. The original is never changed, so you can
re-run it with different settings any time.

From the **⋯** menu on each recording: **Trim**, **Rename**, **Export** as MOV /
MP4 / GIF to any folder, **Share** via AirDrop, Messages or Mail, or **Show in
Finder**.

## 6. Uninstall

1. Quit Dolly from the menu bar.
2. Drag `/Applications/Dolly.app` to the Trash.
3. Your recordings stay in `~/Movies/Screen Recordings` — delete that folder if
   you want them gone too.
4. Optional: System Settings → Privacy & Security → Screen & System Audio
   Recording → remove the entry with **–**.

## Troubleshooting

**The menu bar icon is there but recording does nothing.**
Permission was granted but the app was not restarted. Quit and reopen.

**"Recording stopped" appears immediately.**
The Screen Recording entry was removed or the app was moved after permission
was granted. Re-enable it in System Settings and restart the app.

**A recording in the list says "In progress — stop from the menu bar".**
It is still recording. A video file cannot be opened until recording stops.

**Two menu bar icons.**
Two copies are running (for example one from a disk image). The app now refuses
to start a second copy; quit both and open the one in Applications.
