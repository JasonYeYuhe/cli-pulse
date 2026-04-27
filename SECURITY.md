# Security Policy

CLI Pulse is a developer tool that touches local credentials and AI provider
APIs, so security and privacy are explicit product goals. This document
explains how to report vulnerabilities and summarizes how user data is
handled.

The full privacy policy lives in [PRIVACY.md](PRIVACY.md) and at
<https://jasonyeyuhe.github.io/cli-pulse/privacy.html>. This file focuses on
the security and disclosure aspects.

---

## Reporting vulnerabilities

If you believe you've found a security or privacy issue in CLI Pulse,
please report it privately first.

- **Email:** **yyyyy.yeyuhe@gmail.com**
- **Subject prefix:** `[CLI Pulse Security]`
- **Preferred details:**
  - the affected platform (macOS / iOS / watchOS / Android / backend / web)
  - the affected app version (visible in Settings → About)
  - reproduction steps and impact
  - any logs, stack traces, or screenshots that help

Please do **not** open a public GitHub issue for unfixed security
vulnerabilities. Public issues are appropriate for general bug reports and
feature requests.

We aim to:

- acknowledge new reports within 3 business days
- provide an initial assessment within 7 business days
- ship a fix or a documented mitigation within 30 days for high-severity
  issues, with timeline updates if more time is needed

This is a small, single-developer project, so response times depend on the
report's severity and complexity. Reports that include a clear repro and
impact assessment get triaged fastest.

---

## Responsible disclosure

We support coordinated disclosure:

- please give us a reasonable window (typically 30 days, longer for
  complex issues) to ship a fix before publishing
- if the issue is being actively exploited, tell us in the first email so
  we can prioritize
- we will credit reporters in the release notes when a fix ships, unless
  the reporter prefers anonymity

---

## Data-handling summary

The detailed table is in [PRIVACY.md](PRIVACY.md) and at
<https://jasonyeyuhe.github.io/cli-pulse/data-handling.html>. The key
guarantees:

- **Provider API keys are not uploaded to CLI Pulse servers.** They are
  stored only in the device's secure store (macOS / iOS Keychain, Android
  EncryptedSharedPreferences) and used directly against the provider's API
  over HTTPS.
- **Provider session cookies are not uploaded to CLI Pulse servers.** Same
  handling.
- **Bridged provider OAuth tokens** (read from local files on the user's
  Mac, e.g. `~/.codex/auth.json`, `~/.claude/.credentials.json`,
  `~/.gemini/oauth_creds.json`) are stored in the macOS Keychain (shared
  via the app group between the sandboxed app and the helper) and are
  **not** uploaded to CLI Pulse servers.
- **Raw session-log contents** under paths like `~/.codex/sessions/` and
  `~/.claude/projects/` are scanned **on-device only** after the user
  grants folder access via security-scoped bookmarks. The file contents
  never leave the device.
- The data CLI Pulse syncs to your account is intentionally limited to
  aggregated metrics and operational metadata: provider name, per-day
  token / request counts, locally-derived cost estimates, quota and reset
  summaries, session display metadata (with project paths minimized or
  hashed), device name / OS version / helper version, and alerts you
  choose to keep.
- If you opt in to **Yield Score**, only the commit hash, an HMAC of the
  project path, the commit timestamp, and a merge-commit flag are
  uploaded. Commit messages, diffs, file paths, and author identity are
  never uploaded.

---

## Credential handling

- **Storage:** macOS Keychain on Mac, iOS Keychain on iPhone /
  iPad / Apple Watch, AndroidX EncryptedSharedPreferences on Android. All
  are encrypted at rest by the OS and unlocked alongside the user
  account.
- **Transport to providers:** TLS 1.2+ direct from the user's device to
  each provider's official API endpoint. Provider credentials do not
  transit CLI Pulse infrastructure.
- **Transport to CLI Pulse Sync:** TLS 1.2+ to Supabase. Only the metric
  and metadata categories listed above are sent. Authorization uses the
  user's CLI Pulse session token.
- **App Sandbox** (`com.apple.security.app-sandbox`) is enabled on the
  Apple platforms. File access outside the app container requires
  user-granted security-scoped bookmarks.

---

## Local helper

CLI Pulse for Mac uses a local helper component to perform on-device
collection. The helper:

- runs only on the user's Mac
- reads only the local session-log paths the user has granted access to
- communicates with the main app over a local IPC channel
- shares Keychain items with the main app via the app group, not the
  network
- can be disabled by the user; background sync can also be turned off

The helper does not phone home with raw credentials, raw cookies, or raw
session-log contents. Its uploads are limited to the metric / metadata
categories described above.

---

## Remote sync

CLI Pulse Sync is account-based (Supabase Auth). Sync exists so that
iPhone, Apple Watch, and Android clients can show the same numbers as the
Mac without re-running the local scanner themselves.

- Server-side encryption at rest (AES-256) is applied by Supabase to the
  database and storage backing each account.
- TLS 1.2+ in transit.
- No third-party product-analytics SDK ships with CLI Pulse. Sentry is
  used for crash reports only and runs through a local `beforeSend`
  scrubber that removes API keys, OAuth tokens, JWTs, Bearer headers,
  `/Users/<name>` paths, and any field whose name contains common
  sensitive fragments before the event leaves the device. Performance
  tracing is disabled (`tracesSampleRate = 0`).

---

## User controls

- **Disable background sync / helper:** Settings → General on macOS;
  Settings → Sync on the mobile clients.
- **Revoke folder access:** Settings → CLI Tool Access → remove the
  bookmark for that directory.
- **Delete API keys:** Settings → Providers → remove a provider.
- **Delete account:** Settings → Account → Delete Account. Cascading
  deletes remove all associated rows within 30 days.

---

## Out of scope

The following are intentionally out of scope for this security policy:

- third-party AI providers' own APIs and their data handling — please
  refer to the provider's own policies
- third-party platform stores (Apple App Store, Google Play, Supabase)
  for their own infrastructure security

---

## Contact

- **Security disclosures:** **yyyyy.yeyuhe@gmail.com** with subject
  `[CLI Pulse Security]`
- **General support:** [clipulse.support@gmail.com](mailto:clipulse.support@gmail.com)
