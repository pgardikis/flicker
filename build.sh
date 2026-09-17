#!/bin/bash
# Builds Battery Notify.app. Pass --install to copy it to /Applications and launch it.
set -e

cd "$(dirname "$0")"
BUILD=build
APP="$BUILD/Battery Notify.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/BatteryNotify"

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

if [ "$1" = "--install" ]; then
  INSTALLED="/Applications/Battery Notify.app"

  # Quit the old instance and wait for it to exit (force quit after 5s)
  pkill -x BatteryNotify 2>/dev/null || true
  for _ in $(seq 25); do pgrep -x BatteryNotify >/dev/null || break; sleep 0.2; done
  pkill -9 -x BatteryNotify 2>/dev/null || true

  rm -rf "$INSTALLED"
  cp -R "$APP" /Applications/

  # Launch Services may need a moment to register the new copy (error -600), so retry
  for attempt in 1 2 3 4 5; do
    if open "$INSTALLED" 2>/dev/null && sleep 1 && pgrep -x BatteryNotify >/dev/null; then
      echo "Installed to /Applications and launched"
      exit 0
    fi
    sleep 1
  done
  echo "Installed to /Applications, but launching failed. Open it manually from Applications." >&2
  exit 1
fi
