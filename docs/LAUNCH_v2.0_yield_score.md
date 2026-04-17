# CLI Pulse v2.0 — Yield Score Launch Pack

> Launch target: 2026-04-30 (~2 weeks from spec, dev complete 2026-04-17).
> Killer feature: cost-to-code yield (`$0.42 / commit` per provider).

---

## 1. Pre-launch checklist

### Code

- [x] Stages 0–7 shipped and pushed to main
- [x] Migration `migrate_v0.14_yield_score.sql` applied to prod
- [x] Migration `migrate_v0.15_track_git_activity.sql` applied to prod
- [x] CLI Pulse Bar builds clean on macOS 13
- [x] Swift tests: 13 yield + 186 existing = 199 passing
- [x] Python tests: 18 yield + existing suite passing
- [ ] Bump app marketing version to 2.0 (Info.plist, project.pbxproj)
- [ ] Bump helper version constant to 2.0
- [ ] Smoke test on a fresh user account with no prior data
- [ ] Smoke test on Jason's primary account (real data, expect Yield Card to populate within 1 sync cycle of enabling toggle)

### Distribution

- [ ] Archive + upload macOS build via Xcode → ASC
- [ ] Archive + upload iOS build via Xcode → ASC
- [ ] Update `appstore/description.txt` with Yield Score paragraph
- [ ] Update `appstore/whats-new-v2.0.txt` (template below)
- [ ] Capture 1 Yield Card screenshot at iPhone 6.7" + Mac 1280×800

### Comms

- [ ] Final blog post (draft below)
- [ ] Tweet thread (draft below)
- [ ] Demo video (script below)
- [ ] DM 5 power users 24h before public launch
- [ ] Schedule HN Show post for the morning of launch (Tuesday or Wednesday best)

---

## 2. App Store "What's New" copy

> CLI Pulse 2.0 introduces **Yield Score** — your AI spend per git commit.
>
> See exactly which AI tool is producing code worth its subscription. Cursor at $1.67 / commit vs Codex at $0.32 / commit? Now you'll know.
>
> Everything stays on-device until you opt in. Only hashed metadata leaves your Mac — never your code, messages, or diffs.
>
> Pro feature. Enable in Settings → Privacy → Track git activity.

---

## 3. Blog post draft

**Title:** I built a tool to find out if Cursor is worth $20/month. Then I open-sourced the math.

**Body (~600 words):**

I pay for four AI coding subscriptions. Claude Pro, Cursor Pro, Codex, and Gemini Advanced. Combined: $90/month, every month, automatically renewing.

I have no idea which of them is actually producing the code I ship.

Six months ago I shipped CLI Pulse — a menu-bar app that aggregates token usage and remaining quota across 26 AI providers. It answered "how much am I burning right now?" but it never answered the question I actually cared about: **am I getting my money's worth?**

Today I'm shipping Yield Score, the answer to that question.

### The metric

For every commit you make in a tracked repo, CLI Pulse looks at which AI tools were active during that work session and assigns the commit weight to each tool, normalized so the total weight per commit always equals 1.0. Then it divides total cost by total weighted commits per provider.

```
Last 30 days

Codex      $15.00 → 47 commits   $0.32 / commit  ⭐ best
Claude     $42.10 → 89 commits   $0.47 / commit
Cursor     $20.00 → 12 commits   $1.67 / commit  ⚠️ outlier
```

That's it. No vanity metrics. No lines of code (proxy that lies). No PR count (rewards bikeshedding). Just: how much money produced how many real commits.

### The privacy story

I'd never use a tool that uploaded my git history to a third party, so I didn't build one.

What leaves your Mac when you opt into Yield Score:

- The commit hash (a SHA1, already public if you push to GitHub)
- An HMAC of your project path, salted with a per-device secret you never see
- The commit timestamp
- A flag for whether it's a merge commit (so we can exclude them)

What never leaves:

- Commit messages, diffs, file paths
- Author name or email
- Any unpushed commits, branches, or working-tree state

The HMAC is computed locally with a secret stored in your Mac Keychain. Even if Supabase were breached, an attacker couldn't enumerate-guess your project paths.

The whole thing is opt-in. Off by default.

### What's next

Yield Score is the first thing CLI Pulse does that competitors don't. Helicone has spend dashboards. Vantage has cost forecasting. None of them know what your AI actually produced.

In v2.1 I want to add per-PR aggregation and a "Cost-to-Quality" view (commits that survived the next 30 days vs ones that got reverted). Let me know what would make this useful for you: jason@clipulse.app.

---

## 4. Tweet thread

> 1/ Shipped CLI Pulse 2.0 today.
>
> The new feature answers a question every paying-AI-developer asks but no tool answers: **which subscription is actually producing my code?**
>
> Yield Score: AI cost per git commit. Per provider. On-device.

> 2/ Example from my last 30 days:
>
> Codex   $15 → 47 commits   $0.32/commit ⭐
> Claude  $42 → 89 commits   $0.47/commit
> Cursor  $20 → 12 commits   $1.67/commit ⚠
>
> Cursor is the outlier. I had no idea until today.

> 3/ How attribution works:
>
> When you commit, CLI Pulse looks at which AI sessions were active in your project during the work window and divides the credit. Normalized so total per-commit weight is always 1.0 (no inflation).

> 4/ What leaves your Mac:
>
> ✅ commit hash, HMAC of project path, timestamp, is_merge flag
>
> ❌ commit messages, diffs, file paths, author identity
>
> The HMAC is salted with a per-device secret in your Keychain. Off by default.

> 5/ Built with Codex review on every architectural decision. Pair-programming with a skeptical reviewer turns out to be a great way to catch SQL aggregation bugs before they ship.
>
> Free for 7-day window, Pro unlocks 30 / 90 day breakdowns.
>
> https://clipulse.app

---

## 5. Demo video script (~30 seconds)

| t | Visual | Voiceover |
|---|---|---|
| 0:00 | Mac menu bar, click CLI Pulse icon | "I pay for four AI subscriptions. I had no idea which one was producing my code." |
| 0:04 | Overview tab scrolls to Yield Score card | "Until today." |
| 0:06 | Card zoom: shows Codex $0.32, Claude $0.47, Cursor $1.67 | "Cost per commit. Per provider. From your real git history." |
| 0:11 | Click "View detail" → DetailView | "Per-day breakdown. Ambiguous attributions flagged." |
| 0:16 | Cut to Settings → Privacy → toggle | "Off by default. When you opt in, only hashed metadata leaves your Mac." |
| 0:20 | List on screen: ✅ commit hash, HMAC project path · ❌ messages, diffs, file paths | "Your code stays on your machine." |
| 0:26 | CLI Pulse logo + "v2.0 today" | "Yield Score, in CLI Pulse 2.0. clipulse.app" |
| 0:30 | End | |

Recording notes: use built-in macOS screen recording (Shift+Cmd+5), 30 fps, with mouse cursor visible. Mac mini + cleanup wallpaper. Voice over in QuickTime, mux in iMovie.

---

## 6. HN Show post

**Title:** Show HN: CLI Pulse 2.0 – AI cost per git commit, computed on-device

**Body:**

I built CLI Pulse to track usage across the 26 AI tools I pay for. The new 2.0 feature adds cost-to-code yield — i.e. "Cursor is costing me $1.67 per commit, Codex is $0.32".

Attribution: each commit's weight is normalized across all AI sessions active in that project during the work window, so the total per-commit weight always sums to 1.0 (avoids the obvious double-counting bug).

Privacy: opt-in, off by default. Only commit hash, HMAC of project path, timestamp, and merge flag leave the device. No messages, diffs, file paths, or author identity. HMAC salted with a per-device secret in Keychain.

Stack: Python helper daemon (macOS launchd), Supabase backend, SwiftUI menu-bar app. Schema migration + Swift + Python tests on GitHub.

Happy to answer questions on attribution math, privacy choices, or why I picked Supabase.

---

## 7. Risk register for launch week

| Risk | Watch | Response |
|---|---|---|
| Apple review surprise (mental-health-style scrutiny on git tracking) | ASC review status | Already opt-in with prominent disclosure; respond with screenshot of consent dialog |
| Yield Score numbers wildly off for power users with overlapping sessions | First 5 user reports | Tune the 30-min session window or default to single-best-attribution if ambiguous% high |
| Supabase RPC `ingest_commits` slow with high-commit users | DB CPU during launch day | Add a per-user throttle (max 1000 commits/min) hotfix |
| Helper daemon git scan eats disk on huge repos | User reports | The 10s subprocess timeout already protects; document worst case |
| Privacy-suspicious HN comments | HN Show post | The blog post is the answer; have it ready to link |
