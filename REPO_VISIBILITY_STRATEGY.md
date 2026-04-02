# CLI Pulse Repo Visibility Strategy

**Status:** active repository policy  
**Last Updated:** April 2, 2026

## Recommendation

CLI Pulse should not continue as a fully public source repository.

The current product is a paid iOS app and an unreleased macOS app with
provider-specific quota collection, helper-side local inspection, and backend
sync logic. Those pieces are product IP, not just generic glue code.

Recommended end state:

- **Private source repo** for all product code
- **Public distribution repo or site** for downloads, legal pages, release
  notes, and support links

## What Should Stay Closed

These areas should live only in a private repository:

- `CLI Pulse Bar/`
  - All app source, UI, StoreKit wiring, provider settings, and shared core
- `helper/`
  - Pairing flow, daemon sync, local provider collection, cookie/keychain
    access, quota parsing, fallback logic
- `backend/`
  - Supabase schema, RPC definitions, backend contracts, and any remaining
    server-side logic
- `archive/`
  - Old code, research notes, internal review artifacts, and legacy backend
    history
- `tests/` or any test fixtures that reveal product behavior, provider parsing,
  fallback design, or private assumptions
- Build and release automation that exposes internal workflow details beyond
  what is needed for public downloads

## What Can Be Public

These can safely remain public in a separate distribution-facing repository:

- `docs/index.html`
- `docs/privacy.html`
- `docs/terms.html`
- App screenshots, icons, and marketing assets intended for users
- Release notes and changelog entries
- Download links for notarized macOS release artifacts
- Sparkle appcast or equivalent update feed
- Public support docs, FAQ, issue templates, and contact information

## Public Repo Purpose

The public repo should behave like a distribution and support surface, not a
source repository.

Suggested contents:

- `README.md`
  - Product description
  - Download links
  - App Store link
  - Support email
- `docs/`
  - Website, legal pages, support pages
- `releases/` or release assets only if needed
- `appcast.xml` if Sparkle updates are hosted there

Suggested exclusions:

- No app source
- No helper source
- No backend source
- No internal archive
- No provider parsers
- No test fixtures

## GitHub Releases and GitHub Pages

Both can still be used without open-sourcing the product.

### GitHub Releases

Use a public distribution repo to publish:

- signed DMG or ZIP assets
- checksums
- release notes

Do not use that repo to host the actual macOS source code.

### GitHub Pages

Use the public repo only for:

- website landing page
- privacy page
- terms page
- support or FAQ pages
- update feed hosting if needed

## Recommended Repo Split

### Private repo

Suggested name:

- `cli-pulse-private`

Contains:

- full source
- helper
- backend
- tests
- internal docs
- release automation

### Public repo

Suggested name:

- keep `cli-pulse` as the public-facing repo, but reduce it to distribution
  assets only

Contains:

- public website and legal pages
- release downloads
- public changelog and support info

## Current State

This migration is complete:

1. `origin` now points to the private source repository:
   - `JasonYeYuhe/cli-pulse-private`
2. `public` now points to the public distribution repository:
   - `JasonYeYuhe/cli-pulse`
3. The public `main` branch has been rewritten to contain only
   distribution-facing files.
4. Public release tags were recreated on the distribution-only history so that
   GitHub-generated source archives no longer expose product code.
5. GitHub Pages continues to publish from `public/main:/docs`.

## Public Repo Allowed Contents

The public repository should contain only:

- `README.md`
- `PRIVACY.md`
- `TERMS.md`
- `docs/`
- release assets such as notarized DMGs

The public repository should not contain:

- `CLI Pulse Bar/`
- `helper/`
- `backend/`
- `archive/`
- `tests/`
- internal prompts, research notes, or AI handoff files
- provider integration logic or fixtures

## Ongoing Operating Rule

- Do all product development against `origin` only.
- Use `public` only for distribution tasks:
  - GitHub Pages updates
  - legal page updates
  - support/contact page updates
  - release asset uploads
  - public changelog or release-note changes
- Never merge private product branches into `public`.
- Never create public tags from source-bearing commits.

## Practical Boundary Rule

If a file helps a competitor reproduce the product, provider integrations,
quota logic, sync model, or local helper behavior, it should be private.

If a file exists only to help users download, trust, understand, or contact the
product, it can be public.

## Decision Summary

### Private

- app source
- helper
- backend
- tests
- archive
- internal docs
- provider integration logic

### Public

- website pages
- legal pages
- release assets
- changelog
- support information
