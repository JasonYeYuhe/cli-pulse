from __future__ import annotations

import logging
import os
import re
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

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
    ("Kimi K2", r"\bkimi\b|\bkimi[_-]?k2\b", "high"),
    ("Amp", r"\bamp\b", "low"),
    ("Synthetic", r"\bsynthetic\b", "medium"),
    ("Warp", r"\bwarp\b", "medium"),
    ("Kilo", r"\bkilo\b|\bkilo[_-]?code\b", "high"),
    ("Ollama", r"\bollama\b", "high"),
    ("OpenRouter", r"\bopenrouter\b", "high"),
    ("Alibaba", r"\balibaba\b|\bqwen\b|\btongyi\b", "high"),
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


def estimate_provider_remaining(sessions: list[CollectedSession]) -> dict[str, int]:
    defaults = {
        "Codex": 500_000,
        "Gemini": 300_000,
        "Claude": 250_000,
        "Cursor": 500_000,
        "OpenCode": 300_000,
        "Droid": 200_000,
        "Antigravity": 200_000,
        "Copilot": 500_000,
        "z.ai": 200_000,
        "MiniMax": 300_000,
        "Augment": 300_000,
        "JetBrains AI": 300_000,
        "Kimi K2": 500_000,
        "Amp": 300_000,
        "Synthetic": 200_000,
        "Warp": 300_000,
        "Kilo": 200_000,
        "OpenRouter": 200_000,
        "Ollama": 999_999,
        "Alibaba": 400_000,
    }
    usage: dict[str, int] = {}
    for session in sessions:
        usage[session.provider] = usage.get(session.provider, 0) + session.total_usage

    remaining: dict[str, int] = {}
    for provider in defaults:
        remaining[provider] = max(0, defaults[provider] - usage.get(provider, 0) * 5)
    return remaining


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


def _guess_project(command: str) -> str:
    """Guess the project name from the command string.

    Strategy:
    1. Extract file paths from the command
    2. Walk up from each path looking for project markers (.git, package.json, etc.)
    3. Use the directory name containing the marker as the project name
    4. Fall back to the deepest non-system directory component
    5. Final fallback: current working directory name
    """
    path_matches = re.findall(r"(/(?:Users|home|opt|var|tmp|srv)[^\s\"']+)", command)

    for match in path_matches:
        p = Path(match)
        # Walk up looking for project root markers
        for ancestor in [p] + list(p.parents):
            if str(ancestor) in {"/", "/Users", "/home", "/opt", "/var", "/tmp", "/srv"}:
                break
            for marker in _PROJECT_MARKERS:
                if (ancestor / marker).exists():
                    return ancestor.name
        # Fallback: use deepest meaningful directory
        parts = [part for part in p.parts if part not in {"/", "Users", "home", "opt", "var", "tmp", "srv"}]
        # Skip username, take the next meaningful directory
        if len(parts) >= 2:
            return parts[1]  # parts[0] is usually the username
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
