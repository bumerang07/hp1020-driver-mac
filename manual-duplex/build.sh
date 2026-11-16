#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="build/HP1020 Manual Duplex.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -module-cache-path build/module-cache -target "$(uname -m)-apple-macosx13.0" -Onone -framework AppKit -framework PDFKit main.swift -o "$APP/Contents/MacOS/HP1020ManualDuplex"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HP1020ManualDuplex</string>
<key>CFBundleIdentifier</key><string>community.hp1020.manualduplex</string>
<key>CFBundleName</key><string>HP1020 Manual Duplex</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built: %s\n' "$PWD/$APP"
