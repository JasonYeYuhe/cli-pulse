# CLI Pulse Release Workflow

This document defines the release path for CLI Pulse now that source and
distribution have been separated.

## Repo Roles

### Private source repo

- Remote name: `origin`
- GitHub repo: `JasonYeYuhe/cli-pulse-private`
- Contains:
  - `CLI Pulse Bar/`
  - `helper/`
  - `backend/`
  - `archive/`
  - tests
  - internal docs and implementation notes

### Public distribution repo

- Remote name: `public`
- GitHub repo: `JasonYeYuhe/cli-pulse`
- Contains only:
  - `README.md`
  - `PRIVACY.md`
  - `TERMS.md`
  - `docs/`
  - public GitHub Releases assets

Do not push product source to `public`.

## Release Principles

1. All development happens in the private repo.
2. Public GitHub is for downloads, legal pages, support, and release notes.
3. Public release tags must point only to distribution-only commits.
4. DMG assets may be public; source code may not.

## Standard macOS Release Flow

### 1. Finish product work in private

- Implement and review changes in the private repo.
- Commit and push to `origin`.
- Merge to private `main` only when ready.

### 2. Validate before building

Run these from the private source workspace root:

```bash
python3 -m pytest -q helper/test_system_collector.py
swift test --package-path "CLI Pulse Bar/CLIPulseCore"
```

If the release includes app packaging or entitlement changes, also run a local
Xcode build and a quick smoke test of the macOS app.

### 3. Build the macOS artifact

- Build the macOS app from the private repo.
- Sign and notarize the app if required.
- Produce the release artifact, typically a DMG.
- Keep the built artifact outside the public repo until upload time.

Recommended output naming:

- `CLI-Pulse-Bar-vX.Y.Z.dmg`

### Signing and notarization prerequisites

For a DMG that opens without the extra Gatekeeper override flow, this machine
must have:

- a `Developer ID Application` certificate installed in Keychain
- notarization credentials configured for `notarytool`

Recommended setup:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARYTOOL_KEYCHAIN_PROFILE="cli-pulse-notary"
```

Create the notary profile once:

```bash
xcrun notarytool store-credentials "cli-pulse-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Build a notarized DMG:

```bash
cd "CLI Pulse Bar"
./scripts/build-release.sh --notarize
```

If the machine only has `Apple Development` and not `Developer ID Application`,
outside-App-Store distribution will still trigger Gatekeeper warnings. Do not
publish that build as the "fixed" public release.

### 4. Prepare public-facing content

Update public-facing content only if needed:

- `README.md`
- `docs/index.html`
- `PRIVACY.md`
- `TERMS.md`
- release notes text

This work belongs in the public repo, not the private source repo.

### 5. Publish the release to the public repo

Use the public repo only for distribution steps:

1. Ensure `public/main` still contains only distribution files.
2. Create or update the public release notes.
3. Create the release tag on the public distribution history.
4. Upload the DMG asset to the public GitHub Release.

Example:

```bash
gh release create "vX.Y.Z" "CLI-Pulse-Bar-vX.Y.Z.dmg#CLI-Pulse-Bar-vX.Y.Z.dmg" \
  --repo JasonYeYuhe/cli-pulse \
  --title "CLI Pulse vX.Y.Z" \
  --notes-file /tmp/cli-pulse-release-notes.md
```

Important:

- Never create a public release tag from a source-bearing commit.
- If a tag must be recreated, recreate it on the distribution-only public
  history first, then recreate the release.

### 6. Verify public distribution

After publishing:

- Confirm the GitHub Release page loads.
- Confirm the DMG downloads correctly.
- Confirm GitHub Pages still serves:
  - `https://jasonyeyuhe.github.io/cli-pulse/`
  - `privacy.html`
  - `terms.html`
- Confirm the public repo tree still does not contain source directories.

## Public Repo Maintenance Rules

Allowed changes in `public`:

- legal text updates
- support and FAQ updates
- landing page/download page updates
- release notes
- DMG uploads

Forbidden changes in `public`:

- app source
- helper source
- backend source
- test files
- provider collectors
- internal docs or notes
- archived product code

## AI / Automation Rules

Any AI working in this project must follow:

1. Read `AGENTS.md` first.
2. Treat `origin` as the only source-code remote.
3. Treat `public` as distribution-only.
4. If a task mentions releases, distinguish clearly between:
   - private build work
   - public distribution work
5. Do not push source commits, feature branches, or private implementation
   details to `public`.

## Quick Checklist

Before each release:

- [ ] Product changes merged in private repo
- [ ] Python helper tests pass
- [ ] Swift package tests pass
- [ ] macOS app smoke-tested
- [ ] DMG built and notarized
- [ ] Public release notes prepared
- [ ] Public repo still distribution-only
- [ ] Release tag created on distribution-only commit
- [ ] DMG uploaded to GitHub Release
- [ ] GitHub Pages/download links verified
