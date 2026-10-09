#!/bin/bash
# Copyright (C) 2026 Nabhak. SPDX-License-Identifier: GPL-3.0-or-later
# Build ~/Applications/Momo Hop.app from main.swift (ad-hoc signed).
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Momo Hop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP="$(mktemp -d)"
for arch in arm64 x86_64; do
  swiftc -parse-as-library -O -target "$arch-apple-macos14.0" -o "$TMP/cp-$arch" main.swift
done
lipo -create "$TMP/cp-arm64" "$TMP/cp-x86_64" -output "$APP/Contents/MacOS/MomoHop"
rm -rf "$TMP"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MomoHop</string>
<key>CFBundleIdentifier</key><string>io.github.nabhak.momo-hop</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Momo Hop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Nabhak. GPL-3.0-or-later.</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Opens the project you pick in a new Ghostty tab.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Lists the project folders in your Documents folder.</string>
<key>NSDesktopFolderUsageDescription</key><string>Lists project folders you added on your Desktop.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Lists project folders you added on external drives.</string>
</dict></plist>
PL
codesign --force --sign - "$APP" >/dev/null 2>&1
mkdir -p dist && rm -f dist/Momo-Hop.zip
ditto -c -k --keepParent "$APP" dist/Momo-Hop.zip
echo "built $APP  +  dist/Momo-Hop.zip (universal arm64+x86_64)"
