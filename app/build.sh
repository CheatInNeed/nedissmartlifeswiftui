#!/bin/bash
# Builds build/LampBar.app and installs lamp.py + its Python venv under ~/.local/share/lamp.
# Requires Xcode (its swiftc ships the SwiftUI macro plugin that Command Line Tools alone lack).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
APP="$REPO/build/LampBar.app"
LAMPDIR="$HOME/.local/share/lamp"
PYTHON="${PYTHON:-python3}"

# Prefer /Applications/Xcode.app; otherwise use whatever xcode-select points at.
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --find swiftc >/dev/null 2>&1 || { echo "Xcode not found. Install it from the App Store." >&2; exit 1; }
SDK="$(xcrun --sdk macosx --show-sdk-path)"

# 1) Install lamp.py and a venv with tinytuya (the app calls them from this fixed path).
mkdir -p "$LAMPDIR"
cp "$REPO/lamp.py" "$LAMPDIR/lamp.py"
if [ ! -x "$LAMPDIR/venv/bin/python3" ]; then
  "$PYTHON" -m venv "$LAMPDIR/venv"
  "$LAMPDIR/venv/bin/pip" install --quiet -r "$REPO/requirements.txt"
fi
[ -f "$HOME/.config/lamp/config.json" ] || echo "Note: ~/.config/lamp/config.json is missing - see README step 3." >&2

# 2) Build the app bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LampBar</string>
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

xcrun swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -O -swift-version 5 -parse-as-library \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/LampBar" LampBar.swift

# 3) Ad-hoc signature (required to run on Apple Silicon and to register as a login item).
codesign --force --deep -s - "$APP" >/dev/null

echo "Built: $APP"
