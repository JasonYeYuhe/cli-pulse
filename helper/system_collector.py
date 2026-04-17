from __future__ import annotations

import json as _json
import logging
import os
import re
import sqlite3
import subprocess
import urllib.parse
import urllib.request
from contextlib import closing
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import user_secret as _user_secret_module

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

HELPER_VERSION = "0.2.0"

logger = logging.getLogger("cli_pulse.collector")

PROCESS_PATTERNS: list[tuple[str, str, str]] = [
    # (provider_name, regex_pattern, confidence: high|medium|low)
    ("Codex", r"\bcodex\b", "high"),
    ("Codex", r"\bopenai\b", "medium"),
    ("Gemini", r"\bgemini\b", "high"),
    ("Gemini", r"\bgoogle-generativeai\b", "medium"),
    ("Claude", r"\bclaude\b", "high"),
    ("Cursor", r"\bcursor\b", "high"),
    ("OpenCode", r"\bopencode\b", "high"),
    ("Droid", r"\bdroid\b", "low"),
    ("Antigravity", r"\bantigravity\b", "high"),
    ("Copilot", r"\bcopilot\b|\bgithub.copilot\b", "high"),
    ("z.ai", r"\bz\.ai\b|\bzai\b", "high"),
    ("MiniMax", r"\bminimax\b", "high"),
    ("Augment", r"\baugment\b", "medium"),
    ("JetBrains AI", r"\bjetbrains[\s-]?ai\b|\bjbai\b", "high"),
    ("Kimi K2", r"\bkimi[\s_-]*k2\b", "high"),
    ("Kimi", r"\bkimi\b", "medium"),
    ("Amp", r"\bamp\b", "low"),
    ("Synthetic", r"\bsynthetic\b", "medium"),
    ("Warp", r"\bwarp\b", "medium"),
    ("Kilo", r"\bkilo\b|\bkilo[_-]?code\b", "high"),
    ("Ollama", r"\bollama\b", "high"),
    ("OpenRouter", r"\bopenrouter\b", "high"),
    ("Alibaba", r"\balibaba\b|\bqwen\b|\btongyi\b", "high"),
    ("Kiro", r"\bkiro\b", "high"),
    ("Vertex AI", r"\bvertex[\s_-]?ai\b", "high"),
    ("Perplexity", r"\bperplexity\b", "high"),
    ("Volcano Engine", r"\bvolcano[\s_-]?engine\b|\bvolcengine\b", "high"),
]

IGNORED_COMMAND_PATTERNS: list[str] = [
    r"crashpad",
    r"--type=renderer",
    r"--type=gpu-process",
    r"--utility-sub-type",
    r"codex helper",
    r"electron framework",
    r"\.vscode-server",
    r"--ms-enable-electron",
    r"node_modules/\.bin",
]

# Confidence ranking for deduplication: higher is better
_CONFIDENCE_RANK = {"high": 3, "medium": 2, "low": 1}


@dataclass
class DeviceSnapshot:
    cpu_usage: int
    memory_usage: int


@dataclass
class CollectedSession:
    session_id: str
    name: str
    provider: str
    project: str
    status: str
    total_usage: int
    requests: int
    error_count: int
    started_at: str
    last_active_at: str
    exact_cost: Optional[float]
    cpu_usage: float
    command: str
    collection_confidence: str = "medium"  # high, medium, low
    project_hash: Optional[str] = None  # HMAC-SHA256 of absolute project path; None when path unknown
    project_root: Optional[str] = None  # absolute path; never sent to server, used by git scanner only
    _child_pids: list[str] = field(default_factory=list, repr=False)


@dataclass
class CollectedAlert:
    alert_id: str
    type: str
    severity: str
    title: str
    message: str
    created_at: str
    related_project_id: Optional[str] = None
    related_project_name: Optional[str] = None
    related_session_id: Optional[str] = None
    related_session_name: Optional[str] = None
    related_provider: Optional[str] = None
    related_device_name: Optional[str] = None


@dataclass
class CollectionResult:
    """Full collection result with metadata."""
    device: DeviceSnapshot
    sessions: list[CollectedSession]
    alerts: list[CollectedAlert]
    provider_remaining: dict[str, int]
    helper_version: str = HELPER_VERSION
    collection_errors: list[str] = field(default_factory=list)
    collected_at: str = ""

    def __post_init__(self) -> None:
        if not self.collected_at:
            self.collected_at = datetime.now(timezone.utc).isoformat()


def collect_all() -> CollectionResult:
    """Perform a full collection cycle with graceful degradation."""
    errors: list[str] = []

    # Device snapshot
    try:
        device = collect_device_snapshot()
    except Exception as exc:
        logger.warning("Device snapshot failed: %s", exc)
        errors.append(f"device_snapshot: {exc}")
        device = DeviceSnapshot(cpu_usage=0, memory_usage=0)

    # Sessions
    try:
        sessions = collect_sessions()
    except Exception as exc:
        logger.warning("Session collection failed: %s", exc)
        errors.append(f"sessions: {exc}")
        sessions = []

    # Alerts
    try:
        alerts = collect_alerts(sessions, device)
    except Exception as exc:
        logger.warning("Alert collection failed: %s", exc)
        errors.append(f"alerts: {exc}")
        alerts = []

    # Remaining quota estimates
    try:
        remaining = estimate_provider_remaining(sessions)
    except Exception as exc:
        logger.warning("Quota estimation failed: %s", exc)
        errors.append(f"quota_estimation: {exc}")
        remaining = {}

    return CollectionResult(
        device=device,
        sessions=sessions,
        alerts=alerts,
        provider_remaining=remaining,
        collection_errors=errors,
    )


def collect_device_snapshot() -> DeviceSnapshot:
    cpu_usage = _collect_cpu_usage()
    memory_usage = _collect_memory_usage()
    return DeviceSnapshot(cpu_usage=cpu_usage, memory_usage=memory_usage)


def collect_sessions() -> list[CollectedSession]:
    rows = _process_rows()
    raw_sessions: list[CollectedSession] = []
    secret = _user_secret_module.load_or_create_secret()

    for row in rows:
        if _should_ignore_command(row["command"]):
            continue

        match = _detect_provider(row["command"])
        if match is None:
            continue
        provider, confidence = match

        elapsed_seconds = max(1, _elapsed_to_seconds(row["etime"]))
        started_at = datetime.now(timezone.utc) - timedelta(seconds=elapsed_seconds)
        command = row["command"]
        cpu = float(row["pcpu"])
        project = _guess_project(command)
        project_root = _guess_project_root(command)
        project_hash = _user_secret_module.project_hash(secret, project_root) if project_root else None

        raw_sessions.append(
            CollectedSession(
                session_id=f"proc-{row['pid']}",
                name=_pretty_name(command),
                provider=provider,
                project=project,
                status="Running",
                total_usage=max(500, int(elapsed_seconds * max(1.5, cpu + 1.0))),
                requests=max(1, elapsed_seconds // 45),
                error_count=0,
                started_at=started_at.isoformat(),
                last_active_at=datetime.now(timezone.utc).isoformat(),
                exact_cost=None,
                cpu_usage=cpu,
                command=command,
                collection_confidence=confidence,
                project_hash=project_hash,
                project_root=str(project_root) if project_root else None,
                _child_pids=[row["pid"]],
            )
        )

    # Deduplicate: merge child processes with same provider+project
    deduplicated = _deduplicate_sessions(raw_sessions)
    deduplicated.sort(key=lambda s: (s.cpu_usage, s.last_active_at), reverse=True)
    return deduplicated[:12]


def _deduplicate_sessions(sessions: list[CollectedSession]) -> list[CollectedSession]:
    """Merge sessions with the same provider + project into a single logical session.

    When multiple processes belong to the same provider and project (e.g. parent
    process + child worker), aggregate their usage and keep the highest-confidence
    match as the representative.
    """
    groups: dict[tuple[str, str], list[CollectedSession]] = {}
    for session in sessions:
        key = (session.provider, session.project)
        groups.setdefault(key, []).append(session)

    merged: list[CollectedSession] = []
    for (provider, project), group in groups.items():
        if len(group) == 1:
            merged.append(group[0])
            continue

        # Pick the session with highest confidence as representative
        group.sort(key=lambda s: _CONFIDENCE_RANK.get(s.collection_confidence, 0), reverse=True)
        primary = group[0]

        # Aggregate metrics from children
        total_usage = sum(s.total_usage for s in group)
        total_requests = sum(s.requests for s in group)
        total_errors = sum(s.error_count for s in group)
        total_cpu = sum(s.cpu_usage for s in group)
        all_pids = []
        for s in group:
            all_pids.extend(s._child_pids)

        # Use earliest start, latest active
        earliest_start = min(s.started_at for s in group)
        latest_active = max(s.last_active_at for s in group)

        merged.append(CollectedSession(
            session_id=primary.session_id,
            name=f"{primary.name} (+{len(group) - 1} workers)" if len(group) > 1 else primary.name,
            provider=provider,
            project=project,
            status="Running",
            total_usage=total_usage,
            requests=total_requests,
            error_count=total_errors,
            started_at=earliest_start,
            last_active_at=latest_active,
            exact_cost=None,
            cpu_usage=round(total_cpu, 1),
            command=primary.command,
            project_hash=primary.project_hash,
            project_root=primary.project_root,
            collection_confidence=primary.collection_confidence,
            _child_pids=all_pids,
        ))

    return merged


def collect_alerts(sessions: list[CollectedSession], device_snapshot: DeviceSnapshot) -> list[CollectedAlert]:
    alerts: list[CollectedAlert] = []
    now = datetime.now(timezone.utc).isoformat()

    if device_snapshot.cpu_usage >= 85:
        alerts.append(
            CollectedAlert(
                alert_id=f"cpu-spike-{int(datetime.now().timestamp())}",
                type="Usage Spike",
                severity="Warning",
                title="Device CPU usage is elevated",
                message=f"helper sampled CPU usage at {device_snapshot.cpu_usage}%.",
                created_at=now,
            )
        )

    for session in sessions:
        if session.cpu_usage >= 80:
            alerts.append(
                CollectedAlert(
                    alert_id=f"session-spike-{session.session_id}",
                    type="Usage Spike",
                    severity="Warning",
                    title=f"{session.name} is consuming high CPU",
                    message=f"Process CPU is {session.cpu_usage:.1f}% for {session.provider}.",
                    created_at=now,
                    related_project_id=_project_id(session.project),
                    related_project_name=session.project,
                    related_session_id=session.session_id,
                    related_session_name=session.name,
                    related_provider=session.provider,
                )
            )
        if session.requests >= 400:
            alerts.append(
                CollectedAlert(
                    alert_id=f"session-long-{session.session_id}",
                    type="Session Too Long",
                    severity="Info",
                    title=f"{session.name} has been running for a long time",
                    message="Long-running local agent session detected by helper.",
                    created_at=now,
                    related_project_id=_project_id(session.project),
                    related_project_name=session.project,
                    related_session_id=session.session_id,
                    related_session_name=session.name,
                    related_provider=session.provider,
                )
            )

    return alerts[:6]


# NOTE: Budget alerts are evaluated server-side via evaluate_budget_alerts RPC,
# which has full weekly cost context. Local evaluation was removed because the
# helper daemon only sees currently-active session costs (incomplete data).


def estimate_provider_remaining(sessions: list[CollectedSession]) -> dict[str, int]:
    """Legacy wrapper — returns flat remaining dict for backward compat."""
    quotas = estimate_provider_quotas(sessions)
    return {p: q["remaining"] for p, q in quotas.items()}


def estimate_provider_quotas(sessions: list[CollectedSession]) -> dict[str, dict]:
    """Return per-provider quota info with real API data where possible.

    Tries real API calls for Claude/Codex/Gemini, falls back to static estimates.
    """
    result: dict[str, dict] = {}
    active_providers = {s.provider for s in sessions}

    # Try real API data first for known providers
    for provider in active_providers:
        try:
            if provider == "Claude":
                data = _fetch_claude_usage()
                if data:
                    result["Claude"] = data
                    continue
            elif provider == "Codex":
                data = _fetch_codex_usage()
                if data:
                    result["Codex"] = data
                    continue
            elif provider == "Gemini":
                data = _fetch_gemini_usage()
                if data:
                    result["Gemini"] = data
                    continue
        except Exception as e:
            logging.debug(f"Real quota fetch failed for {provider}: {e}")

        # No real data — skip (don't write fake quota data to DB)

    return result


def _fetch_claude_usage() -> dict | None:
    """Fetch Claude usage via OAuth API → Web session → CLI fallback → plan-only fallback.

    Also writes ~/.clipulse/claude_snapshot.json for the sandboxed app's
    local collector (ClaudeWebStrategy) to use as fallback when OAuth fails.
    """
    token = None
    refresh_token = None
    plan_type = None
    tier_raw = ""

    # Step 1: Read OAuth token + plan from Keychain
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            data = _json.loads(proc.stdout.strip())
            # Support both camelCase and snake_case credential formats
            oauth = data.get("claudeAiOauth", {}) or data.get("claude_ai_oauth", {})
            token = oauth.get("accessToken") or oauth.get("access_token")
            refresh_token = oauth.get("refreshToken") or oauth.get("refresh_token")
            tier_raw = (oauth.get("rateLimitTier") or oauth.get("rate_limit_tier") or "").lower()
            sub_type = (oauth.get("subscriptionType") or "").lower()
            plan_type = _infer_claude_plan(tier_raw, sub_type)
            # Check token expiry and refresh if needed
            exp_ms = oauth.get("expiresAt") or oauth.get("expires_at") or 0
            if isinstance(exp_ms, (int, float)) and exp_ms > 1e12:
                exp_ms = exp_ms / 1000
            if exp_ms and datetime.now(timezone.utc).timestamp() > exp_ms:
                logger.debug("Claude OAuth token expired, attempting refresh")
                refreshed = _refresh_claude_token(refresh_token)
                if refreshed:
                    token = refreshed
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception) as e:
        logger.debug(f"Keychain read failed: {e}")

    # Step 2: Try OAuth usage API if we have a valid token
    if token and token.startswith("sk-ant-oat"):
        api_result = _fetch_claude_oauth_api(token, plan_type)
        if api_result:
            _write_claude_snapshot(api_result, tier_raw, "oauth")
            return api_result

    # Step 3: Try real Claude web usage via sessionKey from desktop/browser cookies
    web_result = _fetch_claude_web_usage(plan_type)
    if web_result:
        _write_claude_snapshot(web_result, tier_raw, "web")
        return web_result

    # Step 4: Try `claude /usage` CLI fallback
    cli_result = _fetch_claude_cli(plan_type)
    if cli_result:
        _write_claude_snapshot(cli_result, tier_raw, "cli")
        return cli_result

    # Step 5: Plan-only fallback (no bars, just badge)
    if plan_type:
        return {
            "quota": 0, "remaining": 0,
            "plan_type": plan_type,
            "reset_time": None, "tiers": [],
        }
    return None


def _refresh_claude_token(refresh_token: str | None) -> str | None:
    """Try to refresh an expired Claude OAuth token using the refresh_token.

    Returns the new access_token on success, None on failure.
    Does NOT update the keychain (Claude CLI owns keychain writes).
    """
    if not refresh_token:
        return None
    # Try known Anthropic OAuth token endpoints
    endpoints = [
        "https://api.anthropic.com/v1/oauth/token",
        "https://console.anthropic.com/v1/oauth/token",
    ]
    for endpoint in endpoints:
        try:
            body = _json.dumps({
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
            }).encode()
            req = urllib.request.Request(
                endpoint,
                data=body,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "CLI-Pulse-Helper/0.2",
                },
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = _json.loads(resp.read())
            new_token = data.get("access_token", "")
            if new_token and new_token.startswith("sk-ant-oat"):
                logger.debug(f"Claude token refresh succeeded via {endpoint}")
                return new_token
        except Exception as e:
            logger.debug(f"Claude token refresh failed via {endpoint}: {e}")
    return None


def _write_claude_snapshot(result: dict, tier_raw: str, source: str) -> None:
    """Write Claude snapshot files for the app's local collector.

    The sandboxed macOS app reads the app-group container path first:
    ~/Library/Group Containers/group.yyh.CLI-Pulse/claude_snapshot.json

    We also keep writing the legacy ~/.clipulse/claude_snapshot.json path for
    compatibility with older builds and command-line diagnostics.
    Schema matches ClaudeHelperContract.swift.
    """
    try:
        # Convert tier-based result back into snapshot format
        tiers = result.get("tiers", [])
        tier_map = {t["name"]: t for t in tiers}

        def _used_pct(name: str) -> int | None:
            t = tier_map.get(name)
            if t is None:
                return None
            return max(0, t["quota"] - t["remaining"])

        snapshot = {
            "session_used": _used_pct("5h Window"),
            "weekly_used": _used_pct("Weekly"),
            "opus_used": _used_pct("Opus (Weekly)"),
            "sonnet_used": _used_pct("Sonnet (Weekly)"),
            "session_reset": tier_map.get("5h Window", {}).get("reset_time"),
            "weekly_reset": tier_map.get("Weekly", {}).get("reset_time"),
            "rate_limit_tier": tier_raw or None,
            "account_email": None,
            "extra_usage": None,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
            "source": source,
        }

        # Handle extra usage tier
        extra = tier_map.get("Extra Usage")
        if extra:
            scale = 100_000
            snapshot["extra_usage"] = {
                "is_enabled": True,
                "monthly_limit": extra["quota"] / scale,
                "used_credits": (extra["quota"] - extra["remaining"]) / scale,
                "currency": "USD",
            }

        snapshot_json = _json.dumps(snapshot, indent=2)
        target_dirs = [
            Path.home() / "Library" / "Group Containers" / "group.yyh.CLI-Pulse",
            Path.home() / ".clipulse",
        ]

        wrote_any = False
        for target_dir in target_dirs:
            try:
                target_dir.mkdir(parents=True, exist_ok=True)
                snapshot_path = target_dir / "claude_snapshot.json"
                snapshot_path.write_text(snapshot_json)
                snapshot_path.chmod(0o600)
                wrote_any = True
                logger.debug(f"Wrote Claude snapshot to {snapshot_path}")
            except Exception as path_error:
                logger.debug(f"Failed to write Claude snapshot to {target_dir}: {path_error}")

        if not wrote_any:
            logger.debug("Claude snapshot write failed for all target paths")
    except Exception as e:
        logger.debug(f"Failed to write Claude snapshot: {e}")


def _write_claude_session_key(session_key: str, source: str) -> None:
    """Write session key file for the app's Web strategy."""
    try:
        payload = _json.dumps({
            "sessionKey": session_key,
            "source": source,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }, indent=2)
        target_dirs = [
            Path.home() / "Library" / "Group Containers" / "group.yyh.CLI-Pulse",
            Path.home() / ".clipulse",
        ]
        for target_dir in target_dirs:
            try:
                target_dir.mkdir(parents=True, exist_ok=True)
                session_file = target_dir / "claude_session.json"
                session_file.write_text(payload)
                session_file.chmod(0o600)
            except Exception as path_error:
                logger.debug(f"Failed to write Claude session key to {target_dir}: {path_error}")
    except Exception as e:
        logger.debug(f"Failed to write Claude session key: {e}")


def _fetch_claude_web_usage(plan_type: str | None) -> dict | None:
    """Fetch Claude usage from the real claude.ai web API using a sessionKey cookie."""
    resolved = _resolve_claude_session_key()
    if not resolved:
        return None

    session_key, source = resolved
    try:
        headers = {
            "Cookie": f"sessionKey={session_key}",
            "Accept": "application/json",
            "User-Agent": "CLI-Pulse-Helper/0.3",
        }
        org_req = urllib.request.Request("https://claude.ai/api/organizations", headers=headers)
        with urllib.request.urlopen(org_req, timeout=15) as resp:
            orgs = _json.loads(resp.read())

        if not isinstance(orgs, list) or not orgs:
            return None
        first = orgs[0]
        org_id = first.get("uuid") or first.get("id")
        if not org_id:
            return None

        usage_req = urllib.request.Request(
            f"https://claude.ai/api/organizations/{org_id}/usage",
            headers=headers,
        )
        with urllib.request.urlopen(usage_req, timeout=15) as resp:
            usage = _json.loads(resp.read())

        result = _parse_claude_api_response(usage, plan_type or "Max")
        if result:
            _write_claude_session_key(session_key, source)
        return result
    except Exception as e:
        logger.debug(f"Claude web usage fetch failed: {e}")
        return None


def _resolve_claude_session_key() -> tuple[str, str] | None:
    """Return a decrypted claude.ai sessionKey from Claude desktop or Chromium browsers."""
    for source_label, db_path, services in _claude_cookie_candidates():
        try:
            session_key = _extract_session_key_from_cookie_db(db_path, services)
            if session_key:
                logger.debug(f"Resolved Claude session key from {source_label}: {db_path}")
                return session_key, source_label
        except Exception as e:
            logger.debug(f"Claude session key extraction failed for {db_path}: {e}")
    return None


def _claude_cookie_candidates() -> list[tuple[str, Path, list[str]]]:
    """Cookie DBs to probe, in priority order."""
    candidates: list[tuple[str, Path, list[str]]] = []

    def add(label: str, path: Path, services: list[str]) -> None:
        if path.exists():
            candidates.append((label, path, services))

    home = Path.home()
    add("claude-desktop", home / "Library" / "Application Support" / "Claude" / "Cookies", [
        "Claude Safe Storage", "Chrome Safe Storage",
    ])
    for path in sorted((home / "Library" / "Application Support" / "Google" / "Chrome").glob("*/Cookies")):
        add(f"chrome:{path.parent.name}", path, ["Chrome Safe Storage"])
    for path in sorted((home / "Library" / "Application Support" / "Microsoft Edge").glob("*/Cookies")):
        add(f"edge:{path.parent.name}", path, ["Microsoft Edge Safe Storage", "Chrome Safe Storage"])
    for path in sorted((home / "Library" / "Application Support" / "BraveSoftware" / "Brave-Browser").glob("*/Cookies")):
        add(f"brave:{path.parent.name}", path, ["Brave Safe Storage", "Chrome Safe Storage"])
    for path in sorted((home / "Library" / "Application Support" / "Chromium").glob("*/Cookies")):
        add(f"chromium:{path.parent.name}", path, ["Chromium Safe Storage", "Chrome Safe Storage"])
    for path in sorted((home / "Library" / "Application Support" / "Arc" / "User Data").glob("*/Cookies")):
        add(f"arc:{path.parent.name}", path, ["Arc Safe Storage", "Chrome Safe Storage"])
    return candidates


def _extract_session_key_from_cookie_db(db_path: Path, keychain_services: list[str]) -> str | None:
    query = """
        SELECT host_key, encrypted_value
        FROM cookies
        WHERE name = 'sessionKey' AND host_key LIKE '%claude.ai%'
        ORDER BY host_key DESC
    """
    with closing(sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)) as conn:
        rows = conn.execute(query).fetchall()

    if not rows:
        return None

    passwords = [pw for service in keychain_services if (pw := _read_safe_storage_password(service))]
    for _host_key, encrypted_value in rows:
        for password in passwords:
            try:
                decrypted = _decrypt_chromium_cookie(encrypted_value, password)
                if decrypted.startswith("sk-ant-sid"):
                    return decrypted
            except Exception:
                continue
    return None


def _read_safe_storage_password(service: str) -> str | None:
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-w", "-s", service],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    except Exception as e:
        logger.debug(f"Safe storage lookup failed for {service}: {e}")
    return None


def _decrypt_chromium_cookie(encrypted_value: bytes, password: str) -> str:
    blob = bytes(encrypted_value)
    if blob.startswith(b"v10"):
        blob = blob[3:]
    key = PBKDF2HMAC(
        algorithm=hashes.SHA1(),
        length=16,
        salt=b"saltysalt",
        iterations=1003,
        backend=default_backend(),
    ).derive(password.encode())
    decryptor = Cipher(
        algorithms.AES(key),
        modes.CBC(b" " * 16),
        backend=default_backend(),
    ).decryptor()
    decrypted = decryptor.update(blob) + decryptor.finalize()
    decrypted = decrypted[:-decrypted[-1]]
    if len(decrypted) > 32:
        host_prefix = decrypted[:32]
        if not all(32 <= b <= 126 for b in host_prefix):
            decrypted = decrypted[32:]
    return decrypted.decode("utf-8", "ignore")


def _infer_claude_plan(tier: str, sub_type: str) -> str:
    """Infer Claude plan display name from rate_limit_tier or subscriptionType."""
    combined = f"{tier} {sub_type}".lower()
    # Match specific Max tiers first (20x before generic max)
    if "max_20x" in combined or "max 20x" in combined:
        return "Max 20x"
    if "max_5x" in combined or "max 5x" in combined:
        return "Max 5x"
    if "max" in combined:
        return "Max 5x"  # default Max → 5x
    for label, keyword in [("Ultra", "ultra"), ("Pro", "pro"), ("Team", "team"),
                           ("Enterprise", "enterprise"), ("Free", "free")]:
        if keyword in combined:
            return label
    return sub_type.capitalize() if sub_type else "Unknown"


def _fetch_claude_oauth_api(token: str, plan_type: str | None) -> dict | None:
    """Call Anthropic OAuth usage API and parse into tiers."""
    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "CLI-Pulse-Helper/0.2",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())
        return _parse_claude_api_response(data, plan_type)
    except Exception as e:
        logger.debug(f"Claude OAuth API failed: {e}")
        return None


def _fetch_claude_cli(plan_type: str | None) -> dict | None:
    """Run Claude CLI to get usage data.

    Note: Claude Code v2.x removed `/usage` slash command.
    This function is kept as a fallback for environments where
    a compatible CLI version is available.
    """
    import shutil
    # Search common Claude CLI locations beyond PATH
    binary = shutil.which("claude")
    if not binary:
        for candidate in [
            str(Path.home() / ".local" / "bin" / "claude"),
            "/usr/local/bin/claude",
            str(Path.home() / ".npm-global" / "bin" / "claude"),
        ]:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                binary = candidate
                break
    if not binary:
        return None
    # Claude Code v2.x: `/usage` is not a valid command.
    # Keep this path for future compatibility but don't expect it to work.
    try:
        proc = subprocess.run(
            [binary, "/usage"],
            capture_output=True, text=True, timeout=15,
            env={**os.environ, "NO_COLOR": "1"},
        )
        if proc.returncode == 0 and proc.stdout.strip():
            result = _parse_claude_usage_output(proc.stdout)
            if result:
                if plan_type:
                    result["plan_type"] = plan_type
                return result
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        logger.debug(f"Claude CLI fallback failed: {e}")
    return None


def _parse_claude_usage_output(output: str) -> dict | None:
    """Parse `claude /usage` CLI output into tier data.

    Uses quota=100 / remaining=100-percent model (percentage-based) to match
    the OAuth API and the local Swift collector.
    """
    tiers = []
    lines = output.splitlines()
    # Track section context: "session" or "week" or "opus" etc.
    section = None
    reset_for_section: dict[str, str | None] = {}

    for line in lines:
        stripped = line.strip().lower()
        if "session" in stripped:
            section = "session"
        elif "week" in stripped and "opus" in stripped:
            section = "opus"
        elif "week" in stripped and "sonnet" in stripped:
            section = "sonnet"
        elif "week" in stripped:
            section = "week"

        if "%" in line:
            pct = _extract_percent(line)
            if pct is not None and section:
                # pct might be "used" or "left" — CLI uses "X% left"
                # _extract_percent returns the raw number; determine semantics
                low = line.strip().lower()
                if "left" in low or "remaining" in low:
                    used = 100 - pct
                else:
                    used = pct
                name_map = {"session": "5h Window", "week": "Weekly",
                            "opus": "Opus (Weekly)", "sonnet": "Sonnet (Weekly)"}
                name = name_map.get(section, section)
                # Avoid duplicate tier names
                if not any(t["name"] == name for t in tiers):
                    tiers.append({"name": name, "quota": 100, "remaining": max(0, 100 - used), "reset_time": None})

        if section and "reset" in line.strip().lower():
            reset = _extract_reset_time(line)
            if reset:
                reset_for_section[section] = reset

    # Attach reset times to matching tiers
    name_to_section = {"5h Window": "session", "Weekly": "week",
                       "Opus (Weekly)": "opus", "Sonnet (Weekly)": "sonnet"}
    for tier in tiers:
        sec = name_to_section.get(tier["name"])
        if sec and sec in reset_for_section:
            tier["reset_time"] = reset_for_section[sec]

    if not tiers:
        return None

    primary = tiers[0]
    return {
        "quota": primary["quota"],
        "remaining": primary["remaining"],
        "plan_type": "Max",
        "reset_time": primary.get("reset_time"),
        "tiers": tiers,
    }


def _parse_claude_api_response(data: dict, plan_type: str | None = None) -> dict | None:
    """Parse Anthropic OAuth usage API response.

    The API returns utilization percentages (0-100) per window, not absolute values.
    We normalize to quota=100, remaining=100-utilization to match the local collector.
    """
    tiers = []

    def _add_window(key: str, name: str, reset_key: str = "resets_at"):
        w = data.get(key)
        if isinstance(w, dict):
            util = w.get("utilization", 0)
            reset = w.get(reset_key)
            tiers.append({"name": name, "quota": 100, "remaining": max(0, 100 - int(util)), "reset_time": reset})

    _add_window("five_hour", "5h Window")
    _add_window("seven_day", "Weekly")
    _add_window("seven_day_opus", "Opus (Weekly)")
    _add_window("seven_day_sonnet", "Sonnet (Weekly)")

    # Extra usage / overage credits
    eu = data.get("extra_usage")
    if isinstance(eu, dict) and eu.get("is_enabled"):
        limit = eu.get("monthly_limit", 0)
        used = eu.get("used_credits", 0)
        if limit and limit > 0:
            scale = 100_000
            tiers.append({
                "name": "Extra Usage",
                "quota": int(limit * scale),
                "remaining": int(max(0, limit - used) * scale),
                "reset_time": None,
            })

    if not tiers:
        return None

    primary = tiers[0]
    return {
        "quota": primary["quota"],
        "remaining": primary["remaining"],
        "plan_type": plan_type or "Max",
        "reset_time": primary.get("reset_time"),
        "tiers": tiers,
    }


def _fetch_codex_usage() -> dict | None:
    """Read Codex usage via auth.json token → OpenAI usage API."""
    auth_path = Path.home() / ".codex" / "auth.json"
    if not auth_path.exists():
        return None
    try:

        auth = _json.loads(auth_path.read_text())
        tokens = auth.get("tokens", {})
        # tokens may be flat {"access_token": "...", ...} or nested
        access_token = tokens.get("access_token", "")
        if not access_token:
            for _key, tok in tokens.items():
                if isinstance(tok, dict) and tok.get("access_token"):
                    access_token = tok["access_token"]
                    break
        if not access_token:
            return None

        req = urllib.request.Request(
            "https://chatgpt.com/backend-api/wham/usage",
            headers={
                "Authorization": f"Bearer {access_token}",
                "User-Agent": "CLI-Pulse-Helper/0.1",
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())
            return _parse_codex_usage_response(data)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        logger.debug("Codex usage fetch failed: %s", e)
        return None
    except (KeyError, ValueError, _json.JSONDecodeError) as e:
        logger.debug("Codex usage parse failed: %s", e)
        return None


def _parse_codex_usage_response(data: dict) -> dict | None:
    """Parse OpenAI/Codex wham/usage API response.

    Real format:
    {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":23,"reset_after_seconds":2391,"reset_at":1775054266},...}}
    """
    tiers = []
    plan_type = (data.get("plan_type") or "Plus").capitalize()
    rl = data.get("rate_limit", {})

    pw = rl.get("primary_window")
    if pw:
        pct_used = pw.get("used_percent", 0)
        remaining_pct = 100 - pct_used
        reset_ts = pw.get("reset_at")
        reset_iso = datetime.fromtimestamp(reset_ts, tz=timezone.utc).isoformat() if reset_ts else None
        tiers.append({"name": "Session", "quota": 100, "remaining": remaining_pct, "reset_time": reset_iso})

    sw = rl.get("secondary_window")
    if sw:
        pct_used = sw.get("used_percent", 0)
        remaining_pct = 100 - pct_used
        reset_ts = sw.get("reset_at")
        reset_iso = datetime.fromtimestamp(reset_ts, tz=timezone.utc).isoformat() if reset_ts else None
        tiers.append({"name": "Weekly", "quota": 100, "remaining": remaining_pct, "reset_time": reset_iso})

    if not tiers:
        return None
    return {
        "quota": tiers[0]["quota"],
        "remaining": tiers[0]["remaining"],
        "plan_type": plan_type,
        "reset_time": tiers[0].get("reset_time"),
        "tiers": tiers,
    }


def _get_clipulse_gemini_client_id() -> str:
    """Return CLI Pulse's own OAuth client_id for Gemini token refresh.

    Reads from ~/.config/clipulse/gemini_tokens.json (written by the Swift app
    after the user completes the OAuth flow in the macOS UI).  Returns "" if the
    file is absent or unreadable.
    """
    tokens_path = Path.home() / ".config" / "clipulse" / "gemini_tokens.json"
    try:
        data = _json.loads(tokens_path.read_text())
        return data.get("client_id", "")
    except (OSError, ValueError, _json.JSONDecodeError):
        return ""


def _refresh_gemini_token(creds_path: Path) -> str | None:
    """Refresh expired Gemini OAuth token using refresh_token.

    Uses CLI Pulse's own OAuth client_id (public PKCE client – no secret
    required).  Only works for tokens that originated from CLI Pulse's OAuth
    flow.  Gemini-CLI-originated tokens cannot be refreshed without that CLI's
    private credentials.
    """
    try:
        creds = _json.loads(creds_path.read_text())
        refresh_token = creds.get("refresh_token")
        if not refresh_token:
            return None
        # Only refresh if the file contains its own client_id (CLI Pulse tokens).
        # Gemini CLI tokens require the CLI's own credentials which we no longer extract.
        client_id = creds.get("client_id", "")
        if not client_id:
            logger.debug("Gemini token refresh skipped: no client_id in credential file")
            return None
        body = urllib.parse.urlencode({
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": client_id,
        }).encode()
        req = urllib.request.Request(
            "https://oauth2.googleapis.com/token",
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())
            new_token = data.get("access_token")
            if new_token:
                creds["access_token"] = new_token
                if "expires_in" in data:
                    creds["expiry_date"] = int((datetime.now(timezone.utc).timestamp() + data["expires_in"]) * 1000)
                creds_path.write_text(_json.dumps(creds, indent=2))
                creds_path.chmod(0o600)
                return new_token
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        logger.debug("Gemini token refresh failed: %s", e)
    except (KeyError, ValueError, _json.JSONDecodeError) as e:
        logger.debug("Gemini token refresh parse error: %s", e)
    return None


def _try_read_gemini_token(creds_path: Path) -> str | None:
    """Try to read and return a valid access token from a credential file.

    Refreshes the token if expired (only works for CLI Pulse tokens that have a
    client_id).  Returns None on any failure so the caller can fall back.
    """
    try:
        creds = _json.loads(creds_path.read_text())
        access_token = creds.get("access_token", "")
        expiry = creds.get("expiry_date", 0)
        if isinstance(expiry, (int, float)):
            exp_ts = expiry / 1000 if expiry > 1e12 else expiry
            if exp_ts < datetime.now(timezone.utc).timestamp():
                access_token = _refresh_gemini_token(creds_path) or ""
        return access_token or None
    except (OSError, ValueError, _json.JSONDecodeError) as e:
        logger.debug("Gemini credential read failed for %s: %s", creds_path, e)
        return None


def _fetch_gemini_usage() -> dict | None:
    """Read Gemini usage via OAuth token → Google quota API."""
    # Priority 1: CLI Pulse's own OAuth tokens (written by the Swift app)
    clipulse_path = Path.home() / ".config" / "clipulse" / "gemini_tokens.json"
    # Priority 2: Gemini CLI's credential file (compatibility fallback)
    gemini_cli_path = Path.home() / ".gemini" / "oauth_creds.json"

    # Try CLI Pulse tokens first, then fall back to Gemini CLI tokens
    access_token = None
    if clipulse_path.exists():
        access_token = _try_read_gemini_token(clipulse_path)
    if not access_token and gemini_cli_path.exists():
        access_token = _try_read_gemini_token(gemini_cli_path)
    if not access_token:
        return None
    try:
        project_id = _load_gemini_project_id(access_token)
        if project_id is None:
            project_id = ""

        req = urllib.request.Request(
            "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
            data=_json.dumps({"project": project_id}).encode(),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())
            return _parse_gemini_quota_response(data)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        logger.debug("Gemini usage fetch failed: %s", e)
        return None
    except (KeyError, ValueError, _json.JSONDecodeError) as e:
        logger.debug("Gemini usage parse error: %s", e)
        return None


def _load_gemini_project_id(access_token: str) -> str | None:
    """Load the active Gemini Code Assist project via loadCodeAssist.

    This matches CodexBar and the local Swift collector. Without the project ID,
    retrieveUserQuota often returns generic 100% buckets that don't match the
    actual Gemini Pro usage shown in the official UI.
    """
    try:
        req = urllib.request.Request(
            "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
            data=_json.dumps({"metadata": {"ideType": "GEMINI_CLI", "pluginType": "GEMINI"}}).encode(),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())

        project = data.get("cloudaicompanionProject")
        if isinstance(project, str) and project.strip():
            return project.strip()
        if isinstance(project, dict):
            pid = project.get("projectId") or project.get("id")
            if isinstance(pid, str) and pid.strip():
                return pid.strip()
    except Exception as e:
        logger.debug(f"Gemini loadCodeAssist failed: {e}")
    return None


def _parse_gemini_quota_response(data: dict) -> dict | None:
    """Parse Google quota API response for Gemini models.

    Real format: {"buckets": [{"resetTime":"...","tokenType":"REQUESTS","modelId":"gemini-2.5-pro","remainingFraction":1.0}]}
    """
    family_best: dict[str, dict] = {}
    buckets = data.get("buckets", data.get("quotas", data.get("userQuotas", [])))
    if isinstance(buckets, list):
        for q in buckets:
            if q.get("tokenType") != "REQUESTS":
                continue
            model = q.get("modelId", "Default")
            if "pro" in model.lower():
                name = "Pro"
            elif "lite" in model.lower():
                name = "Flash Lite"
            elif "flash" in model.lower():
                name = "Flash"
            else:
                name = model
            fraction = q.get("remainingFraction", 1.0)
            remaining_pct = int(fraction * 100)
            reset = q.get("resetTime")
            current = family_best.get(name)
            candidate = {"name": name, "quota": 100, "remaining": remaining_pct, "reset_time": reset}
            if current is None or candidate["remaining"] < current["remaining"]:
                family_best[name] = candidate

    preferred_order = ["Pro", "Flash", "Flash Lite"]
    tiers: list[dict] = []
    for family in preferred_order:
        if family in family_best:
            tiers.append(family_best[family])
    for family in sorted(family_best):
        if family not in preferred_order:
            tiers.append(family_best[family])

    if not tiers:
        return None

    primary = next((family_best[name] for name in preferred_order if name in family_best), tiers[0])
    return {
        "quota": primary["quota"],
        "remaining": primary["remaining"],
        "plan_type": "Paid",
        "reset_time": primary.get("reset_time"),
        "tiers": tiers,
    }


def _extract_percent(text: str) -> int | None:
    """Extract percentage number from text like '15% used'."""
    m = re.search(r"(\d+)%", text)
    return int(m.group(1)) if m else None


def _extract_reset_time(text: str) -> str | None:
    """Extract reset time from text and convert to ISO timestamp."""
    m = re.search(r"resets?\s+in\s+(\d+)h?\s*(\d+)?m?", text, re.IGNORECASE)
    if m:
        hours = int(m.group(1))
        mins = int(m.group(2) or 0)
        reset = datetime.now(timezone.utc) + timedelta(hours=hours, minutes=mins)
        return reset.isoformat()
    return None


def _process_rows() -> list[dict[str, str]]:
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,pcpu=,pmem=,etime=,command="],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            logger.warning("ps command failed with code %d", result.returncode)
            return []
    except subprocess.TimeoutExpired:
        logger.warning("ps command timed out")
        return []
    except FileNotFoundError:
        logger.warning("ps command not found")
        return []

    rows: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(None, 4)
        if len(parts) < 5:
            continue
        pid, pcpu, pmem, etime, command = parts
        rows.append({"pid": pid, "pcpu": pcpu, "pmem": pmem, "etime": etime, "command": command})
    return rows


def _elapsed_to_seconds(raw: str) -> int:
    chunks = raw.split("-")
    time_part = chunks[-1]
    days = int(chunks[0]) if len(chunks) == 2 else 0
    parts = [int(part) for part in time_part.split(":")]

    if len(parts) == 3:
        hours, minutes, seconds = parts
    elif len(parts) == 2:
        hours, minutes, seconds = 0, parts[0], parts[1]
    else:
        hours, minutes, seconds = 0, 0, parts[0]

    return days * 86_400 + hours * 3_600 + minutes * 60 + seconds


def _detect_provider(command: str) -> tuple[str, str] | None:
    """Return (provider_name, confidence) or None."""
    lowered = command.lower()
    for provider, pattern, confidence in PROCESS_PATTERNS:
        if re.search(pattern, lowered):
            return provider, confidence
    return None


def _should_ignore_command(command: str) -> bool:
    lowered = command.lower()
    return any(re.search(pattern, lowered) for pattern in IGNORED_COMMAND_PATTERNS)


def _pretty_name(command: str) -> str:
    compact = re.sub(r"\s+", " ", command).strip()
    if len(compact) <= 48:
        return compact
    return compact[:45] + "..."


# Project marker files, checked in order of specificity
_PROJECT_MARKERS = [
    "package.json",
    "Cargo.toml",
    "go.mod",
    "pyproject.toml",
    "setup.py",
    "Makefile",
    "CMakeLists.txt",
    ".git",
]


def _guess_project_root(command: str) -> Optional[Path]:
    """Best-effort absolute project root inferred from a command's file path arguments.

    Returns the directory containing a project marker (.git, package.json, etc.)
    if one is found, else None. Used to compute project_hash for yield score
    attribution; callers that just need a display name should use _guess_project.
    """
    path_matches = re.findall(r"(/(?:Users|home|opt|var|tmp|srv)[^\s\"']+)", command)

    for match in path_matches:
        p = Path(match)
        for ancestor in [p] + list(p.parents):
            if str(ancestor) in {"/", "/Users", "/home", "/opt", "/var", "/tmp", "/srv"}:
                break
            for marker in _PROJECT_MARKERS:
                if (ancestor / marker).exists():
                    return ancestor

    return None


def _guess_project(command: str) -> str:
    """Guess the project display name from the command string.

    Strategy:
    1. Try _guess_project_root (path with marker) first
    2. Fall back to the deepest non-system directory component of the command
    3. Final fallback: current working directory name
    """
    root = _guess_project_root(command)
    if root is not None:
        return root.name

    path_matches = re.findall(r"(/(?:Users|home|opt|var|tmp|srv)[^\s\"']+)", command)
    for match in path_matches:
        p = Path(match)
        parts = [part for part in p.parts if part not in {"/", "Users", "home", "opt", "var", "tmp", "srv"}]
        if len(parts) >= 2:
            return parts[1]
        if parts:
            return parts[-1]

    return Path(os.getcwd()).name or "local-workspace"


def _project_id(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized or "local-workspace"


def _collect_cpu_usage() -> int:
    try:
        cpu_count = max(os.cpu_count() or 1, 1)
        load = os.getloadavg()[0]
        return max(0, min(100, int(load / cpu_count * 100)))
    except (OSError, AttributeError):
        return 0


def _collect_memory_usage() -> int:
    try:
        result = subprocess.run(
            ["vm_stat"], capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return 0

        page_size = 4096
        page_size_match = re.search(r"page size of (\d+) bytes", result.stdout)
        if page_size_match:
            page_size = int(page_size_match.group(1))

        values: dict[str, int] = {}
        for line in result.stdout.splitlines():
            if ":" not in line:
                continue
            key, raw_value = line.split(":", 1)
            digits = re.sub(r"[^0-9]", "", raw_value)
            if digits:
                values[key.strip()] = int(digits)

        free = values.get("Pages free", 0) + values.get("Pages speculative", 0)
        active = values.get("Pages active", 0) + values.get("Pages wired down", 0) + values.get("Pages occupied by compressor", 0)
        total = free + active + values.get("Pages inactive", 0)
        if total <= 0:
            return 0
        used_ratio = active / total
        return max(0, min(100, int(used_ratio * 100)))
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return 0
