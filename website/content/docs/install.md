# Install

^ Dolly ships as a disk image. Installing takes about a minute; the only step that needs attention is granting Screen Recording permission.

:::steps
1. **Download the disk image.** Get `Dolly-0.2.2.dmg` from the [latest GitHub release](https://github.com/rahulpatel84/dolly/releases/latest) or the download button on this site. It is about 1.4 MB.
2. **Open it and drag Dolly to Applications.** The image contains the app, a shortcut to your Applications folder, and both guides. Drag **Dolly.app** onto **Applications**.
3. **Eject the image and launch Dolly from Applications.** If you launch it from Downloads or from the image instead, Dolly offers to move itself — accept. Permissions are tied to the app's location, so it needs a stable home.
4. **Allow the app to open.** Dolly is open source and signed with a developer certificate but not notarised through the App Store, so the first launch shows "Apple could not verify…". Click **Done**, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, then confirm. This is needed once.
5. **Grant Screen Recording.** macOS asks the first time Dolly needs it. Toggle **Dolly** on in **System Settings → Privacy & Security → Screen Recording**, then quit and reopen Dolly once. See [Permissions](/docs/permissions).
6. **Check the dashboard.** Dolly opens its dashboard and adds an icon to the menu bar. Press [[⌃⌘S]] to take your first screenshot.
:::

![The Dolly disk image open in Finder](/shots/install-dmg.png "The disk image: drag Dolly.app onto the Applications shortcut.")

## Updating

Download the new disk image and drag the app over the old one. Settings, hotkeys and your library are kept — they live in your preferences and in `~/Movies/Screen Recordings`, not in the app bundle. Permission survives updates as long as the app stays at the same path and keeps the same signature.

## Building from source

```bash
git clone https://github.com/rahulpatel84/dolly
cd dolly/ScreenRecorder
./build.sh --release        # builds dist/Dolly-<version>.dmg and installs to /Applications
```

Requires Xcode 26 or the Command Line Tools with Swift 6.2. The build script signs with the local certificate "ScreenRecorder Local Dev" if present, otherwise ad hoc.

## Uninstalling

Quit Dolly, drag `/Applications/Dolly.app` to the Trash, and optionally delete `~/Movies/Screen Recordings` and `~/Library/Preferences/com.rahulpatel.dolly.plist`. Remove it from Screen Recording in System Settings if you like a tidy list.
