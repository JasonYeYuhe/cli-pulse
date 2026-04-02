# CLI Pulse Bar — Provider Support Matrix

## Architecture

Two data paths:

1. **Cloud/Backend** — `APIClient.providers()` → `provider_summary` RPC on Supabase.
2. **Local Mode** (macOS only) — two-phase:
   - **Provider-native collectors** run first for providers with local credentials. Real quota/credits/tier data.
   - **`LocalScanner`** runs second for process detection. Estimated usage only (`quota=nil`, `remaining=nil`).
   - Collector results override scanner summaries. Scanner sessions are always preserved.

## Auth Model

Codex, Claude, and Gemini collectors target **subscription-linked usage/quota endpoints** via local OAuth state:
- Codex: `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage` (ChatGPT subscription)
- Claude: `~/.claude/.credentials.json` → `api.anthropic.com/api/oauth/usage` (Claude subscription OAuth)
- Gemini: `~/.gemini/oauth_creds.json` → `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` (Gemini CLI subscription)

These do **not** use developer API key billing.

## Implemented Local Collectors (16 providers)

| Provider | Collector | Strategy | Data Kind | isAvailable Condition | Confidence |
|---|---|---|---|---|---|
| **Codex** | `CodexCollector` | subscription OAuth → REST | `.quota` | `~/.codex/auth.json` has access_token | high |
| **Claude** | `ClaudeCollector` | subscription OAuth → REST | `.quota` | `~/.claude/.credentials.json` or `CODEXBAR_CLAUDE_OAUTH_TOKEN` | high |
| **Gemini** | `GeminiCollector` | subscription OAuth → REST | `.quota` | `~/.gemini/oauth_creds.json` has access_token | high |
| **OpenRouter** | `OpenRouterCollector` | API token → REST | `.credits` | `config.apiKey` or `OPENROUTER_API_URL` env | high |
| **JetBrains AI** | `JetBrainsAICollector` | local XML file (no network) | `.quota` | `AIAssistantQuotaManager2.xml` exists | high |
| **Ollama** | `OllamaCollector` | local HTTP (no auth) | `.statusOnly` | always (server may be down) | high |
| **Warp** | `WarpCollector` | API token → GraphQL | `.quota` | `config.apiKey` or `WARP_API_KEY`/`WARP_TOKEN` | high |
| **z.ai** | `ZaiCollector` | API token → REST | `.quota` | `config.apiKey` or `Z_AI_API_KEY` | high |
| **Kimi K2** | `KimiK2Collector` | API token → REST | `.credits` | `config.apiKey` or `KIMI_K2_API_KEY`/`KIMI_API_KEY`/`KIMI_KEY` | high |
| **Kilo** | `KiloCollector` | API token → tRPC batch | `.credits` | `config.apiKey` or `KILO_API_KEY` or `~/.local/share/kilo/auth.json` | high |
| **Copilot** | `CopilotCollector` | API token → REST | `.quota` | `config.apiKey` or `COPILOT_API_TOKEN` | high |
| **Cursor** | `CursorCollector` | cookie → REST | `.quota` | `config.manualCookieHeader` or `CURSOR_COOKIE` | medium (cookie-based) |
| **Kimi** | `KimiCollector` | JWT token → Connect RPC | `.quota` | `config.apiKey` or `config.manualCookieHeader` or `KIMI_AUTH_TOKEN` | medium (token-based) |
| **Alibaba** | `AlibabaCollector` | API token → REST (region routing) | `.quota` | `config.apiKey` or `ALIBABA_CODING_PLAN_API_KEY` | medium (region fallback) |
| **MiniMax** | `MiniMaxCollector` | API token → REST; cookie fallback | `.quota` | `config.apiKey` or `MINIMAX_API_KEY` or cookie | medium (API token: high; cookie: fragile) |
| **Augment** | `AugmentCollector` | cookie → REST | `.quota` | `config.manualCookieHeader` or `AUGMENT_COOKIE` | medium (cookie-based) |

## Providers Not Implemented Locally (8 providers)

| Provider | Classification | Reason |
|---|---|---|
| **Kiro** | locally feasible but fragile | Requires CLI PTY spawning (`kiro-cli chat --no-interactive "/usage"`), ANSI text stripping, regex parsing of progress bars and credit lines. CodexBar implements this but the PTY/ANSI path is fragile. |
| **Vertex AI** | locally feasible but heavy | Requires gcloud ADC + Cloud Monitoring timeSeries queries with complex metric filters. Auth is straightforward but the query construction is substantial. |
| **OpenCode** | locally feasible but fragile | Cookie-based + `_server` endpoint returns serialized JavaScript objects, not JSON. Requires regex parsing of opaque response format. |
| **Droid / Factory** | needs more research | Multi-layer auth fallback: stored bearer tokens, WorkOS refresh token minting, LevelDB local storage extraction, cookie chains across multiple domains. Too complex for a clean single-pass. |
| **Antigravity** | locally feasible but fragile | Local process probe: detect `language_server_macos` process, extract CSRF token from command line flags, discover listening ports via `lsof`, Connect RPC to internal protobuf endpoint. Internal protocol, no stability guarantees. |
| **Perplexity** | needs more research | No documented subscription quota API. Developer API key billing exists but subscription usage endpoint not confirmed. |
| **Amp** | needs more research | No documented local auth file, CLI usage command, or public usage API found in CodexBar reference. |
| **Synthetic** | N/A | Testing/development provider, not a real service. No collector needed. |

## Backend Contract

For providers without local collectors, the backend `provider_summary` RPC must return:

```json
{
  "provider": "ProviderName",
  "today_usage": 12000,
  "total_usage": 85000,
  "estimated_cost": 0.85,
  "quota": 200000,
  "remaining": 115000,
  "plan_type": "Free",
  "reset_time": "2026-04-03T00:00:00Z",
  "tiers": [{"name": "Default", "quota": 200000, "remaining": 115000, "reset_time": "..."}]
}
```

## Testing

```bash
cd CLIPulseCore && swift test
```

111 tests across 17 test suites, 0 failures.
