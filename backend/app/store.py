from __future__ import annotations

import json
import sqlite3
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Optional
from uuid import uuid4

from .models import (
    ActivityItemDTO,
    AlertActionResponseDTO,
    AlertRecordDTO,
    AlertSeverity,
    AlertType,
    DashboardSummaryDTO,
    DeviceRecordDTO,
    DeviceStatus,
    HelperHeartbeatRequestDTO,
    HelperRegisterRequestDTO,
    HelperRegisterResponseDTO,
    HelperSyncRequestDTO,
    PairingInfoDTO,
    ProviderKind,
    ProviderUsageDTO,
    SessionRecordDTO,
    SessionStatus,
    SettingsSnapshotDTO,
    SettingsUpdateDTO,
    SuccessDTO,
    UsagePointDTO,
    UserDTO,
)


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class SessionState:
    token: str
    user: UserDTO
    paired: bool


class SQLiteStore:
    def __init__(self, database_path: str) -> None:
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.database_path, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        self._create_tables()

    def authenticate(self, token: str) -> Optional[SessionState]:
        row = self.connection.execute(
            """
            SELECT t.token, u.id, u.name, u.email, u.paired
            FROM auth_tokens t
            JOIN users u ON u.id = t.user_id
            WHERE t.token = ?
            """,
            (token,),
        ).fetchone()
        if row is None:
            return None
        return SessionState(
            token=row["token"],
            user=UserDTO(id=row["id"], name=row["name"], email=row["email"]),
            paired=bool(row["paired"]),
        )

    def login(self, email: str, name: Optional[str]) -> SessionState:
        with self.lock:
            user_row = self.connection.execute(
                "SELECT id, name, email, paired FROM users WHERE email = ?",
                (email,),
            ).fetchone()

            if user_row is None:
                user_id = str(uuid4())
                user_name = name or email.split("@")[0].capitalize()
                self.connection.execute(
                    """
                    INSERT INTO users (
                        id, email, name, paired, settings_json, providers_json,
                        sessions_json, devices_json, alerts_json, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        email,
                        user_name,
                        0,
                        self._encode_model(
                            SettingsSnapshotDTO(
                                notifications_enabled=True,
                                usage_spike_threshold=70_000,
                                data_retention_days=30,
                                login_method="Email + Password",
                            )
                        ),
                        "[]",
                        "[]",
                        "[]",
                        "[]",
                        now_utc().isoformat(),
                    ),
                )
                self._seed_user_data(user_id)
                paired = False
            else:
                user_id = user_row["id"]
                user_name = user_row["name"]
                paired = bool(user_row["paired"])

            token = f"pulse_{uuid4().hex}"
            self.connection.execute(
                "INSERT INTO auth_tokens (token, user_id, created_at) VALUES (?, ?, ?)",
                (token, user_id, now_utc().isoformat()),
            )
            self.connection.commit()

        return SessionState(
            token=token,
            user=UserDTO(id=user_id, name=user_name, email=email),
            paired=paired,
        )

    def pairing_info(self, token: str) -> PairingInfoDTO:
        state = self._require_session(token)
        code = f"PULSE-{uuid4().hex[:6].upper()}"
        with self.lock:
            self.connection.execute(
                "INSERT INTO pairing_codes (code, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (code, state.user.id, now_utc().isoformat(), (now_utc() + timedelta(minutes=10)).isoformat()),
            )
            self.connection.commit()
        return PairingInfoDTO(
            code=code,
            install_command=f"python3 helper/cli_pulse_helper.py pair --server http://127.0.0.1:8000 --pairing-code {code}",
        )

    def complete_pairing(self, token: str) -> SuccessDTO:
        state = self._require_session(token)
        with self.lock:
            self.connection.execute("UPDATE users SET paired = 1 WHERE id = ?", (state.user.id,))
            self.connection.commit()
        return SuccessDTO()

    def dashboard(self, token: str) -> DashboardSummaryDTO:
        state = self._require_session(token)
        self._apply_device_health_rules(state.user.id)
        providers = self.providers(token)
        sessions = self.sessions(token)
        devices = self.devices(token)
        alerts = self.alerts(token)

        hourly: dict[datetime, int] = {}
        for provider in providers:
            for point in provider.trend:
                bucket = point.timestamp.replace(minute=0, second=0, microsecond=0)
                hourly[bucket] = hourly.get(bucket, 0) + point.value

        risk_signals: list[str] = []
        quota_risk = next((item for item in providers if item.quota and item.remaining / item.quota < 0.2), None)
        if quota_risk:
            risk_signals.append(f"{quota_risk.provider.value} quota 低于 20%，建议检查剩余额度。")
        offline_device = next((item for item in devices if item.status == DeviceStatus.offline), None)
        if offline_device:
            risk_signals.append(f"{offline_device.name} helper 离线，需要确认网络或服务进程。")
        critical_alert = next((item for item in alerts if not item.is_resolved and item.severity == AlertSeverity.critical), None)
        if critical_alert:
            risk_signals.append(critical_alert.title)
        if not risk_signals:
            risk_signals.append("当前没有高风险异常。")

        recent_activity = sorted(
            [
                ActivityItemDTO(
                    id=item.id,
                    title=f"{item.provider.value} · {item.name}",
                    subtitle=f"{item.project} on {item.device_name}",
                    timestamp=item.last_active_at,
                )
                for item in sessions
            ],
            key=lambda item: item.timestamp,
            reverse=True,
        )[:4]

        return DashboardSummaryDTO(
            total_usage=sum(item.total_usage for item in sessions),
            total_requests=sum(item.requests for item in sessions),
            active_sessions=sum(1 for item in sessions if item.status in {SessionStatus.running, SessionStatus.syncing}),
            online_devices=sum(1 for item in devices if item.status == DeviceStatus.online),
            unresolved_alerts=sum(1 for item in alerts if not item.is_resolved),
            provider_breakdown=providers,
            trend=[UsagePointDTO(timestamp=timestamp, value=value) for timestamp, value in sorted(hourly.items())],
            recent_activity=recent_activity,
            risk_signals=risk_signals,
        )

    def providers(self, token: str) -> list[ProviderUsageDTO]:
        state = self._require_session(token)
        return self._load_models(state.user.id, "providers_json", ProviderUsageDTO)

    def provider_detail(self, token: str, provider_name: str) -> Optional[ProviderUsageDTO]:
        provider_name = provider_name.lower()
        for provider in self.providers(token):
            if provider.provider.value.lower() == provider_name:
                return provider
        return None

    def sessions(self, token: str) -> list[SessionRecordDTO]:
        state = self._require_session(token)
        items = self._load_models(state.user.id, "sessions_json", SessionRecordDTO)
        return sorted(items, key=lambda item: item.last_active_at, reverse=True)

    def devices(self, token: str) -> list[DeviceRecordDTO]:
        state = self._require_session(token)
        self._apply_device_health_rules(state.user.id)
        items = self._load_models(state.user.id, "devices_json", DeviceRecordDTO)
        return sorted(items, key=lambda item: item.last_sync_at, reverse=True)

    def alerts(self, token: str) -> list[AlertRecordDTO]:
        state = self._require_session(token)
        items = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        return sorted(items, key=lambda item: item.created_at, reverse=True)

    def settings(self, token: str) -> SettingsSnapshotDTO:
        state = self._require_session(token)
        row = self.connection.execute("SELECT settings_json FROM users WHERE id = ?", (state.user.id,)).fetchone()
        return SettingsSnapshotDTO.model_validate_json(row["settings_json"])

    def update_settings(self, token: str, payload: SettingsUpdateDTO) -> SettingsSnapshotDTO:
        state = self._require_session(token)
        current = self.settings(token)
        current.notifications_enabled = payload.notifications_enabled
        current.usage_spike_threshold = payload.usage_spike_threshold
        current.data_retention_days = payload.data_retention_days
        with self.lock:
            self.connection.execute(
                "UPDATE users SET settings_json = ? WHERE id = ?",
                (self._encode_model(current), state.user.id),
            )
            self.connection.commit()
        return current

    def mark_alert(self, token: str, alert_id: str, *, resolve: bool) -> AlertActionResponseDTO:
        state = self._require_session(token)
        alerts = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        for alert in alerts:
            if alert.id == alert_id:
                alert.is_read = True
                if resolve:
                    alert.is_resolved = True
        self._save_models(state.user.id, "alerts_json", alerts)
        return AlertActionResponseDTO(alerts=alerts)

    def register_helper(self, payload: HelperRegisterRequestDTO) -> Optional[HelperRegisterResponseDTO]:
        row = self.connection.execute(
            "SELECT user_id, expires_at FROM pairing_codes WHERE code = ?",
            (payload.pairing_code,),
        ).fetchone()
        if row is None:
            return None
        if datetime.fromisoformat(row["expires_at"]) < now_utc():
            return None

        user_id = row["user_id"]
        device_id = f"device_{payload.device_name.lower().replace(' ', '-')}_{payload.helper_version.replace('.', '-')}"

        with self.lock:
            self.connection.execute("UPDATE users SET paired = 1 WHERE id = ?", (user_id,))
            self.connection.execute(
                """
                INSERT INTO device_tokens (device_id, user_id, created_at, last_seen)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(device_id) DO UPDATE SET user_id = excluded.user_id, last_seen = excluded.last_seen
                """,
                (device_id, user_id, now_utc().isoformat(), now_utc().isoformat()),
            )
            self.connection.commit()

        state = self._session_for_user(user_id)
        if state is None:
            token = f"pulse_{uuid4().hex}"
            with self.lock:
                self.connection.execute(
                    "INSERT INTO auth_tokens (token, user_id, created_at) VALUES (?, ?, ?)",
                    (token, user_id, now_utc().isoformat()),
                )
                self.connection.commit()
            state = self.authenticate(token)

        assert state is not None
        devices = self._load_models(user_id, "devices_json", DeviceRecordDTO)
        existing = next((item for item in devices if item.id == device_id), None)
        if existing is None:
            devices.insert(
                0,
                DeviceRecordDTO(
                    id=device_id,
                    name=payload.device_name,
                    type=payload.device_type,
                    system=payload.system,
                    status=DeviceStatus.online,
                    last_sync_at=now_utc(),
                    helper_version=payload.helper_version,
                    current_session_count=0,
                    cpu_usage=0,
                    memory_usage=0,
                    heartbeat_timeline=[],
                    recent_sync_errors=[],
                    provider_status={},
                    recent_projects=[],
                ),
            )
            self._save_models(user_id, "devices_json", devices)

        return HelperRegisterResponseDTO(device_id=device_id, access_token=state.token)

    def helper_heartbeat(self, token: str, payload: HelperHeartbeatRequestDTO) -> SuccessDTO:
        state = self._require_session(token)
        if not self._device_belongs_to_user(payload.device_id, state.user.id):
            raise PermissionError("Device does not belong to token")

        devices = self._load_models(state.user.id, "devices_json", DeviceRecordDTO)
        for device in devices:
            if device.id == payload.device_id:
                device.status = DeviceStatus.online
                device.last_sync_at = now_utc()
                device.cpu_usage = payload.cpu_usage
                device.memory_usage = payload.memory_usage
                device.current_session_count = payload.active_session_count
                device.heartbeat_timeline.append(
                    UsagePointDTO(
                        timestamp=now_utc(),
                        value=max(0, min(100, 100 - max(payload.cpu_usage, payload.memory_usage) // 2)),
                    )
                )
                device.heartbeat_timeline = device.heartbeat_timeline[-24:]
                break
        self._save_models(state.user.id, "devices_json", devices)

        with self.lock:
            self.connection.execute(
                "UPDATE device_tokens SET last_seen = ? WHERE device_id = ?",
                (now_utc().isoformat(), payload.device_id),
            )
            self.connection.commit()

        return SuccessDTO()

    def helper_sync(self, token: str, payload: HelperSyncRequestDTO) -> SuccessDTO:
        state = self._require_session(token)
        if not self._device_belongs_to_user(payload.device_id, state.user.id):
            raise PermissionError("Device does not belong to token")

        devices = self._load_models(state.user.id, "devices_json", DeviceRecordDTO)
        device_name = next((item.name for item in devices if item.id == payload.device_id), payload.device_id)

        synced_sessions: list[SessionRecordDTO] = []
        recent_projects: set[str] = set()
        for item in payload.sessions:
            recent_projects.add(item.project)
            synced_sessions.append(
                SessionRecordDTO(
                    id=item.id,
                    name=item.name,
                    provider=item.provider,
                    project=item.project,
                    device_name=device_name,
                    started_at=item.started_at,
                    last_active_at=item.last_active_at,
                    status=item.status,
                    total_usage=item.total_usage,
                    requests=item.requests,
                    error_count=item.error_count,
                    usage_timeline=[],
                    activity_timeline=[],
                    error_summary=[],
                )
            )

        existing_sessions = [item for item in self._load_models(state.user.id, "sessions_json", SessionRecordDTO) if item.device_name != device_name]
        self._save_models(state.user.id, "sessions_json", synced_sessions + existing_sessions)

        providers = self._load_models(state.user.id, "providers_json", ProviderUsageDTO)
        provider_totals: dict[ProviderKind, int] = {kind: 0 for kind in ProviderKind}
        for item in payload.sessions:
            provider_totals[item.provider] = provider_totals.get(item.provider, 0) + item.total_usage

        for provider in providers:
            if provider.provider in payload.provider_remaining:
                provider.remaining = payload.provider_remaining[provider.provider]
            provider.today_usage = provider_totals.get(provider.provider, provider.today_usage)
            provider.recent_session_names = [item.name for item in synced_sessions if item.provider == provider.provider][:5]
        self._save_models(state.user.id, "providers_json", providers)

        alerts = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        alert_ids = {item.id for item in alerts}
        for item in payload.alerts:
            if item.id not in alert_ids:
                alerts.insert(
                    0,
                    AlertRecordDTO(
                        id=item.id,
                        type=item.type,
                        severity=item.severity,
                        title=item.title,
                        message=item.message,
                        created_at=item.created_at,
                        is_read=False,
                        is_resolved=False,
                    )
                )
        self._save_models(state.user.id, "alerts_json", alerts)

        for device in devices:
            if device.id == payload.device_id:
                device.provider_status = {provider.provider: provider.status_text for provider in providers}
                device.recent_projects = sorted(recent_projects)[:6]
                device.current_session_count = len(synced_sessions)
                device.last_sync_at = now_utc()
                break
        self._save_models(state.user.id, "devices_json", devices)

        return SuccessDTO()

    def delete_account(self, token: str) -> SuccessDTO:
        state = self._require_session(token)
        with self.lock:
            self.connection.execute("DELETE FROM auth_tokens WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM pairing_codes WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM device_tokens WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM users WHERE id = ?", (state.user.id,))
            self.connection.commit()
        return SuccessDTO()

    def _create_tables(self) -> None:
        with self.lock:
            self.connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    email TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    paired INTEGER NOT NULL DEFAULT 0,
                    settings_json TEXT NOT NULL,
                    providers_json TEXT NOT NULL,
                    sessions_json TEXT NOT NULL,
                    devices_json TEXT NOT NULL,
                    alerts_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS auth_tokens (
                    token TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS pairing_codes (
                    code TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS device_tokens (
                    device_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_at TEXT NOT NULL,
                    last_seen TEXT NOT NULL
                );
                """
            )
            self.connection.commit()

    def _seed_user_data(self, user_id: str) -> None:
        now = now_utc()
        codex_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([4800, 8300, 12200, 15600, 11400, 9200, 13800, 10500])
        ]
        gemini_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([2400, 4900, 6700, 7300, 5600, 4800, 6200, 5500])
        ]

        providers = [
            ProviderUsageDTO(
                provider=ProviderKind.codex,
                today_usage=85_900,
                week_usage=462_000,
                quota=500_000,
                remaining=38_000,
                status_text="Busy",
                trend=codex_trend,
                recent_session_names=["Refactor dashboard filters", "Fix session sync retry", "Investigate helper heartbeat"],
                recent_errors=["2 sync retries on Tokyo-Mac", "1 session timeout on lab-server"],
            ),
            ProviderUsageDTO(
                provider=ProviderKind.gemini,
                today_usage=43_400,
                week_usage=214_000,
                quota=300_000,
                remaining=86_000,
                status_text="Healthy",
                trend=gemini_trend,
                recent_session_names=["Draft device pairing UX", "Summarize CI failures"],
                recent_errors=["No new provider errors"],
            ),
        ]

        sessions = [
            SessionRecordDTO(
                id=str(uuid4()),
                name="Dashboard metrics pass",
                provider=ProviderKind.codex,
                project="cli-pulse-ios",
                device_name="Jason's MacBook Pro",
                started_at=now - timedelta(hours=5),
                last_active_at=now - timedelta(minutes=6),
                status=SessionStatus.running,
                total_usage=41_200,
                requests=118,
                error_count=1,
                usage_timeline=codex_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Opened DashboardView", subtitle="Provider chart rendered", timestamp=now - timedelta(hours=4)),
                    ActivityItemDTO(id=str(uuid4()), title="Pulled remote mocks", subtitle="Refreshed summary cards", timestamp=now - timedelta(hours=2)),
                    ActivityItemDTO(id=str(uuid4()), title="Agent still running", subtitle="Background instrumentation", timestamp=now - timedelta(minutes=6)),
                ],
                error_summary=["One transient timeout during summary sync."],
            ),
            SessionRecordDTO(
                id=str(uuid4()),
                name="Helper heartbeat monitor",
                provider=ProviderKind.gemini,
                project="cli-pulse-helper",
                device_name="lab-server-01",
                started_at=now - timedelta(hours=9),
                last_active_at=now - timedelta(minutes=18),
                status=SessionStatus.syncing,
                total_usage=26_900,
                requests=84,
                error_count=0,
                usage_timeline=gemini_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Restarted helper daemon", subtitle="Version 0.1.3", timestamp=now - timedelta(hours=7)),
                    ActivityItemDTO(id=str(uuid4()), title="Heartbeat recovered", subtitle="Latency back to normal", timestamp=now - timedelta(hours=2)),
                ],
                error_summary=[],
            ),
            SessionRecordDTO(
                id=str(uuid4()),
                name="Session error triage",
                provider=ProviderKind.codex,
                project="backend-api",
                device_name="build-box",
                started_at=now - timedelta(hours=12),
                last_active_at=now - timedelta(hours=1),
                status=SessionStatus.failed,
                total_usage=61_200,
                requests=141,
                error_count=3,
                usage_timeline=codex_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Auth expired", subtitle="Provider token rejected", timestamp=now - timedelta(hours=1))
                ],
                error_summary=["Token expired for backend integration.", "Retry queue exceeded limit."],
            ),
        ]

        devices = [
            DeviceRecordDTO(
                id=str(uuid4()),
                name="Jason's MacBook Pro",
                type="Mac",
                system="macOS 26",
                status=DeviceStatus.online,
                last_sync_at=now - timedelta(minutes=2),
                helper_version="0.1.3",
                current_session_count=2,
                cpu_usage=36,
                memory_usage=58,
                heartbeat_timeline=[UsagePointDTO(timestamp=now - timedelta(minutes=50 - index * 10), value=value) for index, value in enumerate([93, 95, 91, 94, 96, 98])],
                recent_sync_errors=[],
                provider_status={ProviderKind.codex: "Connected", ProviderKind.gemini: "Connected"},
                recent_projects=["cli-pulse-ios", "backend-api"],
            ),
            DeviceRecordDTO(
                id=str(uuid4()),
                name="lab-server-01",
                type="Linux Server",
                system="Ubuntu 24.04",
                status=DeviceStatus.degraded,
                last_sync_at=now - timedelta(minutes=8),
                helper_version="0.1.3",
                current_session_count=1,
                cpu_usage=72,
                memory_usage=68,
                heartbeat_timeline=[UsagePointDTO(timestamp=now - timedelta(minutes=50 - index * 10), value=value) for index, value in enumerate([88, 83, 79, 77, 82, 80])],
                recent_sync_errors=["High latency on recent provider sync."],
                provider_status={ProviderKind.codex: "Connected", ProviderKind.gemini: "Rate limited"},
                recent_projects=["cli-pulse-helper"],
            ),
            DeviceRecordDTO(
                id=str(uuid4()),
                name="build-box",
                type="Linux VM",
                system="Debian 13",
                status=DeviceStatus.offline,
                last_sync_at=now - timedelta(hours=2),
                helper_version="0.1.1",
                current_session_count=0,
                cpu_usage=0,
                memory_usage=0,
                heartbeat_timeline=[UsagePointDTO(timestamp=now - timedelta(minutes=100 - index * 20), value=value) for index, value in enumerate([74, 52, 41, 19, 0, 0])],
                recent_sync_errors=["Helper process exited unexpectedly."],
                provider_status={ProviderKind.codex: "Auth expired"},
                recent_projects=["backend-api"],
            ),
        ]

        alerts = [
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.helper_offline,
                severity=AlertSeverity.critical,
                title="build-box helper offline",
                message="设备 2 小时未上报 heartbeat，相关 session 已停止同步。",
                created_at=now - timedelta(minutes=20),
                is_read=False,
                is_resolved=False,
            ),
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.quota_low,
                severity=AlertSeverity.warning,
                title="Codex remaining quota below 20%",
                message="本周累计 usage 接近上限，建议降低后台任务并开启阈值提醒。",
                created_at=now - timedelta(hours=1),
                is_read=False,
                is_resolved=False,
            ),
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.session_failed,
                severity=AlertSeverity.warning,
                title="backend-api session failed",
                message="最近一次任务因 provider auth expired 失败，共重试 3 次。",
                created_at=now - timedelta(hours=2),
                is_read=True,
                is_resolved=False,
            ),
        ]

        self.connection.execute(
            """
            UPDATE users
            SET providers_json = ?, sessions_json = ?, devices_json = ?, alerts_json = ?
            WHERE id = ?
            """,
            (
                self._encode_models(providers),
                self._encode_models(sessions),
                self._encode_models(devices),
                self._encode_models(alerts),
                user_id,
            ),
        )
        self.connection.commit()

    def _apply_device_health_rules(self, user_id: str) -> None:
        devices = self._load_models(user_id, "devices_json", DeviceRecordDTO)
        updated = False
        cutoff = now_utc() - timedelta(minutes=5)
        degraded_cutoff = now_utc() - timedelta(minutes=2)
        for device in devices:
            if device.last_sync_at < cutoff and device.status != DeviceStatus.offline:
                device.status = DeviceStatus.offline
                updated = True
            elif device.last_sync_at < degraded_cutoff and device.status == DeviceStatus.online:
                device.status = DeviceStatus.degraded
                updated = True
        if updated:
            self._save_models(user_id, "devices_json", devices)

    def _device_belongs_to_user(self, device_id: str, user_id: str) -> bool:
        row = self.connection.execute(
            "SELECT 1 FROM device_tokens WHERE device_id = ? AND user_id = ?",
            (device_id, user_id),
        ).fetchone()
        return row is not None

    def _session_for_user(self, user_id: str) -> Optional[SessionState]:
        row = self.connection.execute(
            """
            SELECT t.token, u.id, u.name, u.email, u.paired
            FROM auth_tokens t
            JOIN users u ON u.id = t.user_id
            WHERE u.id = ?
            ORDER BY t.created_at DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if row is None:
            return None
        return SessionState(
            token=row["token"],
            user=UserDTO(id=row["id"], name=row["name"], email=row["email"]),
            paired=bool(row["paired"]),
        )

    def _require_session(self, token: str) -> SessionState:
        state = self.authenticate(token)
        if state is None:
            raise PermissionError("Invalid token")
        return state

    def _load_models(self, user_id: str, column: str, model_cls: Any) -> list[Any]:
        row = self.connection.execute(f"SELECT {column} FROM users WHERE id = ?", (user_id,)).fetchone()
        raw = row[column] if row is not None else "[]"
        data = json.loads(raw)
        return [model_cls.model_validate(item) for item in data]

    def _save_models(self, user_id: str, column: str, models: Iterable[Any]) -> None:
        with self.lock:
            self.connection.execute(
                f"UPDATE users SET {column} = ? WHERE id = ?",
                (self._encode_models(models), user_id),
            )
            self.connection.commit()

    def _encode_models(self, models: Iterable[Any]) -> str:
        return json.dumps([model.model_dump(mode="json") for model in models], ensure_ascii=False)

    def _encode_model(self, model: Any) -> str:
        return model.model_dump_json()
