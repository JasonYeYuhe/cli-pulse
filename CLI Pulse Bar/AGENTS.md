# CLI Pulse Bar Agent Note

This directory contains the active app codebase.

Before making changes here, read:

- `/Users/jason/Documents/cli pulse/AGENTS.md`
- `/Users/jason/Documents/cli pulse/README.md`
- `/Users/jason/Documents/cli pulse/REPO_VISIBILITY_STRATEGY.md`
- `/Users/jason/Documents/cli pulse/RELEASE_WORKFLOW.md`

Important:

- `origin` is the private source repo
- `public` is the public distribution repo
- do not push app source to `public` by default
- public `main` is distribution-only and must stay that way
- release/tag work for the public repo must point to distribution-only commits
- validate shared code with:

```bash
swift test --package-path "/Users/jason/Documents/cli pulse/CLI Pulse Bar/CLIPulseCore"
```
