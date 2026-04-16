# macOS App Store Rejection Fix Plan — v1.8

**Date**: 2026-04-16  
**Submission ID**: 86491f50-6c61-44ee-beb2-6bcbe5619270  
**Review date**: April 15, 2026  
**Device**: MacBook Pro (14-inch, Nov 2024)

---

## Issue 1: Demo Account Login (Guideline 2.1)

**Problem**: Reviewer provided credentials `demo@clipulse.app / DemoReview2026!` but the macOS app's login UI only offers OTP (email code) sign-in. There is no password field. The backend `signInWithPassword()` already works — the UI just doesn't expose it.

**Root cause**: `SettingsTab.swift` loginSection only renders OTP flow (email → 6-digit code). No password input.

**Fix**:
1. Add a password sign-in toggle/section to `SettingsTab.loginSection` — email field + password field + "Sign In" button
2. Keep OTP as the primary flow, add "Sign in with password" as secondary option
3. Reset demo account password via Supabase admin API to ensure `DemoReview2026!` works

**Files changed**:
- `CLI Pulse Bar/CLI Pulse Bar/SettingsTab.swift` — add password login UI
- Supabase admin — reset demo user password

---

## Issue 2: IAP Not Locatable (Guideline 2.1(b))

**Problem**: Reviewer cannot find In-App Purchases (CLI Pulse Pro) within the app. The current flow: Settings → "Upgrade to Pro" button → opens separate window (`openWindow(id: "subscription")`). This is not obvious. The subscription window may also fail to load StoreKit products in sandbox.

**Root cause**: IAP is behind a separate window that the reviewer may not realize opens. The button text doesn't clearly indicate it leads to IAP.

**Fix**:
1. Add inline plan comparison cards directly in the subscription section of Settings for free-tier users (showing product names, prices, and "Subscribe" buttons)
2. Keep the separate SubscriptionView window for detailed management but make IAP accessible directly from the main settings panel
3. Verify StoreKit configuration file has correct product IDs matching App Store Connect

**Files changed**:
- `CLI Pulse Bar/CLI Pulse Bar/SettingsTab.swift` — expand `subscriptionSection` with inline product cards + purchase buttons
- May need to add `@ObservedObject` for SubscriptionManager directly in SettingsTab

---

## Issue 3: Teams Error Message (Guideline 2.1(a))

**Problem**: App displays error message under "Teams" option. 

**Root cause analysis**: The `TeamView` is embedded in `authenticatedSection` and calls `loadTeams()` via `.task {}` immediately on appear. The `myTeams()` API call does:
```swift
guard let uid = userId, Self.isValidUUID(uid) else { throw APIError.invalidResponse }
```
Then queries `team_members?user_id=eq.{uid}&select=team_id,role,joined_at,teams(...)`. 

Potential failure modes:
- `userId` is nil/empty → throws `APIError.invalidResponse`  
- REST response shape `{ team_id, role, joined_at, teams: { id, name, ... } }` doesn't match flat `TeamDTO { id, name, owner_id, ... }` → JSON decode error
- RLS policy blocks the query → Supabase error

The raw `error.localizedDescription` is shown directly to the user — not user-friendly.

**Fix**:
1. **Fix the API query**: Switch `myTeams()` from REST join query to a proper RPC call (`my_teams`) that returns flat `TeamDTO` shape, OR add a wrapper model to decode the nested response and map to `TeamDTO`
2. **Graceful error handling**: Replace raw error display with user-friendly message; don't show error for "no teams" case
3. **Guard against nil userId**: Show "No teams" instead of throwing when userId is unavailable
4. **Create Supabase RPC `my_teams`**: Returns properly shaped team list for the calling user

**Files changed**:
- `CLI Pulse Bar/CLIPulseCore/Sources/CLIPulseCore/APIClient.swift` — fix `myTeams()` 
- `CLI Pulse Bar/CLI Pulse Bar/TeamView.swift` — improve error handling
- Supabase migration — create `my_teams()` RPC function

---

## Issue 4: Account Deletion Missing (Guideline 5.1.1(v))

**Problem**: App supports account creation but has no UI to delete an account. Apple requires account deletion option.

**Root cause**: Backend `deleteAccount()` exists in both `AuthManager` and `APIClient`, and Supabase `delete_user_account` RPC exists. But SettingsTab's `dangerZone` section has no "Delete Account" button. Also, the Supabase function doesn't delete the `auth.users` record (all FK tables have `ON DELETE CASCADE` from `profiles`, so only `profiles` + `auth.users` need explicit deletion).

**Fix**:
1. **Add Delete Account button** to `dangerZone` in `SettingsTab.swift` with destructive styling
2. **Add confirmation dialog** — two-step: first alert explaining consequences, then text confirmation ("DELETE")
3. **Update Supabase function** — simplify to delete `profiles` (cascades to all tables) + delete `auth.users` record
4. **Post-deletion**: clear local tokens, keychain, UserDefaults; sign out and show login

**Files changed**:
- `CLI Pulse Bar/CLI Pulse Bar/SettingsTab.swift` — add delete account UI + confirmation
- Supabase migration — update `delete_user_account()` to also delete `auth.users`

---

## Implementation Order

1. Supabase migrations (RPC functions)
2. `APIClient.swift` — fix myTeams query
3. `SettingsTab.swift` — all UI changes (password login, inline IAP, delete account)
4. `TeamView.swift` — error handling improvements
5. Reset demo account password
6. Build & test

## Risk Assessment

- **Low risk**: All changes are additive UI + backend RPC fixes
- **No breaking changes**: Existing OTP flow untouched, existing data models preserved
- **Cascade safety**: All FKs from profiles have `ON DELETE CASCADE` — verified via schema query
