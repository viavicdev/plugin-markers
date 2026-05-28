#!/bin/bash
# Bygger RENDER Markers Oppdaterer.app — Patch 1
set -e
cd "$(dirname "$0")"

APP="RENDER Markers Oppdaterer.app"
BIN="RenderMarkersOppdaterer"

echo "▸ Rydder gammel build..."
rm -rf "$APP"

echo "▸ Kompilerer SwiftUI..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/$BIN" main.swift

echo "▸ Bundler Premiere-plugin..."
mkdir -p "$APP/Contents/Resources/extension"
cp -R ../dist/unpacked/RENDER-Suite/extension/com.render.teamsmc2 \
      "$APP/Contents/Resources/extension/com.render.teamsmc2"

echo "▸ Bundler TeamsToCSV.app..."
cp -R ../TeamsToCSV/TeamsToCSV.app "$APP/Contents/Resources/TeamsToCSV.app"

echo "▸ Writing Info.plist..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundleIdentifier</key><string>no.ensamble.render-markers-oppdaterer</string>
    <key>CFBundleName</key><string>RENDER Markers Oppdaterer</string>
    <key>CFBundleDisplayName</key><string>RENDER Markers Oppdaterer</string>
    <key>CFBundleVersion</key><string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signerer..."
codesign --force --deep --sign - "$APP" 2>&1 | tail -1

echo ""
echo "✓ Ferdig: $(pwd)/$APP"
