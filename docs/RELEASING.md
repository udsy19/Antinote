# Releasing

```bash
./scripts/release.sh 1.3.0
```

The script sets the version in `Resources/Info.plist`, commits and pushes, builds the universal DMG, tags `v1.3.0` and
creates the GitHub release with the matching `CHANGELOG.md` section as its notes. Add that section
(`## [1.3.0] — <date>`) before running it.

## What installed copies rely on

Every copy of Super Notes updates itself from the latest GitHub release (`UpdateKit`). It reads
`https://api.github.com/repos/udsy19/super-notes/releases/latest` and installs the release only if all of these hold,
so keep them true for every release:

- **The tag is the version.** `tag_name` is `v<version>` and the app's `CFBundleShortVersionString` is the same
  version. release.sh does both; don't retag by hand. Drafts and pre-releases are never offered.
- **The stable asset name.** The DMG is uploaded as `SuperNotes.dmg` (and as `SuperNotes-<version>.dmg`, used only as
  a fallback). The one-line installer and the website download `SuperNotes.dmg` too.
- **The checksum line.** The release notes end with the line release.sh writes:

  ```
  SHA-256 (SuperNotes.dmg): `<64 lowercase hex digits>`
  ```

  Without it, or if it doesn't match the file, copies refuse the update. If you edit the notes on GitHub, keep the
  line. If you replace the DMG after publishing, update the line to the new file's `shasum -a 256`.
- **The DMG holds `Super Notes.app` at its top level**, with bundle id `com.udsy.supernotes`.
- **Never change the signing identity.** Updates must satisfy the running copy's designated requirement
  (`identifier "com.udsy.supernotes" and certificate leaf = H"…"`), which names the certificate in `.signing/`. A
  release signed with any other certificate, or ad-hoc, is rejected by every installed copy, and those copies can
  then only be updated by hand. `.signing/` is not in git: back it up somewhere safe, and build releases on a Mac
  that has it (`scripts/build-app.sh` falls back to ad-hoc signing without it). The certificate is valid until 2036.

## Testing an update locally

Debug builds (`scripts/build-app.sh --debug`) read the feed from `SUPERNOTES_UPDATE_FEED` when it is set, for example a
`releases/latest`-shaped JSON file served from your Mac; release builds always read GitHub. `swift run
SuperNotesSelfTest` runs the whole download → checksum → mount → signature → stage → swap path against
`build/Super Notes.app` in temporary folders. Update steps are logged under the `updates` category
(`log stream --predicate 'subsystem == "com.udsy.supernotes" AND category == "updates"'`); the swap helper writes
`SuperNotes-update.log` in the user's temporary folder.
