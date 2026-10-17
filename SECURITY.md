# Security Policy

Jotter runs entirely on your Mac. It has no accounts, no analytics and no servers. Network access is limited to the
features listed in **Settings → Privacy**, each behind its own switch: daily currency rates, extension updates from
GitHub, extension API calls to endpoints the extension declares, and end-to-end encrypted sync through your own
iCloud Drive. API keys and the sync encryption key live in the macOS Keychain.

Areas where a report is especially valuable: the extension sandbox (JavaScriptCore contexts, endpoint and API-key
checks, data scopes), sync encryption and key handling, locked notes, and the `jotter://` URL scheme.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/udsy19/Antinote/security/advisories/new) instead.
You'll get a response within a few days, and a fix will be released as soon as practical.

## Supported versions

Only the latest release receives security fixes.
