#!/bin/bash
# Builds TeamsToCSV.app — a SwiftUI drag-and-drop app for OCR-ing
# Teams screenshots into CSV. Requires Xcode command-line tools.

set -e
cd "$(dirname "$0")"

APP="TeamsToCSV.app"
BIN="TeamsToCSV"

echo "▸ Cleaning old build..."
rm -rf "$APP" "$BIN" teams2csv

echo "▸ Generating app icon..."
if [ ! -f AppIcon.icns ] || python3 -c "import PIL" 2>/dev/null; then
    python3 generate_icon.py 2>/dev/null || echo "  (skipping — using existing AppIcon.icns)"
else
    echo "  (using existing AppIcon.icns — PIL not installed)"
fi

echo "▸ Compiling SwiftUI app..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/"
cp ../assets/animation/timeline-bw.html "$APP/Contents/Resources/timeline-bw.html"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/$BIN" main.swift

echo "▸ Writing Info.plist..."
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TeamsToCSV</string>
    <key>CFBundleIdentifier</key>
    <string>no.render.teamstocsv</string>
    <key>CFBundleName</key>
    <string>Teams to CSV</string>
    <key>CFBundleDisplayName</key>
    <string>Teams → CSV</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ Refreshing LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$(pwd)/$APP" 2>/dev/null || true

echo ""
echo "✓ Bygg ferdig: $(pwd)/$APP"
echo "  Åpne med: open '$(pwd)/$APP'"
