# ExtensionsKit

JavaScript extensions that add `::commands` to notes. Super Notes keeps the JavaScript API shape of the original
extension format so existing extensions can be ported by copying their folder into the extensions folder.

Registered as `Services.extensions` (`ExtensionsServicing`) by `ExtensionsKitModule.install()`.

## Extension folders

An extension is a folder containing:

| File | Purpose |
|---|---|
| `extension.json` | Manifest — the static, user-visible contract (validated before any code runs) |
| `index.js` | Code; registers an `Extension` and its `Command`s |
| other `.js` files | Optional; listed in the manifest's `files` array and evaluated in that order |

Sources, in load order:

1. **Bundled** — `Bundled/<name>/` inside the module's resource bundle. Lookup order: `SuperNotes_ExtensionsKit.bundle`
   in `Bundle.main.resourceURL` (packaged app), then next to the executable (`swift run`, self-tests).
   `Bundle.module` is never touched, so a missing bundle means "no bundled extensions", never a crash.
2. **User** — `SuperNotesPaths.extensions/<name>/` (`~/Library/Application Support/Super Notes/Extensions`). A user extension
   with the same name as a bundled one replaces it (that is how a newer version from GitHub wins).

### Manifest

```json
{ "name": "date", "version": "1.0.0", "author": "Super Notes", "description": "…", "license": "MIT",
  "category": "Date & Time", "dataScope": "none", "dependencies": [], "endpoints": [],
  "requiredAPIKeys": [], "files": ["index.js"], "isService": false }
```

Validation errors (shown in the manager and the log, the extension is skipped):

- missing / unreadable `extension.json`, invalid JSON
- `name` empty or not `[A-Za-z0-9_-]+`; `version` not `major.minor[.patch]`
- `dataScope` not `none`, `line` or `full` (absent means `full`, the original default)
- an endpoint that is not an absolute `https` URL (`http` is allowed only for `localhost` / `127.0.0.1`)
- a `files` entry that is absolute, contains `..`, or does not exist; missing `index.js`
- the script registers no `Extension`, or registers one whose name differs from the manifest
- dependency problems (below)

The manifest is authoritative for security fields: `endpoints`, `requiredAPIKeys` and `dataScope` come from
`extension.json`, not from whatever the script passes to `new Extension(…)`.

### Dependencies

`dependencies` names other extensions (typically `isService` ones exposing globals). Resolution is a depth-first
topological sort with clear errors: `'llm2' depends on 'ai_core', which is not installed`, `Dependency cycle:
a → b → a`, `'x' depends on 'y', which failed to load`. Each extension still gets its own `JSContext`; its
dependencies' scripts are evaluated into that context first (in dependency order) so services' globals are
available. Commands registered by a dependency's script are not duplicated. Network permission of a context is the
union of the extension's and its dependencies' manifests.

## Runtime

- One `JSContext` per extension, created and used only on that extension's serial `DispatchQueue`. Results are
  delivered on the main queue.
- Our own base library (`BaseLibrary.swift`) defines the same globals as the original: `Extension`, `Command`
  (with `getParsedParams`), `Parameter`, `Preference`, `TutorialCommand`, `ReturnObject`, `MathEvaluator`
  (`eval`, `evalSafe`, `isMathExpression`, `parseNumeric`), `global`, `commandRegistry`, `extensionRegistry`.
  Every constructor accepts both the config-object form (`new Command({name: …})`) and the older positional form
  (`new Command("gpt", [params], "insert", "help", tutorials, ext)`).
- Bridges: `console.log/info/warn/error` → `ExtensionLogger` (only when `Defaults[.extensionLogging]`; load
  failures are always logged); `__evaluateMathExpression` → `Services.analyzer.evaluate` via a main-thread hop;
  `getPreference(key)` and `getExtensionPreference(ext, key)` (own extension or a dependency only); `now()`
  returns the manager's clock in milliseconds (tests inject a fixed date); `callAPI(…)`.

### callAPI(apiKeyName, url, method, headers, body) → { success, status, data, error }

Synchronous from JavaScript's view; executed with `URLSession` (60 s timeout) while the extension's queue waits.
Allowed only when all hold, otherwise `{success:false, error:<reason>}` without any network traffic:

1. `Defaults[.allowExtensionAPIs]` is on (Settings → Privacy, "Let extensions call their own APIs");
2. the URL's scheme, host and port match one of the declared `endpoints`;
3. if `apiKeyName` is non-empty: the key exists in the Keychain (account `apikey_<name>`, a leading `apikey_` in
   the argument is accepted) and the user granted it to this extension (or a dependency).

`{{API_KEY}}` in the URL and headers (a JSON string or object) is replaced with the secret, which never enters
the JS heap.

### Data scope

| dataScope | `payload.line` | `payload.fullText` |
|---|---|---|
| `none` | `""` | `""` |
| `line` | invocation line, command text removed | same as `line` |
| `full` | invocation line, command text removed | whole note, command text removed (an emptied line is dropped) |

## Invocation

`::name`, `::name()`, `::name(arg1, "arg, 2", 3)`. Arguments split on top-level commas; quotes (`"` or `'`, with
`\` escapes) and nested parentheses are respected. When more arguments than parameters are given and the last
parameter is `string`/`paragraph`, the surplus raw text joins it (`::ask(What is 2, 3?)`). Names match
case-insensitively against command names and aliases of enabled extensions.

Parameter coercion happens in Swift before JS runs, with friendly errors:

- missing required → `Required parameter 'days' is missing`; missing optional → declared default
- `int` → `Parameter 'days' must be a whole number`; `float` → `… must be a number`
- `bool` → true/false/yes/no/1/0/on/off; `expression` → number, or evaluated with `Services.analyzer`
- `string` / `paragraph` → text as written

`payload = { parameters, line, fullText, command, dataScope }`.

### Results

`execute` may return a `ReturnObject` or a plain string. Mapping to `ExtensionEdit`:

- `status: "error"` (or a thrown error) → `.failure(message)`
- success, type `insert` with an empty payload → `.message(message)`
- success → `.insert` / `.replaceLine` / `.replaceAll` / `.openURL` per the command's `type` (an invalid URL is a
  failure)

## Enable, preferences, keys (Defaults, `extensions.` prefix)

- `extensions.disabled` — names of disabled extensions; `extensions.prefs.<name>` — preference values;
  `extensions.apiKeys` — known key ids; `extensions.keyGrants` — key id → extensions allowed to use it;
  `extensions.sources` — installed extension → GitHub repository URL.
- `Defaults[.extensionsEnabled]` off → no commands, `run` fails with "Extensions are turned off".

## Community extensions

- Install from GitHub (`https://github.com/owner/repo[/tree/branch/subdir]`), only when
  `Defaults[.allowExtensionUpdates]` is on: fetch `extension.json` from `raw.githubusercontent.com` (`HEAD` =
  default branch), validate, fetch `index.js` and listed files, write to the user folder, reload.
- Update check: refetch remote manifests of GitHub-installed extensions, compare versions numerically.
- Remove: deletes a user extension folder (bundled ones can only be disabled).

## Bundled extensions (original code, MIT)

date, lines, text, random, json, regex, finance, checklists, templates, llm (OpenAI, Anthropic, Gemini, OpenRouter,
Ollama; provider and model in preferences; Ollama needs no key but still needs the APIs switch).

## Settings view

`makeSettingsView()` — tabs: **Extensions** (master + logging toggles, list with enable toggles, details with
commands/help/keys/endpoints/data scope, generated preference controls, GitHub install, update check, reload, open
folder, remove), **API Keys** (add/replace/delete, per-extension grants), **Logs**.

## Not implemented

Signature/checksum verification, iCloud sync of extensions (`syncExtensions`), user-defined aliases, execution
time limits for runaway scripts (needs private JSC API).
