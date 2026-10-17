#!/bin/bash
# Produces dist/SuperNotes-<version>.dmg: universal (Apple silicon + Intel) app, drag-to-Applications layout,
# and install notes for Gatekeeper (the app is self-signed, not notarized).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

UNIVERSAL=1 ./scripts/build-app.sh

STAGE="$ROOT/build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "build/Super Notes.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install Super Notes.txt" <<TXT
Installing Super Notes $VERSION
=============================

1. Drag Super Notes into the Applications folder.
2. Open Super Notes from Applications. macOS will say it "cannot be opened" because the app
   is not notarized by Apple. Click Done.
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway" next to
   the Super Notes message, then confirm with your password.
   (Alternatively, in Terminal: xattr -dr com.apple.quarantine "/Applications/Super Notes.app")
4. Super Notes opens with a short tutorial note. Press Option-A anywhere to show or hide it.

Requirements: macOS 14 Sonoma or later, Apple silicon or Intel.
TXT

mkdir -p dist
DMG="dist/SuperNotes-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "Super Notes $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
