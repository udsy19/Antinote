#!/bin/bash
# Builds the universal DMG and publishes it as a GitHub release.
#   ./scripts/release.sh 1.0.1
# The asset is uploaded twice: "SuperNotes-<version>.dmg" and a stable "SuperNotes.dmg", which the one-line installer
# and the website download from (https://github.com/<repo>/releases/latest/download/SuperNotes.dmg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION="${1:?usage: release.sh <version>}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(git rev-list --count HEAD) + 1 )); /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
git add Resources/Info.plist
git diff --cached --quiet || git commit -q -m "Release $VERSION"
git push -q origin HEAD
./scripts/make-dmg.sh
cp "dist/SuperNotes-$VERSION.dmg" dist/SuperNotes.dmg
SHA=$(shasum -a 256 dist/SuperNotes.dmg | cut -d' ' -f1)
NOTES=$(awk -v v="$VERSION" '$0 ~ "^## \\["v"\\]" {f=1; next} /^## \[/ {f=0} f' CHANGELOG.md)
git tag -s "v$VERSION" -m "Super Notes $VERSION" 2>/dev/null || git tag "v$VERSION" -m "Super Notes $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "dist/SuperNotes-$VERSION.dmg" dist/SuperNotes.dmg --title "Super Notes $VERSION" \
  --notes "$NOTES

**Install:** \`curl -fsSL https://udsy19.github.io/super-notes/install.sh | bash\` — or download the DMG below.

SHA-256 (SuperNotes.dmg): \`$SHA\`"
