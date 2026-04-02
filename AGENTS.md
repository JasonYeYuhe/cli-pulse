# CLI Pulse Agent Guide

This file is the canonical quick-start context for any AI or automation working
in this repository.

## Product State

CLI Pulse is a paid iOS product and an in-progress macOS product.

Current active architecture:

- `CLI Pulse Bar/`
  - Main app codebase for macOS, iOS, watchOS, widgets, and the shared
    `CLIPulseCore` package
- `helper/`
  - Local helper CLI used for pairing, daemon sync, local provider detection,
    and quota collection
- `backend/supabase/`
  - Active backend contract: SQL schema, migrations, and RPC definitions
- `docs/`
  - Public website/legal/distribution pages used by GitHub Pages

## Repository Visibility Rule

This product should be treated as **closed-source product code**.

Do not assume the public GitHub repository should contain full source.

### Must stay private

- `CLI Pulse Bar/`
- `helper/`
- `backend/` except public-facing legal/distribution docs
- `archive/`
- test fixtures and provider parsing logic
- anything that reveals helper behavior, quota logic, cookie/keychain access,
  sync contracts, provider integrations, release internals, or product IP

### Can be public

- `docs/index.html`
- `docs/privacy.html`
- `docs/terms.html`
- public download links and release notes
- support and marketing content

## Git Rules

- Do **not** push product source changes to the public `origin` repo unless the
  task is explicitly about public website/distribution content only.
- Use a private repository for source development.
- Treat the public repo as distribution-facing unless explicitly told otherwise.
- Before any push, check whether the target remote is public or private.

## Current Repo Reality

- `origin` currently points to the public `cli-pulse` GitHub repo.
- A private source repo should be used for ongoing development.
- Public GitHub Pages and GitHub Releases may still be used for:
  - website pages
  - legal pages
  - macOS release downloads
  - support links

## Active vs Archived

### Active

- `CLI Pulse Bar/`
- `helper/`
- `backend/supabase/`
- `docs/`
- `PRIVACY.md`
- `TERMS.md`

### Archived or historical

- `archive/legacy-root/`
- `archive/backend-fastapi-legacy/`

## Current Technical Direction

- App auth and sync are Supabase-based
- Cloud Sync is account-based, not direct device-to-device pairing
- The Mac helper is the source of local collection and sync
- Claude, Gemini, Codex, and other provider collectors are implemented inside
  `CLIPulseCore` and helper-side parsing logic

## Safe Validation Commands

Run these before shipping collector or helper changes:

```bash
python3 -m pytest -q helper/test_system_collector.py
swift test --package-path "CLI Pulse Bar/CLIPulseCore"
```

## If You Are a New AI Starting Work

1. Read this file first.
2. Read `/Users/jason/Documents/cli pulse/README.md`.
3. Read `/Users/jason/Documents/cli pulse/REPO_VISIBILITY_STRATEGY.md`.
4. Treat the app/helper/backend logic as private product IP.
5. Do not publish source changes to the public repo by default.
