#!/bin/bash
# Builds build/Super Notes.app (release by default; `--debug` for a fast debug build; UNIVERSAL=1 for Apple silicon
# + Intel) and signs it with the project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
# The llama.cpp framework (a SwiftPM binary target) is embedded in Contents/Frameworks, the executable gets the
# matching rpath, and every nested piece is signed before the bundle that seals it.
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
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/SuperNotes" "$APP/Contents/MacOS/SuperNotes"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM resource bundles (ExtensionsKit ships its bundled JavaScript extensions this way).
find "$RES_BIN" -maxdepth 1 -name 'SuperNotes_*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

# The on-device AI engine: the macOS slice of the llama.cpp xcframework SwiftPM downloaded (a universal dynamic
# framework with Metal embedded).
FRAMEWORKS=()
for name in llama; do
  SLICE="$(find "$ROOT/.build/artifacts" -type d -path "*/$name.xcframework/macos-*" -name "$name.framework" | head -1)"
  [ -n "$SLICE" ] || { echo "Missing $name.framework in .build/artifacts; run swift build first" >&2; exit 1; }
  # cp -R keeps the Versions/Current symlink layout; dSYMs stay out of the bundle.
  cp -R "$SLICE" "$APP/Contents/Frameworks/$name.framework"
  FRAMEWORKS+=("$APP/Contents/Frameworks/$name.framework")
done
# The framework's install name is @rpath/llama.framework/Versions/Current/llama; SwiftPM linked the executable
# against the artifact folder, so replace that rpath with the bundle's.
EXE="$APP/Contents/MacOS/SuperNotes"
while IFS= read -r rpath; do
  [ -n "$rpath" ] && install_name_tool -delete_rpath "$rpath" "$EXE" 2>/dev/null || true
done < <(otool -l "$EXE" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -F ".build/" || true)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"

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
  # Nested code first (the framework), then the bundle that seals it; resource bundles are data the seal covers.
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s "Super Notes Local Signing" --keychain "$KC" -o runtime "$fw"; done
  codesign -f -s "Super Notes Local Signing" --keychain "$KC" -o runtime --entitlements "$ENT" "$APP"
  restore; trap - EXIT
else
  for fw in "${FRAMEWORKS[@]}"; do codesign -f -s - "$fw"; done
  codesign -f -s - --entitlements "$ENT" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP"
