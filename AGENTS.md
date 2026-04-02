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

- `origin` is the private source repository.
- `public` is the public distribution repository.
- Do **not** push product source changes to `public` unless the task is
  explicitly about public website/distribution content only.
- Treat the public repo as distribution-facing unless explicitly told
  otherwise.
- Before any push, check whether the target remote is `origin` or `public`.
- The public `main` branch has been rewritten to distribution-only history.
- Public releases/tags are expected to point to distribution-only commits, not
  source commits.

## Current Repo Reality

- `origin` points to the private `cli-pulse-private` repo.
- `public` points to the public `cli-pulse` repo.
- Public GitHub Pages and GitHub Releases are still used for:
  - website pages
  - legal pages
  - macOS release downloads
  - support links
- Public repo contents are intentionally minimal:
  - `.gitignore`
  - `README.md`
  - `PRIVACY.md`
  - `TERMS.md`
  - `docs/`

## Public Release Workflow

If a task is specifically about the public repo, keep it distribution-only.

- Update website/legal/support content only.
- Upload notarized macOS artifacts to GitHub Releases in `public`.
- Do not add app source, helper source, backend code, tests, fixtures, or
  internal notes to `public`.
- If a release tag must be recreated, ensure it is recreated on a
  distribution-only commit.

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
4. Read `/Users/jason/Documents/cli pulse/RELEASE_WORKFLOW.md` before doing
   release or distribution work.
5. Treat the app/helper/backend logic as private product IP.
6. Do not publish source changes to the public repo by default.
