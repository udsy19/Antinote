# Contributing to Super Notes

Thanks for helping make Super Notes better! Bug reports, feature ideas, extensions, docs and code are all welcome.

## Getting started

```sh
git clone https://github.com/udsy19/super-notes.git && cd super-notes
./scripts/signing-setup.sh      # once: local signing identity so Keychain access survives rebuilds
./scripts/build-app.sh --debug  # → build/Super Notes.app
open "build/Super Notes.app"
```

You only need macOS 14+ and the Swift toolchain from the Command Line Tools (`xcode-select --install`).
Xcode is optional.

## Before you open a pull request

1. `swift build` compiles with **no warnings**.
2. `swift run SuperNotesSelfTest` passes. Add cases for new logic in `Sources/SuperNotesSelfTest/<Module>Tests.swift`.
3. For UI changes, include a screenshot or a short recording.
4. Follow the conventions in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): modules depend only on `SuperNotesCore` and
   talk through `Services`, notes stay plain text, settings use typed `Defaults` keys, no third-party dependencies.
5. Anything that touches the network gets its own switch in **Settings → Privacy**. It stays off by default unless the app depends on it (currency rates and automatic updates start on; say so in PRIVACY.md).
6. Keep changes focused and remove any code your change makes obsolete.

## Writing an extension

An extension is a folder with an `extension.json` manifest and an `index.js`. The bundled ones in
`Sources/ExtensionsKit/Bundled/` are small, readable examples. Drop a folder into
`~/Library/Application Support/Super Notes/Extensions` and choose **Reload** in **Settings → Extensions** to try it.
Declare every endpoint you call and the smallest `dataScope` that works.

## Reporting bugs

Open an [issue](https://github.com/udsy19/super-notes/issues/new/choose) with your Super Notes and macOS versions, your Mac
(Apple silicon or Intel), the note text that triggers the problem (if you can share it), steps to reproduce and what
you expected. Logs are in Console.app (filter by `com.udsy.supernotes`).

## Code of conduct

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
