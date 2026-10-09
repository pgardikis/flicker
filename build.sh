#!/bin/bash
# Builds Flicker.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")"
BUILD=build
APP="$BUILD/Flicker.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling (universal: arm64 + x86_64)..."
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 6 -target "$arch-apple-macos14.0" \
    Sources/*.swift -o "$BUILD/Flicker-$arch"
done
lipo -create "$BUILD/Flicker-arm64" "$BUILD/Flicker-x86_64" \
  -output "$APP/Contents/MacOS/Flicker"
rm -f "$BUILD/Flicker-arm64" "$BUILD/Flicker-x86_64"

echo "Making icon..."
swiftc -O make-icon.swift -o "$BUILD/make-icon"
rm -rf "$BUILD/AppIcon.iconset"
"$BUILD/make-icon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: required for notifications and launch at login to work.
# Hardened runtime blocks code injection into the running app.
codesign --force --options runtime --sign - "$APP"

echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  INSTALLED="/Applications/Flicker.app"
  # Match the installed copy by its path, not any process that happens to be named Flicker
  RUNNING="^$INSTALLED/Contents/MacOS/Flicker"

  # Quit the old instance and wait for it to exit (force quit after 5s)
  pkill -f "$RUNNING" 2>/dev/null || true
  for _ in $(seq 25); do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.2; done
  pkill -9 -f "$RUNNING" 2>/dev/null || true

  rm -rf "$INSTALLED"
  cp -R "$APP" /Applications/

  # Launch Services may need a moment to register the new copy (error -600), so retry
  for attempt in 1 2 3 4 5; do
    if open "$INSTALLED" 2>/dev/null && sleep 1 && pgrep -f "$RUNNING" >/dev/null; then
      echo "Installed to /Applications and launched"
      exit 0
    fi
    sleep 1
  done
  echo "Installed to /Applications, but launching failed. Open it manually from Applications." >&2
  exit 1
fi
