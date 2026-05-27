#!/bin/bash
# Bygger RENDER Suite Installer.app
set -e
cd "$(dirname "$0")"

APP="RENDER Suite Installer.app"
BIN="RenderSuiteInstaller"

echo "▸ Rydder gammel build..."
rm -rf "$APP"

echo "▸ Kopierer animasjoner til Resources..."
mkdir -p Resources/animation
cp ../assets/animation/clapper.html  Resources/animation/clapper.html
cp ../assets/animation/timeline.html Resources/animation/timeline.html

echo "▸ Kompilerer SwiftUI-app..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/$BIN" main.swift

echo "▸ Bundler animasjoner..."
cp Resources/animation/clapper.html  "$APP/Contents/Resources/clapper.html"
cp Resources/animation/timeline.html "$APP/Contents/Resources/timeline.html"

echo "▸ Bundler Premiere-plugin..."
mkdir -p "$APP/Contents/Resources/extension"
cp -R ../dist/unpacked/RENDER-Suite/extension/com.render.teamsmc2 \
      "$APP/Contents/Resources/extension/com.render.teamsmc2"

echo "▸ Bundler TeamsToCSV.app..."
cp -R ../TeamsToCSV/TeamsToCSV.app "$APP/Contents/Resources/TeamsToCSV.app"

echo "▸ Skriver Info.plist..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BIN</string>
    <key>CFBundleIdentifier</key>
    <string>no.ensamble.render-suite-installer</string>
    <key>CFBundleName</key>
    <string>RENDER Suite Installer</string>
    <key>CFBundleDisplayName</key>
    <string>RENDER Suite Installer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signerer..."
codesign --force --deep --sign - "$APP" 2>&1 | tail -1

echo ""
echo "✓ Ferdig: $(pwd)/$APP"
echo "  Åpne med: open '$(pwd)/$APP'"
