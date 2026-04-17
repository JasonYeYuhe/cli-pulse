# CLI Pulse v2.0 — Cost-to-Code Yield Score

> Plan date: 2026-04-17
> Reviewed by: Codex (2026-04-17, 3 critical issues found and addressed in v2 of this doc)
> Status: READY FOR EXECUTION

---

## 一、Why this feature

### Strategic context (from PORTFOLIO_REVIEW_2026-04-16.md)

CLI Pulse 在 portfolio 里被标为 **#1 priority**（developer-paying market, $5-20K MRR ceiling — 比 Kinen 的 $500-1.5K 高 10x）。Cost-to-Code Yield Score 被标为 **the killer feature** —— 因为它回答了用户已在问但没工具能答的问题：

> "Cursor $20/mo 值不值？它给我产了多少代码？"
> "Claude Pro vs Codex Pro，哪个对我 ROI 更高？"
> "我这个月花在 AI 上的钱，换成了多少 commits？"

### Why competitors don't have this

- **Helicone / Vantage**：只追踪 token usage，不连接 git。
- **Cursor / Codex / Claude 自己**：只露自己单个产品的数据。
- **CLI Pulse 的独特位置**：唯一一个**跨 provider 聚合 + 本地（能访问 git）**的工具。这是结构性优势。

### Success metric

发布后 30 天内：
- Pro user 留存率 +10pp（从当前 baseline）
- Twitter/HN launch post 触达 5K+ 开发者
- "yield score" 出现在 1+ 第三方推荐文章

---

## 二、Feature scope (MVP)

### What it shows

OverviewTab 加一个新卡片 **"Yield Score"**，按时段（7天/30天）分 provider 显示：

```
┌─────────────────────────────────────┐
│  Yield Score · Last 30 days         │
├─────────────────────────────────────┤
│  Claude        $42.10 → 89 commits  │
│                $0.47 / commit       │
│                                     │
│  Cursor        $20.00 → 12 commits  │
│                $1.67 / commit ⚠️    │
│                                     │
│  Codex         $15.00 → 47 commits  │
│                $0.32 / commit ⭐    │
│                                     │
│  [View detail →]                    │
└─────────────────────────────────────┘
```

⭐ = best yield in range；⚠️ = >2x average (potentially poor ROI)。

点 "View detail" 跳到独立 YieldScoreView，显示：
- 每个 commit 的归属 (provider, session id, cost, timestamp)
- 时间趋势图（cost/commit over time）
- Per-project breakdown（哪些 repo 用 AI 最多）

### What it does NOT show in MVP

- **PR-level grouping**（Phase 2）：commit 是更原子的；PR 需要 git remote/GitHub API。
- **LOC metrics** (`+150 -23`)：noisy proxy，更易误导。先用 commit count，等用户要 LOC 再加。
- **Team aggregation**：Phase 2，需要 multi-user data。
- **Android**：Phase 2，需要 Android 端能跑 git scanner（需要 Termux 或类似环境，复杂）。

---

## 三、Architecture

### Linkage: how do we attribute commits to sessions?

**核心问题**：用户在 Claude 里 chat 1 小时，然后 commit 3 次。怎么把这 3 个 commits 归给 Claude？

**方案**：normalized single-commit attribution（修正 Codex 发现的 double-credit 问题）

1. **Project match**（必要条件）— commit 必须在 session 的 project_hash 下
2. **Time proximity scoring** — 对每个 commit 找所有 candidate sessions（同 project_hash + commit time ∈ [started_at, last_active_at + 30min]），按 |commit_time − last_active_at| 计算 recency score
3. **Normalize to sum=1.0**：每个 commit 的总归属权重永远是 1.0；分给 candidates 按 recency 加权
4. **Ambiguity flag**：如果 top candidate 的 weight < 0.6（即没有明显 winner），mark 这个 commit 为 `ambiguous=true`，UI 里单独标"unclear attribution"

**示例**：
- 用户在 Claude (active 14:00-15:00) 和 Cursor (active 14:30-15:30) 同时开
- 14:55 commit 一次
- Claude: |14:55-15:00| = 5min；Cursor: |14:55-15:30| = 35min
- Claude weight = 35/(35+5) = 0.875；Cursor = 5/40 = 0.125
- Top weight 0.875 > 0.6 → 不 ambiguous，主要归 Claude

**Edge cases**:
- Session 期间 0 commits → 归 0（不平均分摊到其他时段）
- 5 个 sessions 都 active 同窗内 → 都得部分 weight，但 sum=1.0（不会 inflation）
- Top weight 0.4 (3 sessions 旗鼓相当) → ambiguous=true，UI 显示但不计入 yield 主指标

### Data flow

```
[git log] ──(helper daemon)──→ [Supabase: commits table]
                                        ↓
                                   [link by project+time]
                                        ↓
                            [Supabase: session_commit_links]
                                        ↓
                            [APIClient.fetchYieldScore]
                                        ↓
                              [CLIPulseCore: YieldScore model]
                                        ↓
                              [OverviewTab: YieldScoreCard]
```

### Privacy (修正 Codex 发现的 hashing 是 theater 问题)

**核心约束**：commit hash + project path 是用户的代码 metadata，不能盲目上传。

策略:
- **commit hash**：上传 SHA1 (40 char) — 不能反推 diff 内容，但 public repo 可关联到 GitHub。可接受（用户已公开此信息）
- **commit message**：**永不上传**，只存本地（如未来需要搜索功能再单独 opt-in）
- **project_hash**：用 **per-user salted HMAC-SHA256** 替代普通 hash —— 即使数据库泄露，攻击者也无法字典枚举常见 repo 路径
  ```
  project_hash = HMAC-SHA256(user_secret, absolute_project_path)
  user_secret 在 Helper daemon 首次启动时生成，存在 Keychain，永不上传
  ```
- **author_email**：v2.0 **完全不存储**（Codex 建议）。当前用户场景里 author 通常就是 user 自己，不需要区分
- **新加 settings toggle**：`Settings → Privacy → "Track git activity"`，默认关闭，opt-in
- **Local-first option**：Settings 里加另一个 toggle "Keep yield data local-only" —— 启用后只本地计算 yield，不上传任何 commit data 到 Supabase（trade-off: cross-device sync 失效）

---

## 四、Implementation plan

### Stage 0: Schema migration (1 day)

**File**: `supabase/migrations/2026_04_17_yield_score.sql`

```sql
-- 1. Add project_hash to sessions (Codex: backwards-compat NULL existing rows)
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS project_hash TEXT;
CREATE INDEX IF NOT EXISTS sessions_user_project_active_idx
  ON public.sessions (user_id, project_hash, last_active_at DESC);

-- Note: existing sessions get NULL project_hash and won't match.
-- This is by design — old sessions pre-date git tracking. New sessions get hash via writers.
-- Backfill optional: helper daemon could re-classify projects on its next run.

-- 2. Commits collected from helper daemon
CREATE TABLE public.commits (
  id TEXT PRIMARY KEY,                    -- "{user_id}:{commit_hash}"
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  commit_hash TEXT NOT NULL,
  project_hash TEXT NOT NULL,             -- HMAC-SHA256 with per-user secret
  committed_at TIMESTAMPTZ NOT NULL,
  is_merge BOOLEAN DEFAULT false,         -- Codex: filter merge commits from yield
  inserted_at TIMESTAMPTZ DEFAULT now(),
  -- intentionally NO message, NO diff, NO path, NO author email
  UNIQUE (user_id, commit_hash)
);
CREATE INDEX commits_user_time_idx ON public.commits (user_id, committed_at DESC);

-- 3. Link table with normalized weights (Codex fix: weight per commit sums to 1.0)
CREATE TABLE public.session_commit_links (
  session_id TEXT NOT NULL,
  commit_id TEXT NOT NULL REFERENCES public.commits(id) ON DELETE CASCADE,
  weight REAL NOT NULL CHECK (weight > 0 AND weight <= 1),
  is_ambiguous BOOLEAN DEFAULT false,
  linked_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (session_id, commit_id)
);
CREATE INDEX session_commit_links_session_idx ON public.session_commit_links (session_id);
CREATE INDEX session_commit_links_commit_idx ON public.session_commit_links (commit_id);

-- 4. Daily rollup table (Codex: don't query raw join in production)
CREATE TABLE public.yield_score_daily (
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  day DATE NOT NULL,
  total_cost NUMERIC(10,4) NOT NULL DEFAULT 0,
  weighted_commit_count NUMERIC(10,4) NOT NULL DEFAULT 0,    -- sum of weights, not raw count
  raw_commit_count INTEGER NOT NULL DEFAULT 0,               -- for "X attempted attribution" display
  ambiguous_commit_count INTEGER NOT NULL DEFAULT 0,
  last_recomputed_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, provider, day)
);

-- RLS
ALTER TABLE public.commits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_commit_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.yield_score_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY commits_owner ON public.commits FOR ALL USING (user_id = auth.uid());
CREATE POLICY session_commit_links_owner ON public.session_commit_links FOR ALL
  USING (EXISTS (SELECT 1 FROM public.commits c WHERE c.id = commit_id AND c.user_id = auth.uid()));
CREATE POLICY yield_score_daily_owner ON public.yield_score_daily FOR ALL USING (user_id = auth.uid());

-- 5. RPC: ingest_commits with NORMALIZED attribution
CREATE OR REPLACE FUNCTION public.ingest_commits(
  p_commits jsonb  -- [{commit_hash, project_hash, committed_at, is_merge}]
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_commit jsonb;
  v_commit_id TEXT;
  v_committed_at TIMESTAMPTZ;
  v_project_hash TEXT;
  v_total_recency NUMERIC;
  v_top_weight NUMERIC;
BEGIN
  FOR v_commit IN SELECT * FROM jsonb_array_elements(p_commits) LOOP
    v_commit_id := v_user_id::text || ':' || (v_commit->>'commit_hash');
    v_committed_at := (v_commit->>'committed_at')::timestamptz;
    v_project_hash := v_commit->>'project_hash';

    INSERT INTO public.commits (id, user_id, commit_hash, project_hash, committed_at, is_merge)
    VALUES (v_commit_id, v_user_id, v_commit->>'commit_hash', v_project_hash, v_committed_at,
            COALESCE((v_commit->>'is_merge')::boolean, false))
    ON CONFLICT (user_id, commit_hash) DO NOTHING;

    -- Skip merge commits in attribution
    IF COALESCE((v_commit->>'is_merge')::boolean, false) THEN CONTINUE; END IF;

    -- Compute recency-based weights for candidate sessions
    -- recency_score = 1.0 - (|commit_time - last_active_at| / 1800s), clamped to [0.05, 1.0]
    WITH candidates AS (
      SELECT s.id AS session_id,
             GREATEST(0.05,
               1.0 - LEAST(1.0,
                 EXTRACT(EPOCH FROM ABS(v_committed_at - s.last_active_at)) / 1800.0
               )
             ) AS recency_score
      FROM public.sessions s
      WHERE s.user_id = v_user_id
        AND s.project_hash = v_project_hash
        AND v_committed_at BETWEEN s.started_at AND (s.last_active_at + interval '30 minutes')
    ), totals AS (
      SELECT SUM(recency_score) AS total_score FROM candidates
    ), normalized AS (
      SELECT c.session_id, c.recency_score / t.total_score AS weight
      FROM candidates c, totals t
      WHERE t.total_score > 0
    )
    INSERT INTO public.session_commit_links (session_id, commit_id, weight, is_ambiguous)
    SELECT n.session_id, v_commit_id, n.weight,
           NOT EXISTS (SELECT 1 FROM normalized WHERE weight >= 0.6)
    FROM normalized n
    ON CONFLICT (session_id, commit_id) DO NOTHING;
  END LOOP;

  -- Trigger daily rollup recompute for affected days (called separately or via trigger)
  PERFORM public.recompute_yield_scores_for_user(v_user_id);
END;
$$;

-- 6. Daily rollup recompute (Codex: split session-cost from commit-link aggregations)
CREATE OR REPLACE FUNCTION public.recompute_yield_scores_for_user(p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM public.yield_score_daily WHERE user_id = p_user_id;

  WITH session_costs AS (
    -- Per-session cost (NO join with links — fixes Codex SUM duplication bug)
    SELECT s.id, s.provider, s.estimated_cost, date_trunc('day', s.last_active_at)::date AS day
    FROM public.sessions s
    WHERE s.user_id = p_user_id
  ), session_weights AS (
    -- Per-session weighted commit count (separate aggregation)
    SELECT scl.session_id,
           SUM(scl.weight) AS weighted_commits,
           COUNT(*) AS raw_commits,
           SUM(CASE WHEN scl.is_ambiguous THEN 1 ELSE 0 END) AS ambiguous_commits
    FROM public.session_commit_links scl
    JOIN public.commits c ON c.id = scl.commit_id
    WHERE c.user_id = p_user_id
    GROUP BY scl.session_id
  )
  INSERT INTO public.yield_score_daily
    (user_id, provider, day, total_cost, weighted_commit_count, raw_commit_count, ambiguous_commit_count)
  SELECT
    p_user_id,
    sc.provider,
    sc.day,
    SUM(sc.estimated_cost),
    COALESCE(SUM(sw.weighted_commits), 0),
    COALESCE(SUM(sw.raw_commits)::int, 0),
    COALESCE(SUM(sw.ambiguous_commits)::int, 0)
  FROM session_costs sc
  LEFT JOIN session_weights sw ON sw.session_id = sc.id
  GROUP BY sc.provider, sc.day;
END;
$$;
```

**Migration plan for existing sessions**:
- New sessions get `project_hash` from updated writers (Stage 1.5)
- Old sessions stay NULL → naturally excluded from yield calc (correct — no commit data exists for them anyway)
- No backfill needed

### Stage 1: project_hash producer plumbing (2 days) — Codex critical fix

**Problem**: Today's collectors only emit `project` (display name string). Yield scoring needs `project_hash` on every session row, computed deterministically from absolute project path with per-user secret.

**Files modified**:
- `helper/system_collector.py:1286-1316` — when computing `project`, also compute `project_hash = HMAC-SHA256(user_secret, abs_path)` and submit alongside
- `helper/cli_pulse_helper.py:198-229` — extend session payload schema with `project_hash`
- `CLI Pulse Bar/CLIPulseHelper/HelperDaemon.swift:33-55,256-270` — same on Swift side
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/LocalScanner.swift:274-292` — emit `project_hash` for local-detected sessions
- `docs/api-contracts.yaml:155-172,224-246` — update SessionPayload schema
- New: `helper/user_secret.py` — generate/load per-user 32-byte secret on first run, persist in OS Keychain (or `~/.cli_pulse/secret.bin` with 0600 perms as fallback)
- New: `CLI Pulse Bar/CLIPulseHelper/UserSecret.swift` — Keychain-backed secret manager

**Determinism**: Both Python and Swift sides MUST produce same `project_hash` for same path + secret. Test with shared fixture.

**Backwards compat**: Server accepts sessions without `project_hash` (legacy clients), but those sessions never link to commits.

### Stage 2: Helper daemon git scanner (2 days) — Codex revised cadence

**File**: `helper/git_collector.py` (new)

**Cadence (Codex fix: not every 60s)**:
- **Trigger 1**: Whenever the active-session set changes (new session starts or one disappears) — scan affected projects
- **Trigger 2**: Backstop every 10 minutes while ANY tracked session is active
- **Trigger 3**: Once 5 minutes after a session disappears (catch lingering commits)
- **Never**: while no sessions active (don't scan unrelated repos)

```python
class GitCollector:
    def __init__(self, supabase_client, user_secret: bytes):
        self.client = supabase_client
        self.user_secret = user_secret
        self.last_seen_commit_per_project: dict[str, str] = {}

    def scan_project(self, project_path: Path) -> list[dict]:
        """Run `git log` and return new commits since last scan.

        Excludes merge commits (--no-merges), filters by --since to bound work.
        """
        if not (project_path / ".git").exists():
            return []
        try:
            result = subprocess.run(
                ['git', '-C', str(project_path), 'log',
                 '--no-merges',                          # exclude merge commits
                 '--since=2 hours ago',
                 '--pretty=format:%H|%aI|%P'],          # hash|iso_date|parent_hashes
                capture_output=True, text=True, timeout=10
            )
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            logger.warning(f"git log failed for {project_path}: {e}")
            return []

        commits = []
        last_seen = self.last_seen_commit_per_project.get(str(project_path))
        for line in result.stdout.strip().split('\n'):
            if not line: continue
            parts = line.split('|')
            commit_hash, committed_at, parents = parts[0], parts[1], parts[2] if len(parts) > 2 else ''
            if commit_hash == last_seen: break  # we've seen everything older
            commits.append({
                'commit_hash': commit_hash,
                'project_hash': hmac.new(self.user_secret, str(project_path).encode(), 'sha256').hexdigest(),
                'committed_at': committed_at,
                'is_merge': len(parents.split()) > 1,
            })

        if commits:
            self.last_seen_commit_per_project[str(project_path)] = commits[0]['commit_hash']
        return commits
```

**Failure modes handled** (Codex):
- git not installed → caught by `FileNotFoundError`, log warning, skip
- repo corrupt → `git log` returns non-zero, caught
- huge repo → `--since=2 hours ago` bounds work; 10s timeout
- permission denied → caught, skip silently

**Setting persistence**: Codex correction — settings live in `user_settings` table, NOT `profiles.preferences`. Helper reads via `APIClient.fetchUserSettings()`.

### Stage 2: Apple data layer (1-2 days)

**Files**:
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/Models.swift` — new `YieldScore` model
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/APIClient.swift` — `fetchYieldScores(range:)` method
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/AppState.swift` — `yieldScores: [YieldScore]` published property + `refreshYieldScores()` method

```swift
public struct YieldScore: Codable, Identifiable, Sendable {
    public let id: UUID
    public let provider: String                 // ProviderKind raw
    public let rangeStart: Date
    public let rangeEnd: Date
    public let totalCost: Double
    public let commitCount: Int
    public var costPerCommit: Double? {
        commitCount > 0 ? totalCost / Double(commitCount) : nil
    }
}
```

API call to PostgREST view `yield_scores` aggregated client-side over chosen range (7d/30d/90d).

### Stage 3: macOS UI (2-3 days)

**Files**:
- `CLI Pulse Bar/CLI Pulse Bar/OverviewTab.swift` — add `YieldScoreCard()` between cost section and provider breakdown
- `CLI Pulse Bar/CLI Pulse Bar/YieldScoreCard.swift` (new) — compact card view
- `CLI Pulse Bar/CLI Pulse Bar/YieldScoreDetailView.swift` (new) — full detail screen with chart

Key UX details:
- **Empty state**: "Enable git tracking in Settings to see your yield score" + button
- **Star/warn icons**: ⭐ for best, ⚠️ for >2x average (compute client-side)
- **No commits state**: Show "0 commits — try writing some code in a tracked repo!" — don't hide
- **Settings entry**: `SettingsTab.swift` add `Track git activity` toggle (Privacy section)

### Stage 4: iOS read-only — **CUT to v2.1** (Codex recommendation)

Per Codex review: iOS read-only is technically easy (DataRefreshManager already shared), but pushes v2.0 timeline tight. Defer to v2.1 (1 week after launch). v2.0 ships macOS-only.

If we want a teaser on iOS in v2.0: just add a single "Yield Score available on macOS" placeholder card in `CLI Pulse Bar/CLI Pulse Bar iOS/iOSOverviewTab.swift` (correct file path; previous draft pointed to non-existent `CLI Pulse iOS/Views/OverviewView.swift`).

### Stage 5: Tests (1-2 days)

**Swift tests** (`CLIPulseCore/Tests/`):
- `YieldScoreTests.swift` — model serialization, costPerCommit edge cases
- `APIClientTests.swift` — extend with mock yield score fetch

**Python tests** (`helper/tests/`):
- `test_git_collector.py` — git log parsing, project_hash determinism, author_email_hash determinism, dedup logic

**Supabase tests** (`supabase/tests/`):
- SQL test: ingest_commits with overlapping session windows produces correct link_strength

### Stage 6: Settings + onboarding (1 day)

- macOS Settings → Privacy → "Track git activity" toggle (off by default)
- First-time enable: dialog explaining what's collected (commit hash, hashed project path, hashed author email — explicit, no message/diff/path)
- iOS Settings: read-only display of "git tracking is enabled on macOS helper"

### Stage 7: Launch prep (parallel during dev)

- Blog post / Twitter thread draft: "Why we built Yield Score — and what it taught us about Claude vs Cursor"
- 30-second demo video script
- Pricing decision: keep in Pro tier (this IS the Pro killer feature)

---

## 五、Timeline (revised after Codex review)

Sequential dev (1 person, focused work):
- Stage 0 (schema migration): 1 day
- Stage 1 (project_hash producer plumbing): 2 days ← Codex critical addition
- Stage 2 (helper git scanner): 2 days
- Stage 3 (Apple data layer): 1-2 days
- Stage 4 (macOS UI): 2-3 days
- Stage 5 (iOS read-only): **CUT to v2.1**
- Stage 6 (tests): 1-2 days
- Stage 7 (settings + onboarding): 1 day
- Stage 8 (launch prep): parallel

**Total: 10-13 days**, target ship date 2026-04-30 (≈ 2 weeks). Codex flagged real risk that 9-13 was optimistic and `project_hash` plumbing is the actual blocker — adding Stage 1 explicitly as 2 days makes the timeline more honest.

---

## 六、Risks & open questions

### Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Privacy concerns from devs | High | Explicit opt-in + per-user salted HMAC + no message/diff upload + local-only mode |
| Linkage accuracy too low | Medium | Normalized weighting (sum=1) + ambiguous flag for unclear cases (Codex fix) |
| Helper daemon needs git installed | High | Detect git absence via FileNotFoundError, log warning silently |
| Multiple sessions overlap → inflation | **FIXED** | Normalized attribution (Codex fix) makes total weight per commit always 1.0 |
| Yield based on ESTIMATED cost | High | Label "Estimated Yield" in UI when provider cost is estimate vs actual API-reported (Codex fix) |
| Merge commits inflate count | Medium | `--no-merges` filter + `is_merge` flag in DB (Codex fix) |
| Aggregation SQL slow at scale | Medium | Daily rollup table `yield_score_daily` (Codex fix) — never query raw join |
| `project_hash` not present on old sessions | Low | NULL = naturally excluded from yield (correct behavior, no backfill) |
| Some users use git via UI (Tower, Fork) | Low | Doesn't matter — we read git log directly |
| Cursor doesn't expose session API | Already an issue | Use existing process-based detection |

### Open questions for you

1. **Default opt-in or opt-out for git tracking**: I planned **opt-out (off by default)** for privacy. Some PMs argue opt-in (on by default) for better adoption. Which do you prefer?

2. **Free vs Pro gating**: Yield Score is a clear Pro killer. Lock entirely behind Pro? Or show last 7 days free + 30/90 days Pro?

3. **Public repos vs private**: Should we offer different defaults? Track all by default; user can blacklist specific paths.

4. **Should helper detect commit_hash collisions** (e.g. same hash but different repos)? Edge case but possible.

---

## 七、Success criteria for v2.0 launch

- [ ] All 7 stages shipped & tested
- [ ] No P0/P1 bug in 1 week post-launch
- [ ] 100+ active Pro users have enabled git tracking within 7 days
- [ ] At least 3 organic mentions on Twitter/HN/Reddit
- [ ] Codex review approved (this doc)

---

## 八、Files touched summary

**New files (10)**:
- `supabase/migrations/2026_04_17_yield_score.sql`
- `helper/user_secret.py` (Stage 1: HMAC secret manager)
- `helper/git_collector.py` (Stage 2)
- `helper/tests/test_user_secret.py`
- `helper/tests/test_git_collector.py`
- `CLI Pulse Bar/CLIPulseHelper/UserSecret.swift` (Stage 1)
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/YieldScore.swift`
- `CLI Pulse Bar/CLIPulseCore/Tests/CLIPulseCoreTests/YieldScoreTests.swift`
- `CLI Pulse Bar/CLI Pulse Bar/YieldScoreCard.swift`
- `CLI Pulse Bar/CLI Pulse Bar/YieldScoreDetailView.swift`

**Modified files (~9)**:
- `helper/system_collector.py` (emit project_hash + wire git_collector)
- `helper/cli_pulse_helper.py` (extend session payload schema)
- `CLI Pulse Bar/CLIPulseHelper/HelperDaemon.swift` (emit project_hash)
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/LocalScanner.swift` (emit project_hash)
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/APIClient.swift` (fetchYieldScores + extend session POST)
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/AppState.swift` (yieldScores property)
- `CLI Pulse Bar/CLI Pulse Bar/OverviewTab.swift` (insert YieldScoreCard)
- `CLI Pulse Bar/CLI Pulse Bar/SettingsTab.swift` (track_git_activity toggle, persisted via user_settings table)
- `docs/api-contracts.yaml` (extend SessionPayload + commit-related schemas)
- `CLI Pulse Bar/CLI Pulse Bar iOS/iOSOverviewTab.swift` (placeholder card teaser only — full iOS support in v2.1)
