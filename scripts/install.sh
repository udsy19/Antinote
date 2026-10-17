#!/bin/bash
# Super Notes installer.
#
#   Install / update:  curl -fsSL https://udsy19.github.io/super-notes/install.sh | bash
#   Uninstall:         curl -fsSL https://udsy19.github.io/super-notes/install.sh | bash -s -- --uninstall
#
# Downloads the latest release from GitHub, installs it into /Applications (or ~/Applications when /Applications
# isn't writable) and opens it. Nothing else on your system is changed.
# Options (environment): SUPERNOTES_INSTALL_DIR=<folder> to install elsewhere, SUPERNOTES_NO_OPEN=1 to skip launching.
set -euo pipefail

REPO="udsy19/super-notes"
APP="Super Notes.app"
DMG_URL="https://github.com/$REPO/releases/latest/download/SuperNotes.dmg"
# Before 1.2.0 the app was called Jotter. Installing replaces that copy; notes and settings move over on first launch.
OLD_APP="Jotter.app"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
step() { printf '%s→%s %s\n' "$bold" "$reset" "$*"; }
fail() { printf '%s✗ %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

# quit_app <process name> <bundle id> <app name>
quit_app() {
  pgrep -x "$1" >/dev/null 2>&1 || return 0
  step "Quitting the running copy of $3"
  osascript -e "tell application id \"$2\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$1" >/dev/null 2>&1 || break; sleep 0.5; done
  pkill -x "$1" 2>/dev/null || true
}

quit_running() {
  quit_app SuperNotes com.udsy.supernotes "Super Notes"
  quit_app Jotter com.udsy.jotter Jotter
}

# Every installed copy of <app bundle name>, one path per line.
installed_paths() {
  for dir in "/Applications" "$HOME/Applications"; do
    [ -d "$dir/$1" ] && printf '%s\n' "$dir/$1"
  done
  return 0
}

[ "$(uname -s)" = "Darwin" ] || fail "Super Notes runs on macOS only."

if [ "${1:-}" = "--uninstall" ]; then
  paths="$(installed_paths "$APP"; installed_paths "$OLD_APP")"
  [ -n "$paths" ] || fail "Super Notes isn't installed."
  quit_running
  while IFS= read -r path; do
    step "Removing $path"
    rm -rf "$path"
  done <<< "$paths"
  say "${green}✓ Super Notes was uninstalled.${reset}"
  say "${dim}Your notes and settings were kept in ~/Library/Application Support/Super Notes and${reset}"
  say "${dim}~/Library/Preferences/com.udsy.supernotes.plist — delete them to remove everything.${reset}"
  exit 0
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Super Notes needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."

say "${bold}Installing Super Notes${reset} ${dim}— a scratchpad for your Mac${reset}"
tmp="$(mktemp -d -t supernotes-install)"
mnt="$tmp/mount"
cleanup() { hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

step "Downloading the latest release"
curl -fL --progress-bar -o "$tmp/SuperNotes.dmg" "$DMG_URL" || fail "Download failed — check your connection and try again."

step "Verifying the disk image"
hdiutil verify "$tmp/SuperNotes.dmg" -quiet || fail "The download is damaged. Please try again."
mkdir -p "$mnt"
hdiutil attach "$tmp/SuperNotes.dmg" -nobrowse -readonly -mountpoint "$mnt" -quiet || fail "Couldn't open the disk image."
[ -d "$mnt/$APP" ] || fail "The disk image doesn't contain $APP."

dest="${SUPERNOTES_INSTALL_DIR:-/Applications}"
mkdir -p "$dest" 2>/dev/null || true
if [ ! -w "$dest" ]; then
  dest="$HOME/Applications"; mkdir -p "$dest"
fi

[ "${SUPERNOTES_NO_OPEN:-0}" = 1 ] || quit_running
step "Installing to $dest"
rm -rf "$dest/$APP"
ditto "$mnt/$APP" "$dest/$APP"
# Downloads made with curl aren't quarantined; clear the flag anyway in case the image was cached by a browser.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true
while IFS= read -r old; do
  [ -n "$old" ] || continue
  step "Removing the old Jotter app at $old"
  rm -rf "$old"
done <<< "$(installed_paths "$OLD_APP")"

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || echo "")"
if [ "${SUPERNOTES_NO_OPEN:-0}" = 1 ]; then
  say "${green}✓ Super Notes ${version} is installed in $dest.${reset}"
else
  say "${green}✓ Super Notes ${version} is installed.${reset} Opening it now — look for the icon in your menu bar."
  open "$dest/$APP"
fi
