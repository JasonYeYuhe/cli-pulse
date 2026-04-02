# CLI Pulse

This workspace contains the current `CLI Pulse Bar` app plus a small amount of
legacy material kept for reference.

## Current Product Structure

- `CLI Pulse Bar/`
  - Current Xcode workspace and app targets for macOS, iOS, Watch, Widgets, and
    the shared `CLIPulseCore` package.
- `helper/`
  - Current helper CLI used for pairing, daemon sync, and local provider
    collection.
- `backend/supabase/`
  - Active SQL schema, migrations, and RPC definitions used by the app and
    helper when talking to Supabase.
- `docs/`
  - Published static site assets, including `privacy.html`, `terms.html`, and
    `index.html`, which are linked from the shipping app.

## Current Development Commands

### App

Open the current app workspace:

```bash
open "CLI Pulse Bar/CLI Pulse Bar.xcodeproj"
```

### Helper

Run helper tests:

```bash
python3 -m pytest -q helper/test_system_collector.py
```

Inspect local collection output:

```bash
python3 helper/cli_pulse_helper.py inspect
```

Run one sync:

```bash
python3 helper/cli_pulse_helper.py sync
```

### Shared Swift Package

Run the shared package tests:

```bash
swift test --package-path "CLI Pulse Bar/CLIPulseCore"
```

## Legacy or Reference Areas

- `archive/`
  - Archived drafts, old projects, and working notes that are no longer part of
    the active product path.
  - `archive/backend-fastapi-legacy/` contains the older FastAPI runtime and its
    tests.

## Notes

- If you are looking for the current shipping code, start in `CLI Pulse Bar/`.
- If you are looking for pairing or provider collection logic, start in
  `helper/`.
- If you are looking for the live backend contract, start in
  `backend/supabase/`.
- If you are preparing a release, read `RELEASE_WORKFLOW.md`.
- If you are starting a new task branch, read `BRANCHING.md`.
- If you are handing a new task to another AI, use `TASK_START_PROMPT.md`.
- If you are asking an AI to commit, merge, or decide whether public updates are needed, read `MERGE_AND_PUBLISH_RULES.md`.
