#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from system_collector import collect_alerts, collect_device_snapshot, collect_sessions, estimate_provider_remaining


CONFIG_PATH = Path.home() / ".cli-pulse-helper.json"
SUPPORTED_PROVIDERS = {"Codex", "Gemini", "Claude", "OpenRouter", "Ollama"}


@dataclass
class HelperConfig:
    server: str
    access_token: str
    device_id: str
    device_name: str
    helper_version: str


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_config() -> HelperConfig:
    if not CONFIG_PATH.exists():
        raise SystemExit("helper is not paired yet")
    return HelperConfig(**json.loads(CONFIG_PATH.read_text()))


def save_config(config: HelperConfig) -> None:
    CONFIG_PATH.write_text(json.dumps(asdict(config), indent=2))


def request_json(method: str, url: str, payload: dict[str, Any] | None = None, token: str | None = None) -> dict[str, Any]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(url=url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8")
        raise SystemExit(f"{error.code} {detail}") from error


def pair(args: argparse.Namespace) -> None:
    device_name = args.device_name or "CLI Pulse Helper"
    payload = {
        "pairing_code": args.pairing_code,
        "device_name": device_name,
        "device_type": args.device_type,
        "system": args.system,
        "helper_version": args.helper_version,
    }
    response = request_json("POST", f"{args.server}/v1/helper/register", payload)
    config = HelperConfig(
        server=args.server.rstrip("/"),
        access_token=response["access_token"],
        device_id=response["device_id"],
        device_name=device_name,
        helper_version=args.helper_version,
    )
    save_config(config)
    print(f"paired {config.device_name} as {config.device_id}")


def heartbeat(_: argparse.Namespace) -> None:
    config = load_config()
    snapshot = collect_device_snapshot()
    sessions = collect_sessions()
    payload = {
        "device_id": config.device_id,
        "cpu_usage": snapshot.cpu_usage,
        "memory_usage": snapshot.memory_usage,
        "active_session_count": len(sessions),
    }
    request_json("POST", f"{config.server}/v1/helper/heartbeat", payload, config.access_token)
    print("heartbeat sent")


def sync(_: argparse.Namespace) -> None:
    config = load_config()
    snapshot = collect_device_snapshot()
    collected_sessions = collect_sessions()
    sessions = [
        {
            "id": item.session_id,
            "name": item.name,
            "provider": item.provider,
            "project": item.project,
            "status": item.status,
            "total_usage": item.total_usage,
            "requests": item.requests,
            "error_count": item.error_count,
            "started_at": item.started_at,
            "last_active_at": item.last_active_at,
        }
        for item in collected_sessions
        if item.provider in SUPPORTED_PROVIDERS
    ]
    alerts = [
        {
            "id": item.alert_id,
            "type": item.type,
            "severity": item.severity,
            "title": item.title,
            "message": item.message,
            "created_at": item.created_at,
        }
        for item in collect_alerts(collected_sessions, snapshot)
    ]

    payload = {
        "device_id": config.device_id,
        "sessions": sessions,
        "alerts": alerts,
        "provider_remaining": estimate_provider_remaining(collected_sessions),
    }
    request_json("POST", f"{config.server}/v1/helper/sync", payload, config.access_token)
    print(f"synced {len(sessions)} sessions")


def run_demo(args: argparse.Namespace) -> None:
    for _ in range(args.cycles):
        heartbeat(args)
        sync(args)
        time.sleep(args.interval)


def inspect(_: argparse.Namespace) -> None:
    snapshot = collect_device_snapshot()
    sessions = collect_sessions()
    alerts = collect_alerts(sessions, snapshot)
    print(
        json.dumps(
            {
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "device": {"cpu_usage": snapshot.cpu_usage, "memory_usage": snapshot.memory_usage},
                "sessions": [item.__dict__ for item in sessions],
                "alerts": [item.__dict__ for item in alerts],
            },
            indent=2,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="CLI Pulse device helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    pair_parser = subparsers.add_parser("pair", help="pair this device with a CLI Pulse account")
    pair_parser.add_argument("--server", required=True)
    pair_parser.add_argument("--pairing-code", required=True)
    pair_parser.add_argument("--device-name")
    pair_parser.add_argument("--device-type", default="Mac")
    pair_parser.add_argument("--system", default="macOS")
    pair_parser.add_argument("--helper-version", default="0.1.0")
    pair_parser.set_defaults(func=pair)

    heartbeat_parser = subparsers.add_parser("heartbeat", help="send one heartbeat")
    heartbeat_parser.set_defaults(func=heartbeat)

    sync_parser = subparsers.add_parser("sync", help="sync sessions and alerts")
    sync_parser.set_defaults(func=sync)

    demo_parser = subparsers.add_parser("run-demo", help="emit heartbeats and syncs in a loop")
    demo_parser.add_argument("--cycles", type=int, default=3)
    demo_parser.add_argument("--interval", type=int, default=2)
    demo_parser.set_defaults(func=run_demo)

    inspect_parser = subparsers.add_parser("inspect", help="print the locally collected snapshot")
    inspect_parser.set_defaults(func=inspect)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
