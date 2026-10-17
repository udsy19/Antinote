#!/bin/bash
# Builds build/Super Notes.app (release by default; `--debug` for a fast debug build) and signs it with the
# project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CONFIG=release; [ "${1:-}" = "--debug" ] && CONFIG=debug
if [ "${UNIVERSAL:-0}" = 1 ]; then
  # Build each architecture separately (the CLT toolchain has no multi-arch build) and merge with lipo.
  for arch in arm64 x86_64; do swift build -c "$CONFIG" --product SuperNotes --triple "$arch-apple-macosx14.0"; done
  RES_BIN="$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)"
  BIN="$ROOT/build/universal"; mkdir -p "$BIN"
  lipo -create -output "$BIN/SuperNotes" "$(swift build -c "$CONFIG" --triple arm64-apple-macosx14.0 --show-bin-path)/SuperNotes" "$(swift build -c "$CONFIG" --triple x86_64-apple-macosx14.0 --show-bin-path)/SuperNotes"
else
  swift build -c "$CONFIG" --product SuperNotes
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"; RES_BIN="$BIN"
fi

APP="$ROOT/build/Super Notes.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SuperNotes" "$APP/Contents/MacOS/SuperNotes"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM resource bundles (ExtensionsKit ships its bundled JavaScript extensions this way).
find "$RES_BIN" -maxdepth 1 -name 'SuperNotes_*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

ICONSET="$ROOT/build/AppIcon.iconset"
if [ ! -f "$ROOT/build/AppIcon.icns" ]; then
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET" && iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

KC="$ROOT/.signing/supernotes.keychain-db"
ENT="$ROOT/Resources/SuperNotes.entitlements"
if [ -f "$KC" ]; then
  security unlock-keychain -p supernotes "$KC"
  ORIG=()
  while IFS= read -r line; do line="${line#"${line%%[![:space:]]*}"}"; line="${line//\"/}"; [ -n "$line" ] && ORIG+=("$line"); done < <(security list-keychains -d user)
  restore() { security list-keychains -d user -s "${ORIG[@]}"; }
  trap restore EXIT
  security list-keychains -d user -s "${ORIG[@]}" "$KC"
  codesign -f -s "Super Notes Local Signing" --keychain "$KC" -o runtime --entitlements "$ENT" "$APP"
  restore; trap - EXIT
else
  codesign -f -s - --entitlements "$ENT" "$APP"
fi
echo "Built $APP"
