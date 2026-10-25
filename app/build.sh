#!/bin/bash
# Bygger LampBar.app med Command Line Tools-swiftc (virker på macOS 26, hvor Xcode 15.1 ikke kan).
# Installerer også lamp.py + venv-sti, som appen kalder.
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
# Byg med Xcode-toolchainen mod macOS 14-SDK'et. Den færdige app kører på macOS 14+ (inkl. 26).
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$REPO/build/LampBar.app"
LAMPDIR="$HOME/.local/share/lamp"

# 1) Installér lamp.py ved siden af venv'et (så appen slipper for den lange OneDrive-sti).
mkdir -p "$LAMPDIR"
cp "$REPO/lamp.py" "$LAMPDIR/lamp.py"
if [ ! -x "$LAMPDIR/venv/bin/python3" ]; then
  echo "ADVARSEL: venv mangler i $LAMPDIR/venv – kør: python3 -m venv $LAMPDIR/venv && $LAMPDIR/venv/bin/pip install tinytuya" >&2
fi

# 2) Byg app-bundlet.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LampBar</string>
  <key>CFBundleDisplayName</key><string>LampBar</string>
  <key>CFBundleIdentifier</key><string>dk.peterroland.lampbar</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>LampBar</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

xcrun swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 -O -swift-version 5 -parse-as-library \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/LampBar" \
  LampBar.swift

# 3) Ad-hoc signering (nødvendigt for SMAppService/menu bar på Apple Silicon).
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

echo "Bygget: $APP"
