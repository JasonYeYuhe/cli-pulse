# CLI Pulse Merge And Publish Rules

Use this document when working with AI on commits, merges, and deciding whether
private and public repos both need updates.

## Default Interpretation

If the user says:

- "直接 merge 到 main"
- "直接合到 main"
- "不用 PR，直接合并"

the default meaning is:

1. commit the current task branch work in the private source repo
2. push that task branch to `origin`
3. merge it into private `main`
4. push private `main`

Do **not** assume the public repo should be updated unless the task clearly
requires it.

## Repo Roles

### Private source repo

- remote: `origin`
- contains app source, helper, backend, tests, internal docs

### Public distribution repo

- remote: `public`
- contains public website/legal pages and GitHub Releases distribution history

## AI Decision Rule

When the user asks to commit, merge, or ship something, the AI should first
classify the work into one of these buckets:

1. private-only source change
2. private source change plus release/distribution work
3. public-only distribution/documentation work

## Case 1: Private-Only Source Change

This is the default.

Examples:

- provider collector changes
- app UI changes
- helper logic changes
- backend contract changes
- tests
- internal docs used for development

### What the AI should do

If the user says "直接 merge 到 main", the AI should:

1. verify current branch is a task branch, not `main`
2. run the relevant validation for the touched area
3. commit current branch changes
4. push current branch to `origin`
5. merge into private `main`
6. push private `main`

### What the AI should NOT do

- do not update `public`
- do not create a public release
- do not touch GitHub Pages
- do not modify public legal pages

## Case 2: Private Change Plus Release/Distribution Work

Examples:

- version bump for macOS release
- packaging DMG
- signing
- notarization
- release notes tied to a new downloadable build
- download page update for a new release

### What the AI should do

First do the private flow:

1. commit and merge source changes into private `main`
2. push private `main`
3. build and validate the release artifact from private source

Then do the public flow only if needed:

4. update public release notes or download page
5. upload the DMG to the public GitHub Release
6. verify GitHub Pages or release links if they changed

### Important

Public repo updates are **not automatic**.

The AI should update `public` only when the user request actually involves
distribution, release artifacts, download pages, legal pages, or other public
surface area.

## Case 3: Public-Only Distribution/Docs Work

Examples:

- update `docs/index.html`
- update `PRIVACY.md` / `TERMS.md`
- adjust support wording
- update public README
- fix GitHub Pages content

### What the AI should do

1. work only on the public distribution workflow
2. avoid touching app/helper/backend source
3. do not merge private source branches unless separately requested

## Direct Merge Rule

If the user says "直接 merge 到 main", and does not mention public release or
public docs, the AI should assume:

- merge to **private `main` only**
- no public action

If the user says any of these:

- "发版"
- "上传新版本"
- "更新下载页"
- "更新 GitHub Pages"
- "更新 privacy / terms"
- "release"
- "notarize"

then the AI should explicitly consider whether public work is required.

## Validation Before Merge

At minimum, the AI should run the most relevant checks for the changed area.

Common defaults:

```bash
python3 -m pytest -q helper/test_system_collector.py
swift test --package-path "CLI Pulse Bar/CLIPulseCore"
```

If only docs changed, lightweight validation is enough.

If release/signing work changed, use `RELEASE_WORKFLOW.md`.

## Merge Procedure For AI

When asked to "直接 merge 到 main", the AI should follow this order:

```bash
git branch --show-current
git status --short --branch
```

Then:

1. confirm current branch is the intended task branch
2. validate
3. commit if needed
4. push task branch to `origin`
5. `git checkout main`
6. `git pull origin main`
7. `git merge <task-branch>`
8. `git push origin main`

Only after that should it decide whether a separate public update is needed.

## Public Update Decision Table

- app/helper/backend/tests/internal docs only: private only
- macOS downloadable build: private + public
- GitHub Pages text change: public only
- legal page change: public only, and maybe private source docs if requested
- release notes for a new DMG: public
- notarization/build script changes without shipping a new version yet: private only

## Short Rule For AI

If unsure:

- default to private-only
- do not touch `public` unless the task clearly affects public distribution
- do not publish source code to `public`

## Related Docs

- `/Users/jason/Documents/cli pulse/AGENTS.md`
- `/Users/jason/Documents/cli pulse/BRANCHING.md`
- `/Users/jason/Documents/cli pulse/RELEASE_WORKFLOW.md`
- `/Users/jason/Documents/cli pulse/TASK_START_PROMPT.md`
