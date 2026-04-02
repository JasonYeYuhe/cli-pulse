# CLI Pulse Branching Guide

This repository uses a private source repo for development and a separate public
distribution repo for releases, downloads, and GitHub Pages.

## Core Rule

- Do not develop directly on `main`.
- Start each new task from private `main`.
- Use one task branch per unit of work.
- Do not use the public repo for source-code development.

## Remotes

- `origin` = private source repo
- `public` = public distribution repo

Source work goes to `origin`.

Distribution-only work goes to `public`.

## Branch Roles

### `main`

- Integration branch in the private repo
- Should stay stable enough to branch from
- Should not be used for day-to-day direct edits

### `codex/<task-name>`

- Normal feature or fix branch
- One branch per task
- Examples:
  - `codex/onboarding-pairing-ux`
  - `codex/provider-fix-gemini`
  - `codex/volcano-engine-support`
  - `codex/release-1-1-4`

## Current Special Branches

These already exist and should not become catch-all branches for unrelated work:

- `codex/provider-sync-repo-cleanup`
  - repo cleanup
  - visibility split
  - release and notarization workflow
- `codex/onboarding-pairing-ux`
  - onboarding and cloud sync setup UX

If a new task is unrelated to those scopes, create a new branch.

## Standard Workflow For A New Task

Always do this before starting a fresh task:

```bash
cd "/Users/jason/Documents/cli pulse"
git checkout main
git pull origin main
git checkout -b codex/<task-name>
```

Example:

```bash
git checkout main
git pull origin main
git checkout -b codex/volcano-engine-support
```

## If You Accidentally Start On The Wrong Branch

Check where you actually are:

```bash
git branch --show-current
```

If it prints a task branch such as `codex/onboarding-pairing-ux`, you are not on
`main`, even if a UI shows `main <- codex/onboarding-pairing-ux`.

That UI means:

- current working branch = `codex/onboarding-pairing-ux`
- base branch = `main`

It does **not** mean your HEAD is on `main`.

To reset correctly for a new task:

```bash
git checkout main
git pull origin main
git checkout -b codex/<new-task>
```

## When Not To Branch From `main`

If private `main` is stale and does not yet include branches that should become
your new baseline, merge those branches first or consciously choose a different
base branch.

Do not silently stack new unrelated work on top of an old task branch just
because it already has useful changes.

## Commit Discipline

- Keep one logical topic per branch
- Commit after validation
- Push to `origin`, not `public`
- Do not mix:
  - onboarding UX
  - provider quota fixes
  - repo cleanup
  - release/notarization work

## Public Repo Rule

The public repo is distribution-only.

Allowed there:

- `docs/`
- `README.md`
- `PRIVACY.md`
- `TERMS.md`
- GitHub Releases assets and release notes

Not allowed there:

- app source
- helper source
- backend source
- tests
- internal notes
- provider collectors

## Before Asking Another AI To Work

Tell it to read:

- `/Users/jason/Documents/cli pulse/AGENTS.md`
- `/Users/jason/Documents/cli pulse/README.md`
- `/Users/jason/Documents/cli pulse/REPO_VISIBILITY_STRATEGY.md`
- `/Users/jason/Documents/cli pulse/RELEASE_WORKFLOW.md`
- `/Users/jason/Documents/cli pulse/BRANCHING.md`

And tell it which branch it is allowed to use.
