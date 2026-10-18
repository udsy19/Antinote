# Privacy

**Super Notes is a local app. Your notes never leave your Mac unless you turn on a feature that needs the network.**

## What Super Notes does not do

- **No accounts.** There is nothing to sign up for.
- **No analytics or telemetry.** Super Notes never tracks usage or sends crash reports. The only routine request is
  the update check, which asks GitHub for the latest release and sends nothing about you.
- **No servers.** The project doesn't operate any; there is nowhere for your notes to go.

## Every network call has its own switch

**Settings → Privacy → Allow these network calls** lists everything that can reach the network. Each switch is the
only way the feature next to it goes online, and **Turn Everything Off** flips them all at once. With every switch
off, Super Notes works fully offline.

| Switch | Default | What it calls | What is sent |
|---|---|---|---|
| Currency rates | **On** | `open.er-api.com` (fiat) and CoinGecko (crypto), at most once a day | A plain request for the latest rates. No note text, no identifiers. |
| Install updates automatically | **On** | `api.github.com` for this project's latest release, every six hours while Super Notes runs and never more often than every four; `github.com` and GitHub's download servers only when a newer version exists | One anonymous HTTPS request with a `SuperNotes/<version>` User-Agent. No cookies, no note text, no identifiers. |
| Download the AI model automatically | **On** | `huggingface.co`, once, for the 1.28 GB on-device model behind `::ask` (see below): a few minutes after launch, only on Wi-Fi or another unmetered connection, never in Low Power Mode, only with 10 GB free | One anonymous HTTPS download, resumed where it stopped. No note text, no identifiers. |
| Extension updates | Off | `raw.githubusercontent.com`, for extensions you installed from GitHub | The extension's repository path |
| Extension APIs | Off | Only the endpoints a community extension declares in its manifest. The built-in AI commands don't use this. | Whatever that command needs, such as the line you asked about, with an API key you stored for that extension. |
| Sync notes | Off | Your own iCloud Drive folder | Notes encrypted on this Mac with AES-GCM before they are written |
| Sync preferences | Off | Your own iCloud Drive folder | Settings, keywords and themes, encrypted the same way |

Currency rates are on out of the box so `$32 USD to JPY =` works on day one. Turning the switch off keeps the last
saved rates, and you can type your own rates in **Settings → Math**.

## Updates

Super Notes keeps itself up to date without asking. A minute after launch, and every six hours while it runs, it asks
GitHub for the latest release of `udsy19/super-notes`. When there is a newer version it downloads `SuperNotes.dmg`
and only uses it if:

- its SHA-256 matches the one published in the release notes,
- the app inside passes a strict code-signature check and is signed with the same identity as the copy you run,
- it is Super Notes (`com.udsy.supernotes`) and the version the release advertises.

The verified copy waits next to the app and goes in when you quit, or sooner when your Mac has been idle for ten
minutes with the Super Notes window hidden or in the background, no timer running and every edit saved: Super Notes
then quits and reopens in the background, on the note you left. The previous version goes to the Trash. Anything
that fails is logged and tried again later; you are never interrupted. If Super Notes can't write to the folder it
lives in, it doesn't update itself.

Turn off **Settings → Privacy → Install updates automatically** to stop the check and the downloads. You can still
update with the one-line installer or the DMG.

## AI commands

`::ask`, `::summarize`, `::rewrite` and `::translate` work out of the box with no account and no API key. **Settings →
AI** picks the engine:

- **On-device model (default).** A small open model (Qwen3.5 2B, Q4_K_M, Apache-2.0; 1.28 GB) that Super Notes
  downloads once from `huggingface.co` in the background and runs on your Mac with llama.cpp. The download is
  verified against a SHA-256 before it is used, lands in `~/Library/Application Support/Super Notes/Models`, and
  is the only network call involved. Prompts and notes never leave your Mac. Until the model has arrived a command
  shows "Getting ready… 40%" and runs on its own when it has.
- **Apple on-device model.** On macOS 26 with Apple Intelligence, Apple's own model, chosen for you where it is
  present. Nothing leaves your Mac.
- **Use an installed command-line tool.** Only if you pick it. Super Notes looks for a supported tool you installed
  yourself (`codex`, `claude` or `gemini` on your PATH or in the usual install folders) and runs it as a separate
  program in its documented non-interactive mode, with the prompt. Whatever you ask then goes wherever that tool
  sends it, under the account you signed in with there. Super Notes never reads the tool's credential files, never
  signs in for you, and shows the tool's name plainly in the picker.

Esc stops an answer that is being written.

## What stays on your Mac

| Data | Location |
|---|---|
| Notes, The Void, archive | `~/Library/Application Support/Super Notes/notes.sqlite` |
| Automatic backups | `~/Library/Application Support/Super Notes/Backups` |
| Extensions you installed | `~/Library/Application Support/Super Notes/Extensions` |
| Custom themes | `~/Library/Application Support/Super Notes/Themes` |
| The downloaded AI model | `~/Library/Application Support/Super Notes/Models` (Settings → AI removes it) |
| Saved exchange rates | `~/Library/Application Support/Super Notes/exchange-rates.json` |
| Settings | `~/Library/Preferences/com.udsy.supernotes.plist` |
| Extension API keys and the sync encryption key | macOS Keychain |

Text recognition from dropped images (Vision), Touch ID for locked notes (LocalAuthentication) and everything else
run on-device using Apple's frameworks.

## Extensions

Extensions are JavaScript that runs inside Super Notes, each in its own JavaScriptCore context. An extension can only
reach the network when **Extension APIs** is on, only at the URLs its manifest declares, and only with an API key you
granted to that extension. Keys are substituted outside the script, so the JavaScript never sees them. Each extension
also declares how much of a note it can read (`none`, the current `line`, or the `full` note), and whether it asks
the AI engine (`usesAI`), which is what the bundled `llm` extension does instead of calling anyone itself.

## Sync

Sync is off until you turn it on. Notes are sealed with a 256-bit key that is generated on your Mac and kept in your
Keychain (iCloud Keychain carries it to your other Macs when available). iCloud Drive only ever stores ciphertext.

## Exports

Apple Notes, Obsidian and Bear exports hand the note to that app on your Mac. Apple Notes export asks macOS for
Automation permission the first time. Markdown, plain text and PDF exports are files you save yourself.

## Removing everything

Run `curl -fsSL https://udsy19.github.io/super-notes/install.sh | bash -s -- --uninstall`, then delete
`~/Library/Application Support/Super Notes` and `~/Library/Preferences/com.udsy.supernotes.plist`. If you used sync, also
delete the `Super Notes` folder in iCloud Drive.
