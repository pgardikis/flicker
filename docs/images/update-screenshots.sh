#!/bin/bash
# Re-renders the panel screenshots from the app's own code and rebuilds screenshots.png.
# The Settings window images are real captures of an active window (a window drawn by this
# script would look inactive), so replace settings-light.png and settings-dark.png by hand.
set -e

cd "$(dirname "$0")/../.."
mkdir -p build

# Everything but the app's entry point, plus the renderer, which has its own
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos14.0" \
  -o build/render-panel $(ls Sources/*.swift | grep -v FlickerApp.swift) docs/images/render-panel.swift

# US number formatting, so the cycle count reads 1,054 whatever the Mac's region
build/render-panel docs/images -AppleLocale en_US
swift docs/images/compose.swift
