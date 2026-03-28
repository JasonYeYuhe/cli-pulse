from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional


PROCESS_PATTERNS: list[tuple[str, str]] = [
    ("Codex", r"\bcodex\b|\bopenai\b"),
    ("Gemini", r"\bgemini\b|\bgoogle-generativeai\b"),
    ("Claude", r"\bclaude\b"),
    ("OpenRouter", r"\bopenrouter\b"),
    ("Ollama", r"\bollama\b"),
]

IGNORED_COMMAND_PATTERNS: list[str] = [
    r"crashpad",
    r"--type=renderer",
    r"--type=gpu-process",
    r"--utility-sub-type",
    r"codex helper",
    r"electron framework",
]


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


def collect_device_snapshot() -> DeviceSnapshot:
    cpu_usage = _collect_cpu_usage()
    memory_usage = _collect_memory_usage()
    return DeviceSnapshot(cpu_usage=cpu_usage, memory_usage=memory_usage)


def collect_sessions() -> list[CollectedSession]:
    sessions: list[CollectedSession] = []
    for row in _process_rows():
        if _should_ignore_command(row["command"]):
            continue

        provider = _detect_provider(row["command"])
        if provider is None:
            continue

        elapsed_seconds = max(1, _elapsed_to_seconds(row["etime"]))
        started_at = datetime.now(timezone.utc) - timedelta(seconds=elapsed_seconds)
        command = row["command"]
        cpu = float(row["pcpu"])
        project = _guess_project(command)

        sessions.append(
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
            )
        )

    sessions.sort(key=lambda item: (item.cpu_usage, item.last_active_at), reverse=True)
    return sessions[:12]


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
        "OpenRouter": 200_000,
        "Ollama": 999_999,
    }
    usage: dict[str, int] = {}
    for session in sessions:
        usage[session.provider] = usage.get(session.provider, 0) + session.total_usage

    remaining: dict[str, int] = {}
    for provider in defaults:
        remaining[provider] = max(0, defaults[provider] - usage.get(provider, 0) * 5)
    return remaining


def _process_rows() -> list[dict[str, str]]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,pcpu=,pmem=,etime=,command="],
        capture_output=True,
        text=True,
        check=True,
    )

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


def _detect_provider(command: str) -> str | None:
    lowered = command.lower()
    for provider, pattern in PROCESS_PATTERNS:
        if re.search(pattern, lowered):
            return provider
    return None


def _should_ignore_command(command: str) -> bool:
    lowered = command.lower()
    return any(re.search(pattern, lowered) for pattern in IGNORED_COMMAND_PATTERNS)


def _pretty_name(command: str) -> str:
    compact = re.sub(r"\s+", " ", command).strip()
    if len(compact) <= 48:
        return compact
    return compact[:45] + "..."


def _guess_project(command: str) -> str:
    path_matches = re.findall(r"/Users/[^ ]+|/home/[^ ]+|/opt/[^ ]+", command)
    for match in path_matches:
        parts = [part for part in Path(match).parts if part not in {"/", "Users", "home", "opt"}]
        if parts:
            return parts[-1]
    return Path(os.getcwd()).name or "local-workspace"


def _project_id(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized or "local-workspace"


def _collect_cpu_usage() -> int:
    cpu_count = max(os.cpu_count() or 1, 1)
    load = os.getloadavg()[0]
    return max(0, min(100, int(load / cpu_count * 100)))


def _collect_memory_usage() -> int:
    try:
        result = subprocess.run(["vm_stat"], capture_output=True, text=True, check=True)
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
    except Exception:
        return 0
