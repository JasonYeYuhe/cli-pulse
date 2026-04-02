# CLI Pulse Review Fix TODO

> Generated: 2026-04-01
> Source: gemini-review-todo.md (Gemini + Codex 4-round review, 25 items)
> Strategy: P0 → P1 → P2 → ... → P6, sequential fix with verification

---

## P0: Critical Security (5 items)

- [ ] **P0-1** Fix FastAPI passwordless auth
  - Files: `backend/app/main.py`, `backend/app/store.py`, `backend/app/models.py`
  - Add `password_hash` column, bcrypt hashing, separate register/login, negative tests

- [ ] **P0-2** Implement Apple Receipt (JWS) verification
  - Files: `backend/app/store.py:1105`, `tests/test_backend.py:437`
  - Verify Apple certificate chain, reject invalid signatures

- [ ] **P0-3** Fix iOS token storage → Keychain
  - Files: `CLI Pulse Bar/.../RemotePulseRepository.swift:377`, `SettingsTab.swift:615`
  - Migrate UserDefaults token storage to Keychain

- [ ] **P0-4** Helper token isolation
  - Files: `backend/app/store.py:630`, `store.py:667`
  - Issue separate device-scoped credentials for helpers

- [ ] **P0-5** Tighten Supabase helper RPC permissions
  - Files: `backend/supabase/helper_rpc.sql`
  - Remove `security definer`, fix `using (true)` RLS

## P1: Security & Hygiene (5 items)

- [ ] **P1-1** Externalize Supabase config from Info.plist
- [ ] **P1-2** Clean up committed test credentials & demo content
- [ ] **P1-3** Lower Sentry tracesSampleRate (1.0 → 0.05~0.1)
- [ ] **P1-4** Sentry PII scrubbing
- [ ] **P1-5** Fix error handling (empty catch, try?, invalidResponse, DTO fallback)

## P2: Data Integrity (4 items)

- [ ] **P2-1** Fix helper_sync device dedup (device_name → device_id)
- [ ] **P2-2** Wire alert_rules into alert engine (or remove UI)
- [ ] **P2-3** Fix subscription ID mismatch (StoreKit vs backend)
- [ ] **P2-4** Fix digest cadence minute→hour truncation

## P3: Architecture (4 items)

- [ ] **P3-1** Unify two client architectures (needs decision)
- [ ] **P3-2** Split god objects (store.py 3086L, AppState.swift)
- [ ] **P3-3** Refactor SQLiteStore (JSON blob → proper tables)
- [ ] **P3-4** Decouple APIClient from Sentry (ErrorLogger protocol)

## P4: Performance (2 items)

- [ ] **P4-1** Merge duplicate polling loops into shared coordinator
- [ ] **P4-2** Widget refresh strategy (push-driven or freshness-based)

## P5: UX & Polish (5 items)

- [ ] **P5-1** Unify UI language & localization
- [ ] **P5-2** Fix version number mismatch (MenuBarView v0.1.0 vs bundle 1.1.0)
- [ ] **P5-3** Update privacy policy (GitHub OAuth → Apple Sign In + OTP)
- [ ] **P5-4** Add accessibility labels
- [ ] **P5-5** Harden system_collector.py

## P6: Testing (3 items)

- [ ] **P6-1** Add test target for CLI Pulse Bar
- [ ] **P6-2** Enhance backend tests (negative auth, device dedup edge cases)
- [ ] **P6-3** Enhance frontend tests (RemotePulseRepository, token, polling, errors)

---

*25 items total. Progress tracked here and in gemini-review-todo.md.*
