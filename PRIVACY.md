# Privacy

**Jotter is a local app. Your notes never leave your Mac unless you turn on a feature that needs the network.**

## What Jotter does not do

- **No accounts.** There is nothing to sign up for.
- **No analytics or telemetry.** Jotter never phones home, tracks usage or sends crash reports.
- **No servers.** The project doesn't operate any; there is nowhere for your notes to go.

## Every network call has its own switch

**Settings → Privacy → Allow these network calls** lists everything that can reach the network. Each switch is the
only way the feature next to it goes online, and **Turn Everything Off** flips them all at once. With every switch
off, Jotter works fully offline.

| Switch | Default | What it calls | What is sent |
|---|---|---|---|
| Currency rates | **On** | `open.er-api.com` (fiat) and CoinGecko (crypto), at most once a day | A plain request for the latest rates. No note text, no identifiers. |
| Extension updates | Off | `raw.githubusercontent.com`, for extensions you installed from GitHub | The extension's repository path |
| Extension APIs | Off | Only the endpoints an extension declares in its manifest (for example the `llm` extension's OpenAI, Anthropic, Gemini, OpenRouter or local Ollama endpoint) | Whatever that command needs, such as the line you asked about. You choose the provider and supply your own API key. |
| Sync notes | Off | Your own iCloud Drive folder | Notes encrypted on this Mac with AES-GCM before they are written |
| Sync preferences | Off | Your own iCloud Drive folder | Settings, keywords and themes, encrypted the same way |

Currency rates are on out of the box so `$32 USD to JPY =` works on day one. Turning the switch off keeps the last
saved rates, and you can type your own rates in **Settings → Math**.

## What stays on your Mac

| Data | Location |
|---|---|
| Notes, The Void, archive | `~/Library/Application Support/Jotter/notes.sqlite` |
| Automatic backups | `~/Library/Application Support/Jotter/Backups` |
| Extensions you installed | `~/Library/Application Support/Jotter/Extensions` |
| Custom themes | `~/Library/Application Support/Jotter/Themes` |
| Saved exchange rates | `~/Library/Application Support/Jotter/exchange-rates.json` |
| Settings | `~/Library/Preferences/com.udsy.jotter.plist` |
| Extension API keys and the sync encryption key | macOS Keychain |

Text recognition from dropped images (Vision), Touch ID for locked notes (LocalAuthentication) and everything else
run on-device using Apple's frameworks.

## Extensions

Extensions are JavaScript that runs inside Jotter, each in its own JavaScriptCore context. An extension can only
reach the network when **Extension APIs** is on, only at the URLs its manifest declares, and only with an API key you
granted to that extension. Keys are substituted outside the script, so the JavaScript never sees them. Each extension
also declares how much of a note it can read (`none`, the current `line`, or the `full` note).

## Sync

Sync is off until you turn it on. Notes are sealed with a 256-bit key that is generated on your Mac and kept in your
Keychain (iCloud Keychain carries it to your other Macs when available). iCloud Drive only ever stores ciphertext.

## Exports

Apple Notes, Obsidian and Bear exports hand the note to that app on your Mac. Apple Notes export asks macOS for
Automation permission the first time. Markdown, plain text and PDF exports are files you save yourself.

## Removing everything

Run `curl -fsSL https://udsy19.github.io/Antinote/install.sh | bash -s -- --uninstall`, then delete
`~/Library/Application Support/Jotter` and `~/Library/Preferences/com.udsy.jotter.plist`. If you used sync, also
delete the `Jotter` folder in iCloud Drive.
