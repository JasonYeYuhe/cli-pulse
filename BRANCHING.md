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

### `<task-name>`

- Normal feature or fix branch
- One branch per task
- Examples:
  - `onboarding-pairing-ux`
  - `provider-fix-gemini`
  - `volcano-engine-support`
  - `release-1-1-4`

## Current Special Branches

These already exist and should not become catch-all branches for unrelated work:

- `provider-sync-repo-cleanup`
  - repo cleanup
  - visibility split
  - release and notarization workflow
- `onboarding-pairing-ux`
  - onboarding and cloud sync setup UX

If a new task is unrelated to those scopes, create a new branch.

Existing older branches may still use the historical `codex/` prefix. That is
fine. Do not rename active branches just for naming cleanup. The new default is
simply to create task-named branches without the `codex/` prefix.

## Standard Workflow For A New Task

Always do this before starting a fresh task:

```bash
cd "/Users/jason/Documents/cli pulse"
git checkout main
git pull origin main
git checkout -b <task-name>
```

Example:

```bash
git checkout main
git pull origin main
git checkout -b volcano-engine-support
```

## AI Branch Decision Policy

When a user gives a new task, the AI should decide branch strategy before doing
real work.

### Step 1: Inspect current repo state

Always check:

```bash
git branch --show-current
git status --short --branch
```

### Step 2: Classify the task

Put the task into one of these buckets:

- current branch continuation
- new product feature or bug fix
- release or notarization work
- public distribution-only work
- repo cleanup / documentation / process work

### Step 3: Apply the rule

#### Reuse the current branch only if all are true

- the current branch already matches the task scope
- the task is a continuation of the same work
- the user did not ask to separate it
- the branch is not being reused as a dumping ground for unrelated changes

Example:

- already on `onboarding-pairing-ux`
- user asks for another onboarding wording fix
- result: stay on `onboarding-pairing-ux`

#### Create a new branch from private `main` if any are true

- the task is unrelated to the current branch
- the current branch is feature-specific and the new task is different
- the task should be independently reviewable or releasable
- the user is starting a new idea, provider, integration, or bug thread

Example:

- current branch: `onboarding-pairing-ux`
- new task: add Volcano Engine support
- result: create `volcano-engine-support` from updated private `main`

#### Use a release branch only for release work

Use a dedicated branch such as:

- `release-1-1-4`

Only for:

- version bumps
- release notes
- packaging
- signing
- notarization
- release validation

Do not mix product features into a release branch.

#### Use the public repo only for distribution-only work

Only switch to `public` when the task is explicitly about:

- `docs/`
- `README.md`
- `PRIVACY.md`
- `TERMS.md`
- GitHub Pages
- public release notes
- public release asset upload

Never use the public repo for app/helper/backend source development.

## AI Default Behavior

If the user gives a new task without mentioning branches, the AI should:

1. inspect the current branch
2. decide whether the task matches that branch
3. if it does not match, create a new task-named branch from private `main`
4. tell the user briefly what it decided and why

The AI should not silently continue unrelated work on an old feature branch.

## Quick Decision Table

- same task family as current branch: reuse current branch
- unrelated feature/fix: create new branch from `main`
- release/signing/notarization: create or use a release branch
- docs/download/privacy/terms/public release page: use `public` distribution
  workflow only
- if unsure: prefer a new branch over polluting an old one

## If You Accidentally Start On The Wrong Branch

Check where you actually are:

```bash
git branch --show-current
```

If it prints a task branch such as `onboarding-pairing-ux`, you are not on
`main`, even if a UI shows `main <- onboarding-pairing-ux`.

That UI means:

- current working branch = `onboarding-pairing-ux`
- base branch = `main`

It does **not** mean your HEAD is on `main`.

To reset correctly for a new task:

```bash
git checkout main
git pull origin main
git checkout -b <new-task>
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
