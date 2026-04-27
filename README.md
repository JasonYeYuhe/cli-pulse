# CLI Pulse

CLI Pulse is a developer app for monitoring usage, quotas, resets, sessions,
and alerts across supported AI coding providers. Available on macOS, iOS,
watchOS, and Android (beta).

This repository is the **public distribution and trust-documentation** repo
for CLI Pulse. It exists so users can:

- download official builds
- read the privacy, security, and terms documents
- find support contacts

It is **not** the product source code. CLI Pulse is closed-source commercial
software. See [License / All Rights Reserved](#license--all-rights-reserved)
below.

---

## What is CLI Pulse

CLI Pulse helps developers see — at a glance — how much of their AI provider
quotas they've used, what each provider is costing, when limits reset, and
which sessions are currently active. It supports providers like Claude,
Codex, Gemini, OpenRouter, Cursor, Copilot, JetBrains AI, Ollama, Warp,
Augment, and others.

The product spans:

- a macOS menu-bar app with a local helper
- an iOS / iPadOS / watchOS app
- an Android app (beta)

---

## Download

| Platform | Where |
|----------|-------|
| iOS / iPadOS / watchOS | [App Store](https://apps.apple.com/app/cli-pulse/id6761163709) |
| macOS | [Signed & notarized DMG on GitHub Releases](https://github.com/JasonYeYuhe/cli-pulse/releases/latest) |
| Android (beta) | [Google Play internal testing](https://play.google.com/apps/internaltest/4699926885235347963) or [APK on GitHub Releases](https://github.com/JasonYeYuhe/cli-pulse/releases/latest) |

Binaries obtained from any source not listed above are **not** authentic and
may have been modified. Please report unofficial redistributions to
**yyyyy.yeyuhe@gmail.com**.

The published landing page lives at
<https://jasonyeyuhe.github.io/cli-pulse/>.

---

## Privacy summary

The full policy is in [PRIVACY.md](PRIVACY.md) and at
<https://jasonyeyuhe.github.io/cli-pulse/privacy.html>. The short version:

- **Provider API keys are never uploaded.** They are stored only in your
  device's secure store (macOS Keychain on Mac, iOS Keychain on iPhone,
  AndroidX EncryptedSharedPreferences on Android) and used directly against
  the provider's own API.
- **Provider session cookies are never uploaded.** Same handling as API keys.
- **Bridged OAuth tokens** read from local files such as `~/.codex/auth.json`,
  `~/.claude/.credentials.json`, and `~/.gemini/oauth_creds.json` stay on
  your device. They are shared between the sandboxed app and the local
  helper through the Keychain and never sent to CLI Pulse servers.
- **Raw session-log contents** under `~/.codex/sessions/` and
  `~/.claude/projects/` are scanned **on-device only**, after you grant
  folder access via security-scoped bookmarks. The file contents never leave
  your Mac.
- We do not ship any third-party product-analytics SDK (no Google Analytics,
  Firebase Analytics, Amplitude, Mixpanel, or similar). Sentry is used for
  crash reports only and runs through a local scrubber that strips secrets,
  tokens, and `/Users/<name>` paths before any event is sent.

### What stays on-device

- provider API keys and session cookies
- bridged provider OAuth tokens
- the contents of local session logs
- security-scoped folder bookmarks
- locally-resolved alert suppression state

### What syncs to your CLI Pulse account

The data we sync is a small set of aggregated usage metrics and operational
metadata, kept to the minimum needed for cross-device viewing:

- provider name
- per-day token counts and request counts
- cost estimates derived locally
- quota / remaining / reset summaries
- session display metadata such as session name, status, and (minimized or
  hashed) project identifier
- device name, OS version, and helper version
- alerts that you choose to keep
- if you opt in to **Yield Score**: commit hash, an HMAC of the project
  path, the commit timestamp, and a merge-commit flag — never message,
  diff, file paths, or author identity

You can disable background sync, revoke folder access, or delete your
account at any time. See PRIVACY.md for the controls.

---

## Repository scope

This public repository is intentionally limited to:

- this `README.md`
- [LICENSE.md](LICENSE.md) — All Rights Reserved license
- [PRIVACY.md](PRIVACY.md) — privacy policy
- [TERMS.md](TERMS.md) — terms of use
- [SECURITY.md](SECURITY.md) — security policy and disclosure contact
- `docs/` — the static GitHub Pages site (landing, privacy, terms, security,
  data-handling, support, release notes)
- GitHub Releases — signed/notarized DMGs and APKs and their release notes

### What this repository is *not*

- It is **not** the product source code. The CLI Pulse macOS / iOS / watchOS
  / Android apps, their helper component, the Supabase backend, provider
  integrations, scanners, fixtures, internal planning documents, RPC
  schemas, and migrations are **not** published here.
- It is **not** a reproducible-build repository. You cannot rebuild a
  shipping CLI Pulse binary from anything in this repo.
- It is **not** a provider-integration reference. Nothing here documents how
  CLI Pulse talks to provider APIs, parses session logs, manages quotas,
  reads cookies, or accesses the Keychain.
- It is **not** permission to copy or reuse CLI Pulse code, assets, product
  designs, or documentation. See [LICENSE.md](LICENSE.md).

If you are looking for the product itself, install it from one of the
[official distribution channels](#download).

---

## License / All Rights Reserved

Copyright © Jason Ye. All rights reserved.

The contents of this repository are provided for product distribution, legal
notices, release notes, support, and transparency documentation only. No
license is granted to copy, modify, redistribute, reverse engineer, or
create derivative works from CLI Pulse application code, assets, product
designs, helper behavior, provider integration logic, or documentation
except where explicitly permitted in writing.

Full terms: [LICENSE.md](LICENSE.md).

For licensing inquiries, partnership requests, or takedown notices, email
**yyyyy.yeyuhe@gmail.com**.

---

## Support

- **Email:** [clipulse.support@gmail.com](mailto:clipulse.support@gmail.com)
- **Issues:** [github.com/JasonYeYuhe/cli-pulse/issues](https://github.com/JasonYeYuhe/cli-pulse/issues)
- **Security disclosures:** see [SECURITY.md](SECURITY.md)
- **Response time:** within 48 hours on business days
