#!/bin/bash
# Builds ScreenRecorder.app from the Swift package.
#
# The app is assembled by hand rather than via an Xcode project so the whole
# build is reproducible from the command line.
set -euo pipefail

cd "$(dirname "$0")"

# Brand: see Sources/ScreenRecorder/Brand.swift
APP_NAME="Dolly"
EXEC_NAME="ScreenRecorder"            # SwiftPM product name; the bundle executable is renamed below
BUNDLE_ID="com.rahulpatel.dolly"
APP="build.noindex/${APP_NAME}.app"
VERSION="0.2.1"
DEVELOPER="Rahul Patel"
VOLNAME="Dolly"

echo "==> Compiling"
swift build -c release

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# build.noindex: the .noindex suffix keeps the dev copy out of Spotlight and
# the Apps view, so only the installed copy in /Applications shows in search.
cp ".build/release/${EXEC_NAME}" "$APP/Contents/MacOS/${APP_NAME}"

# App icon. Regenerate from source if the .icns is missing.
if [ ! -f Icon/AppIcon.icns ] || [ ! -f Icon/MenuBarIcon@2x.png ]; then
    echo "==> Generating app icon"
    ( cd Icon && swiftc -O -o makeicon makeicon.swift && ./makeicon >/dev/null \
      && iconutil -c icns AppIcon.iconset -o AppIcon.icns )
fi
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Icon/MenuBarIcon.png Icon/MenuBarIcon@2x.png "$APP/Contents/Resources/"
cp INSTALL.md "$APP/Contents/Resources/Install Guide.md"
cp GUIDE.md "$APP/Contents/Resources/User Guide.md"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>           <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>            <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>            <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>${VERSION}</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>NSHumanReadableCopyright</key>      <string>Developed by ${DEVELOPER}</string>

    <!-- Regular app with a Dock icon and menu bar; the status-bar icon is a shortcut. -->
    <key>LSUIElement</key>                   <false/>

    <!-- Required, or macOS kills the app the moment it touches the mic or camera. -->
    <key>NSMicrophoneUsageDescription</key>
    <string>${APP_NAME} records your microphone when you enable it for a recording.</string>
    <key>NSCameraUsageDescription</key>
    <string>${APP_NAME} records your webcam when you enable it, as a separate file or picture-in-picture.</string>
</dict>
</plist>
PLIST

# Signing. macOS binds Screen Recording permission to the signing identity:
# with the local "ScreenRecorder Local Dev" certificate the identity is stable
# across rebuilds and the grant survives. Ad-hoc signatures change with every
# build (the identity is the binary's own hash), so the grant is lost each time.
IDENTITY="ScreenRecorder Local Dev"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "==> Signing with $IDENTITY (permission survives rebuilds)"
    codesign --force --deep --sign "$IDENTITY" "$APP"
    SIGNED_STABLE=1
else
    echo "==> Signing (ad-hoc; permission will reset on every rebuild)"
    codesign --force --deep --sign - "$APP"
    SIGNED_STABLE=0
fi

# The installed copy is the one that should appear in Spotlight / the Apps view.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$(pwd)/$APP" >/dev/null 2>&1 || true

echo "==> Verifying"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
# Each build produces a new ad-hoc cdhash, and macOS binds Screen Recording
# permission to that hash. Without this reset the app looks approved in System
# Settings but is silently denied. Resetting makes it prompt again instead.
if [ "$SIGNED_STABLE" = "0" ]; then
    echo "==> Resetting Screen Recording permission (ad-hoc signature changed)"
    tccutil reset ScreenCapture "${BUNDLE_ID}" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Disk image. Staged in a temp folder with an /Applications symlink so the
# usual drag-to-install gesture works.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--dmg" ] || [ "${1:-}" = "--release" ]; then
    echo "==> Building disk image"
    DMG="dist/${APP_NAME}-${VERSION}.dmg"
    STAGE="$(mktemp -d)"
    mkdir -p dist
    rm -f "$DMG"

    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp INSTALL.md "$STAGE/Install Guide.md"
    cp GUIDE.md "$STAGE/User Guide.md"

    hdiutil create \
        -volname "$VOLNAME" \
        -srcfolder "$STAGE" \
        -ov -format UDZO \
        -quiet \
        "$DMG"

    rm -rf "$STAGE"
    echo "    $(pwd)/${DMG}  ($(du -h "$DMG" | cut -f1))"
fi

# ---------------------------------------------------------------------------
# Install. Running from the build folder or a mounted disk image both cause
# problems: the app refuses to launch from a disk image, and permission is
# bound to the location, so a stable home matters.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--install" ] || [ "${1:-}" = "--release" ]; then
    echo "==> Installing to /Applications"
    osascript -e 'quit app "ScreenRecorder"' 2>/dev/null || true
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
    sleep 1
    # The app used to be called ScreenRecorder; never leave two copies behind.
    rm -rf "/Applications/ScreenRecorder.app" "/Applications/${APP_NAME}.app"
    cp -R "$APP" "/Applications/${APP_NAME}.app"
    echo "    /Applications/${APP_NAME}.app"
fi

echo
echo "Built: $(pwd)/${APP}"
echo "cdhash: $(codesign -dv --verbose=2 "$APP" 2>&1 | grep -o 'CDHash=.*' || echo 'n/a')"
echo
echo "Grant Screen Recording when prompted, then run:"
echo "  open -a \"$(pwd)/${APP}\" --args --record 5"
