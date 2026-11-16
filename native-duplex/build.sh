#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache
ARCH=$(uname -m)
xcrun clang -target "$ARCH-apple-macos13.0" -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations filter.c -lcups -o build/hp1020duplex
xcrun clang -target "$ARCH-apple-macos13.0" -std=c11 -Wall -Wextra -Werror queue-state.c -lcups -o build/queue-state
APP="build/HP1020 Duplex Agent.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -module-cache-path build/module-cache -target "$ARCH-apple-macosx13.0" -Onone Agent.swift -framework AppKit -o "$APP/Contents/MacOS/HP1020DuplexAgent"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HP1020DuplexAgent</string>
<key>CFBundleIdentifier</key><string>community.hp1020.duplex.agent</string>
<key>CFBundleName</key><string>HP1020 Duplex Agent</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
python3 make_ppd.py
printf 'Built native filter, confirmation agent and PPD.\n'
