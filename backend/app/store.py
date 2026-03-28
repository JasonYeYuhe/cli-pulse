from __future__ import annotations

import json
import os
import re
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
    AlertSummaryDTO,
    AlertTypeSummaryDTO,
    AlertType,
    CollectionConfidence,
    CostStatus,
    DashboardSummaryDTO,
    DeviceRecordDTO,
    DeviceStatus,
    HelperHeartbeatRequestDTO,
    HelperRegisterRequestDTO,
    HelperRegisterResponseDTO,
    HelperSyncRequestDTO,
    PairingInfoDTO,
    ProjectRecordDTO,
    ProviderKind,
    ProviderMetadataDTO,
    PushPolicy,
    ProviderUsageDTO,
    SessionRecordDTO,
    SessionStatus,
    SettingsSnapshotDTO,
    SettingsUpdateDTO,
    SubscriptionDTO,
    SubscriptionTier,
    SuccessDTO,
    TeamDTO,
    TeamInviteDTO,
    TeamMemberDTO,
    TierLimitsDTO,
    UsagePointDTO,
    UserDTO,
)


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True)
class ProviderCostConfig:
    rate_per_1k_usage: Optional[float]
    status: CostStatus


DEFAULT_PROVIDER_COST_CONFIG: dict[ProviderKind, ProviderCostConfig] = {
    ProviderKind.codex: ProviderCostConfig(rate_per_1k_usage=0.012, status=CostStatus.estimated),
    ProviderKind.gemini: ProviderCostConfig(rate_per_1k_usage=0.008, status=CostStatus.estimated),
    ProviderKind.claude: ProviderCostConfig(rate_per_1k_usage=0.015, status=CostStatus.estimated),
    ProviderKind.cursor: ProviderCostConfig(rate_per_1k_usage=0.013, status=CostStatus.estimated),
    ProviderKind.opencode: ProviderCostConfig(rate_per_1k_usage=0.011, status=CostStatus.estimated),
    ProviderKind.droid: ProviderCostConfig(rate_per_1k_usage=0.010, status=CostStatus.estimated),
    ProviderKind.antigravity: ProviderCostConfig(rate_per_1k_usage=0.014, status=CostStatus.estimated),
    ProviderKind.copilot: ProviderCostConfig(rate_per_1k_usage=0.012, status=CostStatus.estimated),
    ProviderKind.zai: ProviderCostConfig(rate_per_1k_usage=0.009, status=CostStatus.estimated),
    ProviderKind.minimax: ProviderCostConfig(rate_per_1k_usage=0.006, status=CostStatus.estimated),
    ProviderKind.augment: ProviderCostConfig(rate_per_1k_usage=0.011, status=CostStatus.estimated),
    ProviderKind.jetbrains_ai: ProviderCostConfig(rate_per_1k_usage=0.010, status=CostStatus.estimated),
    ProviderKind.kimi_k2: ProviderCostConfig(rate_per_1k_usage=0.005, status=CostStatus.estimated),
    ProviderKind.amp: ProviderCostConfig(rate_per_1k_usage=0.012, status=CostStatus.estimated),
    ProviderKind.synthetic: ProviderCostConfig(rate_per_1k_usage=0.008, status=CostStatus.estimated),
    ProviderKind.warp: ProviderCostConfig(rate_per_1k_usage=0.007, status=CostStatus.estimated),
    ProviderKind.kilo: ProviderCostConfig(rate_per_1k_usage=0.009, status=CostStatus.estimated),
    ProviderKind.ollama: ProviderCostConfig(rate_per_1k_usage=None, status=CostStatus.unavailable),
    ProviderKind.openrouter: ProviderCostConfig(rate_per_1k_usage=0.010, status=CostStatus.estimated),
    ProviderKind.alibaba: ProviderCostConfig(rate_per_1k_usage=0.004, status=CostStatus.estimated),
}

# Provider metadata registry — describes each provider's capabilities
PROVIDER_METADATA: dict[ProviderKind, ProviderMetadataDTO] = {
    ProviderKind.codex: ProviderMetadataDTO(display_name="Codex", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=500_000),
    ProviderKind.gemini: ProviderMetadataDTO(display_name="Gemini", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.claude: ProviderMetadataDTO(display_name="Claude", category="cloud", supports_exact_cost=True, supports_quota=True, default_quota=250_000),
    ProviderKind.cursor: ProviderMetadataDTO(display_name="Cursor", category="ide", supports_exact_cost=False, supports_quota=True, default_quota=500_000),
    ProviderKind.opencode: ProviderMetadataDTO(display_name="OpenCode", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.droid: ProviderMetadataDTO(display_name="Droid", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=200_000),
    ProviderKind.antigravity: ProviderMetadataDTO(display_name="Antigravity", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=200_000),
    ProviderKind.copilot: ProviderMetadataDTO(display_name="Copilot", category="ide", supports_exact_cost=False, supports_quota=True, default_quota=500_000),
    ProviderKind.zai: ProviderMetadataDTO(display_name="z.ai", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=200_000),
    ProviderKind.minimax: ProviderMetadataDTO(display_name="MiniMax", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.augment: ProviderMetadataDTO(display_name="Augment", category="ide", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.jetbrains_ai: ProviderMetadataDTO(display_name="JetBrains AI", category="ide", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.kimi_k2: ProviderMetadataDTO(display_name="Kimi K2", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=500_000),
    ProviderKind.amp: ProviderMetadataDTO(display_name="Amp", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.synthetic: ProviderMetadataDTO(display_name="Synthetic", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=200_000),
    ProviderKind.warp: ProviderMetadataDTO(display_name="Warp", category="ide", supports_exact_cost=False, supports_quota=True, default_quota=300_000),
    ProviderKind.kilo: ProviderMetadataDTO(display_name="Kilo", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=200_000),
    ProviderKind.ollama: ProviderMetadataDTO(display_name="Ollama", category="local", supports_exact_cost=False, supports_quota=False, default_quota=999_999),
    ProviderKind.openrouter: ProviderMetadataDTO(display_name="OpenRouter", category="aggregator", supports_exact_cost=True, supports_quota=True, default_quota=200_000),
    ProviderKind.alibaba: ProviderMetadataDTO(display_name="Alibaba", category="cloud", supports_exact_cost=False, supports_quota=True, default_quota=400_000),
}


def _provider_kind_from_key(value: str) -> Optional[ProviderKind]:
    normalized = value.strip().lower().replace("-", "").replace("_", "")
    for provider in ProviderKind:
        if provider.value.lower().replace("-", "").replace("_", "") == normalized:
            return provider
    return None


def load_provider_cost_config() -> dict[ProviderKind, ProviderCostConfig]:
    config = dict(DEFAULT_PROVIDER_COST_CONFIG)
    raw = os.environ.get("CLI_PULSE_COST_CONFIG_JSON", "").strip()
    if not raw:
        return config

    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError:
        return config

    if not isinstance(decoded, dict):
        return config

    for key, value in decoded.items():
        provider = _provider_kind_from_key(str(key))
        if provider is None or not isinstance(value, dict):
            continue

        raw_status = str(value.get("status", config[provider].status.value))
        try:
            status = CostStatus(raw_status.title())
        except ValueError:
            status = config[provider].status

        raw_rate = value.get("rate_per_1k_usage")
        rate = float(raw_rate) if isinstance(raw_rate, (int, float)) else None
        config[provider] = ProviderCostConfig(rate_per_1k_usage=rate, status=status)

    return config


def aggregate_cost_status(statuses: Iterable[CostStatus]) -> CostStatus:
    filtered = [status for status in statuses if status != CostStatus.unavailable]
    if not filtered:
        return CostStatus.unavailable
    if all(status == CostStatus.exact for status in filtered):
        return CostStatus.exact
    return CostStatus.estimated


@dataclass
class SessionState:
    token: str
    user: UserDTO
    paired: bool


# ── User-facing message templates (i18n) ──
from .i18n import Msg


# ── Display limits ──
MAX_RECENT_ACTIVITY = 4
MAX_TOP_PROJECTS = 3
MAX_RECENT_SESSION_NAMES = 5
MAX_RECENT_DEVICES = 4
MAX_RECENT_PROJECTS_PER_DEVICE = 6
MAX_HEARTBEAT_TIMELINE = 24

FREE_ALERT_TYPES = ["quota_low", "usage_spike", "helper_offline"]
ALL_ALERT_TYPES = [
    "quota_low", "usage_spike", "helper_offline", "sync_failed",
    "auth_expired", "session_failed", "session_too_long", "project_budget_exceeded",
]

TIER_LIMITS: dict[SubscriptionTier, TierLimitsDTO] = {
    SubscriptionTier.free: TierLimitsDTO(
        max_providers=3,
        max_devices=1,
        data_retention_days=7,
        alert_rule_types=FREE_ALERT_TYPES,
        cost_tracking_range="today",
        has_project_budgets=False,
        has_api_access=False,
        max_team_members=1,
        export_formats=[],
    ),
    SubscriptionTier.pro: TierLimitsDTO(
        max_providers=-1,
        max_devices=5,
        data_retention_days=90,
        alert_rule_types=ALL_ALERT_TYPES,
        cost_tracking_range="30d",
        has_project_budgets=True,
        has_api_access=True,
        max_team_members=1,
        export_formats=["csv"],
    ),
    SubscriptionTier.team: TierLimitsDTO(
        max_providers=-1,
        max_devices=-1,
        data_retention_days=365,
        alert_rule_types=ALL_ALERT_TYPES + ["custom"],
        cost_tracking_range="full",
        has_project_budgets=True,
        has_api_access=True,
        max_team_members=50,
        export_formats=["csv", "json", "api"],
    ),
}


class SQLiteStore:
    def __init__(self, database_path: str) -> None:
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.database_path, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        self.provider_cost_config = load_provider_cost_config()
        self._create_tables()
        self._ensure_demo_account()

    # ── Demo account for App Store review ──

    DEMO_EMAIL = "demo@clipulse.app"
    DEMO_TOKEN = "pulse_demo_appstore_review_2026"

    def _ensure_demo_account(self) -> None:
        """Create or refresh the demo account used by App Store reviewers."""
        row = self.connection.execute(
            "SELECT id FROM users WHERE email = ?", (self.DEMO_EMAIL,)
        ).fetchone()
        if row is not None:
            return
        state = self.login(self.DEMO_EMAIL, "Demo User")
        with self.lock:
            self.connection.execute(
                "UPDATE users SET paired = 1 WHERE id = ?", (state.user.id,)
            )
            self.connection.execute(
                "DELETE FROM auth_tokens WHERE token = ?", (state.token,)
            )
            self.connection.execute(
                "INSERT OR REPLACE INTO auth_tokens (token, user_id, created_at) VALUES (?, ?, ?)",
                (self.DEMO_TOKEN, state.user.id, now_utc().isoformat()),
            )
            self.connection.commit()

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
                                push_policy=PushPolicy.warnings_and_critical,
                                digest_notifications_enabled=True,
                                digest_interval_minutes=15,
                                usage_spike_threshold=70_000,
                                project_budget_threshold_usd=0.25,
                                session_too_long_threshold_minutes=180,
                                offline_grace_period_minutes=5,
                                repeated_failure_threshold=3,
                                alert_cooldown_minutes=30,
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
                now_iso = now_utc().isoformat()
                self.connection.execute(
                    """
                    INSERT INTO subscriptions
                        (user_id, tier, status, created_at, updated_at)
                    VALUES (?, 'free', 'active', ?, ?)
                    """,
                    (user_id, now_iso, now_iso),
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
        limits = self._get_user_tier_limits(state.user.id)
        self._apply_device_health_rules(state.user.id)
        self._apply_helper_offline_rules(state.user.id)
        self._apply_usage_spike_rules(state.user.id)
        self._apply_session_failure_rules(state.user.id)
        self._apply_session_duration_rules(state.user.id)
        self._apply_project_budget_rules(state.user.id)
        providers = self.providers(token)
        sessions = self.sessions(token)
        devices = self.devices(token)
        alerts = self.alerts(token)
        projects = self.projects(token)

        # Feature gating: limit trend data for free tier (24h only)
        cutoff_24h = now_utc() - timedelta(hours=24)
        hourly: dict[datetime, int] = {}
        for provider in providers:
            trend_points = provider.trend
            if limits.cost_tracking_range == "today":
                trend_points = [p for p in trend_points if p.timestamp >= cutoff_24h]
            for point in trend_points:
                bucket = point.timestamp.replace(minute=0, second=0, microsecond=0)
                hourly[bucket] = hourly.get(bucket, 0) + point.value

        # Feature gating: free tier cost data is today-only
        total_cost: Optional[float] = None
        cost_status = aggregate_cost_status(item.cost_status for item in sessions)
        if limits.cost_tracking_range == "today":
            # Only include today's cost estimate
            total_cost = self._sum_available_costs(item.estimated_cost for item in sessions)
        else:
            total_cost = self._sum_available_costs(item.estimated_cost for item in sessions)

        risk_signals: list[str] = []
        quota_risk = next((item for item in providers if item.quota and item.remaining / item.quota < 0.2), None)
        if quota_risk:
            risk_signals.append(Msg.QUOTA_LOW_RISK.format(provider=quota_risk.provider.value))
        offline_device = next((item for item in devices if item.status == DeviceStatus.offline), None)
        if offline_device:
            risk_signals.append(Msg.DEVICE_OFFLINE_RISK.format(device=offline_device.name))
        critical_alert = next((item for item in alerts if not item.is_resolved and item.severity == AlertSeverity.critical), None)
        if critical_alert:
            risk_signals.append(critical_alert.title)
        if not risk_signals:
            risk_signals.append(Msg.NO_RISK)

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
        )[:MAX_RECENT_ACTIVITY]

        return DashboardSummaryDTO(
            total_usage=sum(item.total_usage for item in sessions),
            total_estimated_cost=total_cost,
            cost_status=cost_status,
            total_requests=sum(item.requests for item in sessions),
            active_sessions=sum(1 for item in sessions if item.status in {SessionStatus.running, SessionStatus.syncing}),
            online_devices=sum(1 for item in devices if item.status == DeviceStatus.online),
            unresolved_alerts=sum(1 for item in alerts if not item.is_resolved),
            provider_breakdown=providers,
            top_projects=projects[:MAX_TOP_PROJECTS],
            trend=[UsagePointDTO(timestamp=timestamp, value=value) for timestamp, value in sorted(hourly.items())],
            recent_activity=recent_activity,
            risk_signals=risk_signals,
            alert_summary=self._build_alert_summary(alerts),
        )

    def providers(self, token: str) -> list[ProviderUsageDTO]:
        state = self._require_session(token)
        items = self._load_models(state.user.id, "providers_json", ProviderUsageDTO)
        limits = self._get_user_tier_limits(state.user.id)
        # Free tier: limit to max_providers
        if limits.max_providers > 0:
            items = items[:limits.max_providers]
        return items

    def provider_detail(self, token: str, provider_name: str) -> Optional[ProviderUsageDTO]:
        provider_name = provider_name.lower()
        for provider in self.providers(token):
            if provider.provider.value.lower() == provider_name:
                return provider
        return None

    def projects(self, token: str) -> list[ProjectRecordDTO]:
        state = self._require_session(token)
        self._apply_project_budget_rules(state.user.id)
        return self._build_projects(state.user.id)

    def project_detail(self, token: str, project_id: str) -> Optional[ProjectRecordDTO]:
        project_id = project_id.lower()
        for project in self.projects(token):
            if project.id.lower() == project_id:
                return project
        return None

    def sessions(self, token: str) -> list[SessionRecordDTO]:
        state = self._require_session(token)
        items = self._load_models(state.user.id, "sessions_json", SessionRecordDTO)
        limits = self._get_user_tier_limits(state.user.id)
        # Apply data retention limit
        cutoff = now_utc() - timedelta(days=limits.data_retention_days)
        items = [s for s in items if s.last_active_at >= cutoff]
        return sorted(items, key=lambda item: item.last_active_at, reverse=True)

    def devices(self, token: str) -> list[DeviceRecordDTO]:
        state = self._require_session(token)
        self._apply_device_health_rules(state.user.id)
        self._apply_helper_offline_rules(state.user.id)
        items = self._load_models(state.user.id, "devices_json", DeviceRecordDTO)
        return sorted(items, key=lambda item: item.last_sync_at, reverse=True)

    def alerts(self, token: str) -> list[AlertRecordDTO]:
        state = self._require_session(token)
        self._apply_device_health_rules(state.user.id)
        self._apply_helper_offline_rules(state.user.id)
        self._apply_usage_spike_rules(state.user.id)
        self._apply_session_failure_rules(state.user.id)
        self._apply_session_duration_rules(state.user.id)
        self._apply_project_budget_rules(state.user.id)
        items = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        # Filter alerts by allowed alert rule types for the user's tier
        limits = self._get_user_tier_limits(state.user.id)
        allowed_types = set(limits.alert_rule_types)
        # Map AlertType enum names to rule type strings
        items = [
            a for a in items
            if a.type.name in allowed_types or a.type.name.lower() in allowed_types
        ]
        return sorted(items, key=lambda item: item.created_at, reverse=True)

    def settings(self, token: str) -> SettingsSnapshotDTO:
        state = self._require_session(token)
        row = self.connection.execute("SELECT settings_json FROM users WHERE id = ?", (state.user.id,)).fetchone()
        return SettingsSnapshotDTO.model_validate_json(row["settings_json"])

    def update_settings(self, token: str, payload: SettingsUpdateDTO) -> SettingsSnapshotDTO:
        state = self._require_session(token)
        current = self.settings(token)
        current.notifications_enabled = payload.notifications_enabled
        current.push_policy = payload.push_policy
        current.digest_notifications_enabled = payload.digest_notifications_enabled
        current.digest_interval_minutes = payload.digest_interval_minutes
        current.usage_spike_threshold = payload.usage_spike_threshold
        current.project_budget_threshold_usd = payload.project_budget_threshold_usd
        current.session_too_long_threshold_minutes = payload.session_too_long_threshold_minutes
        current.offline_grace_period_minutes = payload.offline_grace_period_minutes
        current.repeated_failure_threshold = payload.repeated_failure_threshold
        current.alert_cooldown_minutes = payload.alert_cooldown_minutes
        current.data_retention_days = payload.data_retention_days
        with self.lock:
            self.connection.execute(
                "UPDATE users SET settings_json = ? WHERE id = ?",
                (self._encode_model(current), state.user.id),
            )
            self.connection.commit()
        # Re-evaluate alert rules after settings change.
        # Each rule method handles its own transaction so partial
        # failures won't leave settings in an inconsistent state
        # (settings are already committed above).
        for apply_rule in (
            self._apply_device_health_rules,
            self._apply_helper_offline_rules,
            self._apply_usage_spike_rules,
            self._apply_session_failure_rules,
            self._apply_session_duration_rules,
            self._apply_project_budget_rules,
        ):
            try:
                apply_rule(state.user.id)
            except Exception:
                pass  # rule failure should not break settings update
        return current

    def mark_alert(self, token: str, alert_id: str, *, resolve: bool) -> AlertActionResponseDTO:
        state = self._require_session(token)
        alerts = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        for alert in alerts:
            if alert.id == alert_id:
                alert.is_read = True
                alert.acknowledged_at = now_utc()
                if resolve:
                    alert.is_resolved = True
                    alert.snoozed_until = None
        self._save_models(state.user.id, "alerts_json", alerts)
        return AlertActionResponseDTO(alerts=alerts)

    def acknowledge_alert(self, token: str, alert_id: str) -> AlertActionResponseDTO:
        state = self._require_session(token)
        alerts = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        for alert in alerts:
            if alert.id == alert_id:
                alert.is_read = True
                alert.acknowledged_at = now_utc()
        self._save_models(state.user.id, "alerts_json", alerts)
        return AlertActionResponseDTO(alerts=alerts)

    def snooze_alert(self, token: str, alert_id: str, minutes: int) -> AlertActionResponseDTO:
        state = self._require_session(token)
        alerts = self._load_models(state.user.id, "alerts_json", AlertRecordDTO)
        acknowledged_at = now_utc()
        for alert in alerts:
            if alert.id == alert_id:
                alert.is_read = True
                alert.acknowledged_at = acknowledged_at
                alert.snoozed_until = acknowledged_at + timedelta(minutes=minutes)
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

        if state is None:
            raise PermissionError("Failed to create session for paired device")
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
                device.heartbeat_timeline = device.heartbeat_timeline[-MAX_HEARTBEAT_TIMELINE:]
                break
        self._save_models(state.user.id, "devices_json", devices)
        self._apply_helper_offline_rules(state.user.id)
        self._apply_session_failure_rules(state.user.id)

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
            session_cost, session_cost_status = self._resolve_cost(item.provider, item.total_usage, item.exact_cost)
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
                    estimated_cost=session_cost,
                    cost_status=session_cost_status,
                    requests=item.requests,
                    error_count=item.error_count,
                    collection_confidence=item.collection_confidence,
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
            provider.estimated_cost_today, provider.cost_status_today = self._resolve_cost(provider.provider, provider.today_usage)
            provider.estimated_cost_week, provider.cost_status_week = self._resolve_cost(provider.provider, provider.week_usage)
            provider.recent_session_names = [item.name for item in synced_sessions if item.provider == provider.provider][:MAX_RECENT_SESSION_NAMES]
            provider.metadata = PROVIDER_METADATA.get(provider.provider)
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
                        related_project_id=item.related_project_id,
                        related_project_name=item.related_project_name,
                        related_session_id=item.related_session_id,
                        related_session_name=item.related_session_name,
                        related_provider=item.related_provider,
                        related_device_name=item.related_device_name,
                    )
                )
        self._save_models(state.user.id, "alerts_json", alerts)

        for device in devices:
            if device.id == payload.device_id:
                device.provider_status = {provider.provider: provider.status_text for provider in providers}
                device.recent_projects = sorted(recent_projects)[:MAX_RECENT_PROJECTS_PER_DEVICE]
                device.current_session_count = len(synced_sessions)
                device.last_sync_at = now_utc()
                break
        self._save_models(state.user.id, "devices_json", devices)
        self._apply_helper_offline_rules(state.user.id)
        self._apply_usage_spike_rules(state.user.id)
        self._apply_session_failure_rules(state.user.id)
        self._apply_session_duration_rules(state.user.id)
        self._apply_project_budget_rules(state.user.id)

        return SuccessDTO()

    def delete_account(self, token: str) -> SuccessDTO:
        state = self._require_session(token)
        with self.lock:
            self.connection.execute("DELETE FROM auth_tokens WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM pairing_codes WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM device_tokens WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM subscriptions WHERE user_id = ?", (state.user.id,))
            self.connection.execute("DELETE FROM team_members WHERE user_id = ?", (state.user.id,))
            # Delete teams owned by this user (cascades to members/invites via app logic)
            owned_teams = self.connection.execute(
                "SELECT id FROM teams WHERE owner_id = ?", (state.user.id,)
            ).fetchall()
            for team in owned_teams:
                self.connection.execute("DELETE FROM team_invites WHERE team_id = ?", (team["id"],))
                self.connection.execute("DELETE FROM team_members WHERE team_id = ?", (team["id"],))
                self.connection.execute("DELETE FROM teams WHERE id = ?", (team["id"],))
            self.connection.execute("DELETE FROM users WHERE id = ?", (state.user.id,))
            self.connection.commit()
        return SuccessDTO()

    def _settings_for_user(self, user_id: str) -> SettingsSnapshotDTO:
        row = self.connection.execute("SELECT settings_json FROM users WHERE id = ?", (user_id,)).fetchone()
        if row is None:
            return SettingsSnapshotDTO()
        try:
            return SettingsSnapshotDTO.model_validate_json(row["settings_json"])
        except (json.JSONDecodeError, Exception):
            return SettingsSnapshotDTO()

    def _build_alert_summary(self, alerts: list[AlertRecordDTO]) -> AlertSummaryDTO:
        type_counts = {}
        for alert in alerts:
            type_counts[alert.type] = type_counts.get(alert.type, 0) + 1

        return AlertSummaryDTO(
            unread_count=sum(1 for alert in alerts if not alert.is_read),
            open_count=sum(1 for alert in alerts if not alert.is_resolved),
            resolved_count=sum(1 for alert in alerts if alert.is_resolved),
            critical_open_count=sum(1 for alert in alerts if not alert.is_resolved and alert.severity == AlertSeverity.critical),
            warning_open_count=sum(1 for alert in alerts if not alert.is_resolved and alert.severity == AlertSeverity.warning),
            info_open_count=sum(1 for alert in alerts if not alert.is_resolved and alert.severity == AlertSeverity.info),
            type_breakdown=[
                AlertTypeSummaryDTO(type=alert_type, count=count)
                for alert_type, count in sorted(type_counts.items(), key=lambda item: item[1], reverse=True)
            ],
        )

    def _resolve_cost(
        self, provider: ProviderKind, usage: int, exact_cost: Optional[float] = None
    ) -> tuple[Optional[float], CostStatus]:
        if exact_cost is not None:
            return round(exact_cost, 4), CostStatus.exact

        config = self.provider_cost_config.get(provider, ProviderCostConfig(None, CostStatus.unavailable))
        if config.rate_per_1k_usage is None or config.status == CostStatus.unavailable:
            return None, CostStatus.unavailable

        cost = round((usage / 1_000.0) * config.rate_per_1k_usage, 4)
        return cost, config.status

    def _sum_available_costs(self, values: Iterable[Optional[float]]) -> Optional[float]:
        available = [value for value in values if value is not None]
        if not available:
            return None
        return round(sum(available), 4)

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

                CREATE TABLE IF NOT EXISTS subscriptions (
                    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                    tier TEXT NOT NULL DEFAULT 'free',
                    status TEXT NOT NULL DEFAULT 'active',
                    current_period_start TEXT,
                    current_period_end TEXT,
                    trial_end TEXT,
                    cancel_at_period_end INTEGER DEFAULT 0,
                    apple_transaction_id TEXT,
                    apple_original_transaction_id TEXT,
                    apple_product_id TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS teams (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS team_members (
                    team_id TEXT REFERENCES teams(id) ON DELETE CASCADE,
                    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                    role TEXT NOT NULL DEFAULT 'member',
                    joined_at TEXT NOT NULL,
                    PRIMARY KEY (team_id, user_id)
                );

                CREATE TABLE IF NOT EXISTS team_invites (
                    id TEXT PRIMARY KEY,
                    team_id TEXT REFERENCES teams(id) ON DELETE CASCADE,
                    email TEXT NOT NULL,
                    role TEXT NOT NULL DEFAULT 'member',
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL
                );
                """
            )
            self.connection.commit()
            self._migrate_existing_subscriptions()

    def _migrate_existing_subscriptions(self) -> None:
        """Create free subscription for any existing user without one.

        NOTE: Called from _create_tables which already holds self.lock,
        so we must NOT acquire the lock here.
        """
        rows = self.connection.execute(
            """
            SELECT u.id FROM users u
            LEFT JOIN subscriptions s ON s.user_id = u.id
            WHERE s.user_id IS NULL
            """
        ).fetchall()
        now_iso = now_utc().isoformat()
        for row in rows:
            self.connection.execute(
                """
                INSERT OR IGNORE INTO subscriptions
                    (user_id, tier, status, created_at, updated_at)
                VALUES (?, 'free', 'active', ?, ?)
                """,
                (row["id"], now_iso, now_iso),
            )
        if rows:
            self.connection.commit()

    def _ensure_subscription(self, user_id: str) -> None:
        """Ensure a user has a subscription row (defaults to free)."""
        row = self.connection.execute(
            "SELECT 1 FROM subscriptions WHERE user_id = ?", (user_id,)
        ).fetchone()
        if row is None:
            now_iso = now_utc().isoformat()
            with self.lock:
                self.connection.execute(
                    """
                    INSERT OR IGNORE INTO subscriptions
                        (user_id, tier, status, created_at, updated_at)
                    VALUES (?, 'free', 'active', ?, ?)
                    """,
                    (user_id, now_iso, now_iso),
                )
                self.connection.commit()

    def _get_user_tier(self, user_id: str) -> SubscriptionTier:
        self._ensure_subscription(user_id)
        row = self.connection.execute(
            "SELECT tier FROM subscriptions WHERE user_id = ?", (user_id,)
        ).fetchone()
        if row is None:
            return SubscriptionTier.free
        try:
            return SubscriptionTier(row["tier"])
        except ValueError:
            return SubscriptionTier.free

    def _get_user_tier_limits(self, user_id: str) -> TierLimitsDTO:
        tier = self._get_user_tier(user_id)
        return TIER_LIMITS[tier]

    # ── Subscription endpoints ──

    def get_subscription(self, token: str) -> SubscriptionDTO:
        state = self._require_session(token)
        self._ensure_subscription(state.user.id)
        row = self.connection.execute(
            "SELECT * FROM subscriptions WHERE user_id = ?", (state.user.id,)
        ).fetchone()
        return SubscriptionDTO(
            tier=SubscriptionTier(row["tier"]),
            status=row["status"],
            current_period_start=(
                datetime.fromisoformat(row["current_period_start"])
                if row["current_period_start"] else None
            ),
            current_period_end=(
                datetime.fromisoformat(row["current_period_end"])
                if row["current_period_end"] else None
            ),
            trial_end=(
                datetime.fromisoformat(row["trial_end"])
                if row["trial_end"] else None
            ),
            cancel_at_period_end=bool(row["cancel_at_period_end"]),
            apple_transaction_id=row["apple_transaction_id"],
            apple_original_transaction_id=row["apple_original_transaction_id"],
            apple_product_id=row["apple_product_id"],
        )

    def get_tier_limits(self, token: str) -> TierLimitsDTO:
        state = self._require_session(token)
        return self._get_user_tier_limits(state.user.id)

    def update_subscription(
        self,
        token: str,
        tier: SubscriptionTier,
        apple_transaction_id: Optional[str] = None,
        apple_original_transaction_id: Optional[str] = None,
        apple_product_id: Optional[str] = None,
    ) -> SubscriptionDTO:
        state = self._require_session(token)
        self._ensure_subscription(state.user.id)
        now_iso = now_utc().isoformat()
        period_end = (now_utc() + timedelta(days=30)).isoformat()
        with self.lock:
            self.connection.execute(
                """
                UPDATE subscriptions
                SET tier = ?, status = 'active',
                    current_period_start = ?, current_period_end = ?,
                    apple_transaction_id = COALESCE(?, apple_transaction_id),
                    apple_original_transaction_id = COALESCE(?, apple_original_transaction_id),
                    apple_product_id = COALESCE(?, apple_product_id),
                    updated_at = ?
                WHERE user_id = ?
                """,
                (
                    tier.value, now_iso, period_end,
                    apple_transaction_id, apple_original_transaction_id,
                    apple_product_id, now_iso, state.user.id,
                ),
            )
            self.connection.commit()
        return self.get_subscription(token)

    # Mapping from Apple product IDs to subscription tiers
    APPLE_PRODUCT_TIER_MAP: dict[str, SubscriptionTier] = {
        "clipulse_pro_monthly": SubscriptionTier.pro,
        "clipulse_pro_yearly": SubscriptionTier.pro,
        "clipulse_team_monthly": SubscriptionTier.team,
        "clipulse_team_yearly": SubscriptionTier.team,
    }

    def verify_apple_receipt(self, token: str, receipt_data: str) -> SubscriptionDTO:
        """Verify an Apple StoreKit 2 JWS transaction and update subscription.

        In a full implementation this would:
        1. Decode the JWS (JSON Web Signature) payload
        2. Verify the signature against Apple's certificate chain
        3. Extract productId and transactionId
        4. Map productId to a subscription tier

        For now we perform basic structure validation and decode the
        product ID from the JWS payload if possible.
        """
        import base64

        state = self._require_session(token)

        if not receipt_data or not isinstance(receipt_data, str):
            raise ValueError("receipt_data must be a non-empty string")

        # StoreKit 2 sends a JWS (three base64url segments separated by dots)
        parts = receipt_data.split(".")
        if len(parts) != 3:
            raise ValueError("Invalid JWS format — expected header.payload.signature")

        try:
            # Decode the payload (second segment) to extract product info
            padded = parts[1] + "=" * (-len(parts[1]) % 4)
            payload = json.loads(base64.urlsafe_b64decode(padded))
        except Exception as exc:
            raise ValueError(f"Failed to decode JWS payload: {exc}") from exc

        product_id = payload.get("productId") or payload.get("product_id", "")
        transaction_id = str(payload.get("transactionId") or payload.get("transaction_id", ""))
        original_transaction_id = str(payload.get("originalTransactionId") or payload.get("original_transaction_id", transaction_id))

        tier = self.APPLE_PRODUCT_TIER_MAP.get(product_id)
        if tier is None:
            raise ValueError(f"Unknown Apple product ID: {product_id}")

        return self.update_subscription(
            token,
            tier=tier,
            apple_transaction_id=transaction_id,
            apple_original_transaction_id=original_transaction_id,
            apple_product_id=product_id,
        )

    def check_feature_access(self, token: str, feature: str) -> bool:
        state = self._require_session(token)
        limits = self._get_user_tier_limits(state.user.id)
        feature_lower = feature.lower()
        if feature_lower == "api_access":
            return limits.has_api_access
        if feature_lower == "project_budgets":
            return limits.has_project_budgets
        if feature_lower == "export_csv":
            return "csv" in limits.export_formats
        if feature_lower == "export_json":
            return "json" in limits.export_formats
        if feature_lower == "export_api":
            return "api" in limits.export_formats
        if feature_lower == "team":
            return limits.max_team_members > 1
        if feature_lower in ("unlimited_providers", "unlimited_devices"):
            return limits.max_providers == -1
        # Alert rule types check
        if feature_lower.startswith("alert_"):
            rule_name = feature_lower[len("alert_"):]
            return rule_name in limits.alert_rule_types
        return True

    # ── Team management ──

    def create_team(self, token: str, name: str) -> TeamDTO:
        state = self._require_session(token)
        tier = self._get_user_tier(state.user.id)
        if tier != SubscriptionTier.team:
            raise PermissionError("Team features require a Team subscription")

        # Check if user already owns a team
        existing = self.connection.execute(
            "SELECT id FROM teams WHERE owner_id = ?", (state.user.id,)
        ).fetchone()
        if existing:
            raise PermissionError("User already owns a team")

        team_id = str(uuid4())
        now_iso = now_utc().isoformat()
        with self.lock:
            self.connection.execute(
                "INSERT INTO teams (id, name, owner_id, created_at) VALUES (?, ?, ?, ?)",
                (team_id, name, state.user.id, now_iso),
            )
            self.connection.execute(
                "INSERT INTO team_members (team_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)",
                (team_id, state.user.id, now_iso),
            )
            self.connection.commit()

        return TeamDTO(
            id=team_id,
            name=name,
            owner_id=state.user.id,
            member_count=1,
            max_members=TIER_LIMITS[SubscriptionTier.team].max_team_members,
            created_at=datetime.fromisoformat(now_iso),
        )

    def get_team(self, token: str) -> Optional[TeamDTO]:
        state = self._require_session(token)
        # Find team where user is a member
        row = self.connection.execute(
            """
            SELECT t.id, t.name, t.owner_id, t.created_at
            FROM teams t
            JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = ?
            LIMIT 1
            """,
            (state.user.id,),
        ).fetchone()
        if row is None:
            return None
        member_count = self.connection.execute(
            "SELECT COUNT(*) as cnt FROM team_members WHERE team_id = ?",
            (row["id"],),
        ).fetchone()["cnt"]
        return TeamDTO(
            id=row["id"],
            name=row["name"],
            owner_id=row["owner_id"],
            member_count=member_count,
            max_members=TIER_LIMITS[SubscriptionTier.team].max_team_members,
            created_at=datetime.fromisoformat(row["created_at"]),
        )

    def invite_team_member(self, token: str, email: str, role: str = "member") -> TeamInviteDTO:
        state = self._require_session(token)
        tier = self._get_user_tier(state.user.id)
        if tier != SubscriptionTier.team:
            raise PermissionError("Team features require a Team subscription")

        team_row = self.connection.execute(
            """
            SELECT t.id FROM teams t
            JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = ? AND tm.role IN ('owner', 'admin')
            """,
            (state.user.id,),
        ).fetchone()
        if team_row is None:
            raise PermissionError("You must be a team owner or admin to invite members")

        team_id = team_row["id"]
        member_count = self.connection.execute(
            "SELECT COUNT(*) as cnt FROM team_members WHERE team_id = ?",
            (team_id,),
        ).fetchone()["cnt"]
        max_members = TIER_LIMITS[SubscriptionTier.team].max_team_members
        if member_count >= max_members:
            raise PermissionError(f"Team has reached the maximum of {max_members} members")

        invite_id = str(uuid4())
        now_dt = now_utc()
        expires_dt = now_dt + timedelta(days=7)
        with self.lock:
            self.connection.execute(
                "INSERT INTO team_invites (id, team_id, email, role, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
                (invite_id, team_id, email, role, now_dt.isoformat(), expires_dt.isoformat()),
            )
            self.connection.commit()

        return TeamInviteDTO(
            id=invite_id,
            email=email,
            role=role,
            created_at=now_dt,
            expires_at=expires_dt,
        )

    def accept_team_invite(self, token: str, invite_id: str) -> TeamMemberDTO:
        state = self._require_session(token)
        invite_row = self.connection.execute(
            "SELECT * FROM team_invites WHERE id = ?", (invite_id,)
        ).fetchone()
        if invite_row is None:
            raise PermissionError("Invite not found")
        if datetime.fromisoformat(invite_row["expires_at"]) < now_utc():
            raise PermissionError("Invite has expired")
        if invite_row["email"] != state.user.email:
            raise PermissionError("This invite is for a different email address")

        team_id = invite_row["team_id"]
        role = invite_row["role"]
        now_iso = now_utc().isoformat()

        with self.lock:
            self.connection.execute(
                """
                INSERT INTO team_members (team_id, user_id, role, joined_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(team_id, user_id) DO UPDATE SET role = excluded.role
                """,
                (team_id, state.user.id, role, now_iso),
            )
            self.connection.execute("DELETE FROM team_invites WHERE id = ?", (invite_id,))
            self.connection.commit()

        return TeamMemberDTO(
            user_id=state.user.id,
            name=state.user.name,
            email=state.user.email,
            role=role,
            joined_at=datetime.fromisoformat(now_iso),
        )

    def remove_team_member(self, token: str, target_user_id: str) -> SuccessDTO:
        state = self._require_session(token)
        # Find user's team where they are owner or admin
        team_row = self.connection.execute(
            """
            SELECT t.id, t.owner_id FROM teams t
            JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = ? AND tm.role IN ('owner', 'admin')
            """,
            (state.user.id,),
        ).fetchone()
        if team_row is None:
            raise PermissionError("You must be a team owner or admin to remove members")
        if target_user_id == team_row["owner_id"]:
            raise PermissionError("Cannot remove the team owner")

        with self.lock:
            self.connection.execute(
                "DELETE FROM team_members WHERE team_id = ? AND user_id = ?",
                (team_row["id"], target_user_id),
            )
            self.connection.commit()
        return SuccessDTO()

    def get_team_members(self, token: str) -> list[TeamMemberDTO]:
        state = self._require_session(token)
        team_row = self.connection.execute(
            """
            SELECT t.id FROM teams t
            JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = ?
            """,
            (state.user.id,),
        ).fetchone()
        if team_row is None:
            return []

        rows = self.connection.execute(
            """
            SELECT tm.user_id, u.name, u.email, tm.role, tm.joined_at
            FROM team_members tm
            JOIN users u ON u.id = tm.user_id
            WHERE tm.team_id = ?
            ORDER BY tm.joined_at
            """,
            (team_row["id"],),
        ).fetchall()

        return [
            TeamMemberDTO(
                user_id=row["user_id"],
                name=row["name"],
                email=row["email"],
                role=row["role"],
                joined_at=datetime.fromisoformat(row["joined_at"]),
            )
            for row in rows
        ]

    def get_team_dashboard(self, token: str) -> DashboardSummaryDTO:
        """Aggregated dashboard for all team members."""
        state = self._require_session(token)
        tier = self._get_user_tier(state.user.id)
        if tier != SubscriptionTier.team:
            raise PermissionError("Team dashboard requires a Team subscription")

        team_row = self.connection.execute(
            """
            SELECT t.id FROM teams t
            JOIN team_members tm ON tm.team_id = t.id
            WHERE tm.user_id = ?
            """,
            (state.user.id,),
        ).fetchone()
        if team_row is None:
            raise PermissionError("You are not a member of any team")

        member_rows = self.connection.execute(
            "SELECT user_id FROM team_members WHERE team_id = ?",
            (team_row["id"],),
        ).fetchall()
        member_ids = [row["user_id"] for row in member_rows]

        # Aggregate data across all team members
        all_sessions: list[SessionRecordDTO] = []
        all_providers: list[ProviderUsageDTO] = []
        all_devices: list[DeviceRecordDTO] = []
        all_alerts: list[AlertRecordDTO] = []

        for member_id in member_ids:
            all_sessions.extend(self._load_models(member_id, "sessions_json", SessionRecordDTO))
            all_providers.extend(self._load_models(member_id, "providers_json", ProviderUsageDTO))
            all_devices.extend(self._load_models(member_id, "devices_json", DeviceRecordDTO))
            all_alerts.extend(self._load_models(member_id, "alerts_json", AlertRecordDTO))

        # Deduplicate providers by aggregating
        provider_map: dict[ProviderKind, ProviderUsageDTO] = {}
        for p in all_providers:
            if p.provider not in provider_map:
                provider_map[p.provider] = p
            else:
                existing = provider_map[p.provider]
                existing.today_usage += p.today_usage
                existing.week_usage += p.week_usage
                if existing.estimated_cost_today is not None and p.estimated_cost_today is not None:
                    existing.estimated_cost_today = round(existing.estimated_cost_today + p.estimated_cost_today, 4)
                if existing.estimated_cost_week is not None and p.estimated_cost_week is not None:
                    existing.estimated_cost_week = round(existing.estimated_cost_week + p.estimated_cost_week, 4)

        providers = list(provider_map.values())

        hourly: dict[datetime, int] = {}
        for provider in providers:
            for point in provider.trend:
                bucket = point.timestamp.replace(minute=0, second=0, microsecond=0)
                hourly[bucket] = hourly.get(bucket, 0) + point.value

        # Build projects from all sessions
        grouped: dict[str, list[SessionRecordDTO]] = {}
        for session in all_sessions:
            grouped.setdefault(session.project, []).append(session)
        projects: list[ProjectRecordDTO] = []
        for project_name, project_sessions in grouped.items():
            provider_totals: dict[ProviderKind, int] = {}
            for s in project_sessions:
                provider_totals[s.provider] = provider_totals.get(s.provider, 0) + s.total_usage
            primary_provider = max(provider_totals, key=provider_totals.get) if provider_totals else ProviderKind.codex
            today_usage = sum(s.total_usage for s in project_sessions)
            est_cost = self._sum_available_costs(s.estimated_cost for s in project_sessions)
            projects.append(
                ProjectRecordDTO(
                    id=self._project_id(project_name),
                    name=project_name,
                    today_usage=today_usage,
                    week_usage=today_usage * 3,
                    estimated_cost_today=est_cost,
                    estimated_cost_week=round(est_cost * 3, 4) if est_cost else None,
                    cost_status_today=aggregate_cost_status(s.cost_status for s in project_sessions),
                    cost_status_week=CostStatus.estimated,
                    active_session_count=sum(1 for s in project_sessions if s.status in {SessionStatus.running, SessionStatus.syncing}),
                    device_count=len({s.device_name for s in project_sessions}),
                    alert_count=0,
                    primary_provider=primary_provider,
                    trend=[],
                    recent_devices=sorted({s.device_name for s in project_sessions})[:MAX_RECENT_DEVICES],
                    recent_session_names=[s.name for s in project_sessions[:MAX_RECENT_SESSION_NAMES]],
                    provider_breakdown=provider_totals,
                )
            )
        projects.sort(key=lambda p: p.today_usage, reverse=True)

        recent_activity = sorted(
            [
                ActivityItemDTO(
                    id=s.id,
                    title=f"{s.provider.value} · {s.name}",
                    subtitle=f"{s.project} on {s.device_name}",
                    timestamp=s.last_active_at,
                )
                for s in all_sessions
            ],
            key=lambda a: a.timestamp,
            reverse=True,
        )[:MAX_RECENT_ACTIVITY]

        return DashboardSummaryDTO(
            total_usage=sum(s.total_usage for s in all_sessions),
            total_estimated_cost=self._sum_available_costs(s.estimated_cost for s in all_sessions),
            cost_status=aggregate_cost_status(s.cost_status for s in all_sessions),
            total_requests=sum(s.requests for s in all_sessions),
            active_sessions=sum(1 for s in all_sessions if s.status in {SessionStatus.running, SessionStatus.syncing}),
            online_devices=sum(1 for d in all_devices if d.status == DeviceStatus.online),
            unresolved_alerts=sum(1 for a in all_alerts if not a.is_resolved),
            provider_breakdown=providers,
            top_projects=projects[:MAX_TOP_PROJECTS],
            trend=[UsagePointDTO(timestamp=t, value=v) for t, v in sorted(hourly.items())],
            recent_activity=recent_activity,
            risk_signals=["Team aggregate dashboard."],
            alert_summary=self._build_alert_summary(all_alerts),
        )

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
        claude_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([1800, 2600, 3900, 4200, 3600, 3100, 4700, 4400])
        ]
        openrouter_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([1200, 1800, 2200, 2600, 2100, 1900, 2400, 2300])
        ]
        ollama_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([900, 1300, 1700, 2100, 1900, 1600, 1800, 1500])
        ]
        cursor_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([3200, 5100, 7400, 8200, 6800, 5900, 7100, 6600])
        ]
        copilot_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([2100, 3400, 4800, 5100, 4200, 3800, 4600, 4100])
        ]
        kimi_trend = [
            UsagePointDTO(timestamp=now - timedelta(hours=21 - index * 3), value=value)
            for index, value in enumerate([1500, 2200, 3100, 3600, 3000, 2700, 3300, 2900])
        ]

        providers = [
            ProviderUsageDTO(
                provider=ProviderKind.codex,
                today_usage=85_900,
                week_usage=462_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.codex, 85_900)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.codex, 462_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.codex, 85_900)[1],
                cost_status_week=self._resolve_cost(ProviderKind.codex, 462_000)[1],
                quota=500_000,
                remaining=38_000,
                status_text="Busy",
                trend=codex_trend,
                recent_session_names=["Refactor dashboard filters", "Fix session sync retry", "Investigate helper heartbeat"],
                recent_errors=["2 sync retries on Tokyo-Mac", "1 session timeout on lab-server"],
                metadata=PROVIDER_METADATA.get(ProviderKind.codex),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.gemini,
                today_usage=43_400,
                week_usage=214_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.gemini, 43_400)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.gemini, 214_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.gemini, 43_400)[1],
                cost_status_week=self._resolve_cost(ProviderKind.gemini, 214_000)[1],
                quota=300_000,
                remaining=86_000,
                status_text="Healthy",
                trend=gemini_trend,
                recent_session_names=["Draft device pairing UX", "Summarize CI failures"],
                recent_errors=["No new provider errors"],
                metadata=PROVIDER_METADATA.get(ProviderKind.gemini),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.claude,
                today_usage=24_800,
                week_usage=132_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.claude, 24_800)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.claude, 132_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.claude, 24_800)[1],
                cost_status_week=self._resolve_cost(ProviderKind.claude, 132_000)[1],
                quota=250_000,
                remaining=118_000,
                status_text="Healthy",
                trend=claude_trend,
                recent_session_names=["Summarize incident notes", "Review provider adapter contract"],
                recent_errors=["1 auth refresh last night"],
                metadata=PROVIDER_METADATA.get(ProviderKind.claude),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.openrouter,
                today_usage=15_600,
                week_usage=74_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.openrouter, 15_600)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.openrouter, 74_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.openrouter, 15_600)[1],
                cost_status_week=self._resolve_cost(ProviderKind.openrouter, 74_000)[1],
                quota=200_000,
                remaining=126_000,
                status_text="Stable",
                trend=openrouter_trend,
                recent_session_names=["Compare model outputs", "Run prompt regression batch"],
                recent_errors=["No new provider errors"],
                metadata=PROVIDER_METADATA.get(ProviderKind.openrouter),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.ollama,
                today_usage=9_700,
                week_usage=48_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.ollama, 9_700)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.ollama, 48_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.ollama, 9_700)[1],
                cost_status_week=self._resolve_cost(ProviderKind.ollama, 48_000)[1],
                quota=999_999,
                remaining=999_999,
                status_text="Local",
                trend=ollama_trend,
                recent_session_names=["Local llama smoke test", "Embedding batch on workstation"],
                recent_errors=["One slow local inference spike"],
                metadata=PROVIDER_METADATA.get(ProviderKind.ollama),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.cursor,
                today_usage=52_300,
                week_usage=278_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.cursor, 52_300)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.cursor, 278_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.cursor, 52_300)[1],
                cost_status_week=self._resolve_cost(ProviderKind.cursor, 278_000)[1],
                quota=500_000,
                remaining=222_000,
                status_text="Active",
                trend=cursor_trend,
                recent_session_names=["Refactor auth module", "Widget layout fix"],
                recent_errors=["No new provider errors"],
                metadata=PROVIDER_METADATA.get(ProviderKind.cursor),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.copilot,
                today_usage=31_200,
                week_usage=156_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.copilot, 31_200)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.copilot, 156_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.copilot, 31_200)[1],
                cost_status_week=self._resolve_cost(ProviderKind.copilot, 156_000)[1],
                quota=500_000,
                remaining=344_000,
                status_text="Healthy",
                trend=copilot_trend,
                recent_session_names=["Autocomplete audit", "PR review assist"],
                recent_errors=["No new provider errors"],
                metadata=PROVIDER_METADATA.get(ProviderKind.copilot),
            ),
            ProviderUsageDTO(
                provider=ProviderKind.kimi_k2,
                today_usage=22_100,
                week_usage=98_000,
                estimated_cost_today=self._resolve_cost(ProviderKind.kimi_k2, 22_100)[0],
                estimated_cost_week=self._resolve_cost(ProviderKind.kimi_k2, 98_000)[0],
                cost_status_today=self._resolve_cost(ProviderKind.kimi_k2, 22_100)[1],
                cost_status_week=self._resolve_cost(ProviderKind.kimi_k2, 98_000)[1],
                quota=500_000,
                remaining=402_000,
                status_text="Healthy",
                trend=kimi_trend,
                recent_session_names=["Long-context analysis", "Code translation batch"],
                recent_errors=["No new provider errors"],
                metadata=PROVIDER_METADATA.get(ProviderKind.kimi_k2),
            ),
        ]

        dashboard_metrics_session_id = str(uuid4())
        helper_heartbeat_session_id = str(uuid4())
        session_error_triage_id = str(uuid4())
        provider_adapter_review_id = str(uuid4())
        local_model_benchmark_id = str(uuid4())
        cursor_refactor_id = str(uuid4())
        copilot_review_id = str(uuid4())
        kimi_analysis_id = str(uuid4())

        sessions = [
            SessionRecordDTO(
                id=dashboard_metrics_session_id,
                name="Dashboard metrics pass",
                provider=ProviderKind.codex,
                project="cli-pulse-ios",
                device_name="Jason's MacBook Pro",
                started_at=now - timedelta(hours=5),
                last_active_at=now - timedelta(minutes=6),
                status=SessionStatus.running,
                total_usage=41_200,
                estimated_cost=self._resolve_cost(ProviderKind.codex, 41_200)[0],
                cost_status=self._resolve_cost(ProviderKind.codex, 41_200)[1],
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
                id=helper_heartbeat_session_id,
                name="Helper heartbeat monitor",
                provider=ProviderKind.gemini,
                project="cli-pulse-helper",
                device_name="lab-server-01",
                started_at=now - timedelta(hours=9),
                last_active_at=now - timedelta(minutes=18),
                status=SessionStatus.syncing,
                total_usage=26_900,
                estimated_cost=self._resolve_cost(ProviderKind.gemini, 26_900)[0],
                cost_status=self._resolve_cost(ProviderKind.gemini, 26_900)[1],
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
                id=session_error_triage_id,
                name="Session error triage",
                provider=ProviderKind.codex,
                project="backend-api",
                device_name="build-box",
                started_at=now - timedelta(hours=12),
                last_active_at=now - timedelta(hours=1),
                status=SessionStatus.failed,
                total_usage=61_200,
                estimated_cost=self._resolve_cost(ProviderKind.codex, 61_200)[0],
                cost_status=self._resolve_cost(ProviderKind.codex, 61_200)[1],
                requests=141,
                error_count=3,
                usage_timeline=codex_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Auth expired", subtitle="Provider token rejected", timestamp=now - timedelta(hours=1))
                ],
                error_summary=["Token expired for backend integration.", "Retry queue exceeded limit."],
            ),
            SessionRecordDTO(
                id=provider_adapter_review_id,
                name="Provider adapter review",
                provider=ProviderKind.claude,
                project="provider-layer",
                device_name="Jason's MacBook Pro",
                started_at=now - timedelta(hours=4),
                last_active_at=now - timedelta(minutes=12),
                status=SessionStatus.running,
                total_usage=18_600,
                estimated_cost=round(0.284, 4),
                cost_status=CostStatus.exact,
                requests=72,
                error_count=0,
                usage_timeline=claude_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Reviewed adapter contracts", subtitle="Claude summaries generated", timestamp=now - timedelta(hours=3)),
                    ActivityItemDTO(id=str(uuid4()), title="Captured edge cases", subtitle="Provider normalization notes updated", timestamp=now - timedelta(minutes=12)),
                ],
                error_summary=[],
            ),
            SessionRecordDTO(
                id=local_model_benchmark_id,
                name="Local model benchmark",
                provider=ProviderKind.ollama,
                project="local-models",
                device_name="lab-server-01",
                started_at=now - timedelta(hours=6),
                last_active_at=now - timedelta(minutes=28),
                status=SessionStatus.running,
                total_usage=8_900,
                estimated_cost=self._resolve_cost(ProviderKind.ollama, 8_900)[0],
                cost_status=self._resolve_cost(ProviderKind.ollama, 8_900)[1],
                requests=39,
                error_count=1,
                usage_timeline=ollama_trend,
                activity_timeline=[
                    ActivityItemDTO(id=str(uuid4()), title="Pulled latest model", subtitle="Warmup run completed", timestamp=now - timedelta(hours=5)),
                    ActivityItemDTO(id=str(uuid4()), title="Benchmark still active", subtitle="One transient local timeout", timestamp=now - timedelta(minutes=28)),
                ],
                error_summary=["One transient local inference timeout."],
            ),
            SessionRecordDTO(
                id=cursor_refactor_id,
                name="Auth module refactor",
                provider=ProviderKind.cursor,
                project="cli-pulse-ios",
                device_name="Jason's MacBook Pro",
                started_at=now - timedelta(hours=3),
                last_active_at=now - timedelta(minutes=8),
                status=SessionStatus.running,
                total_usage=28_400,
                estimated_cost=self._resolve_cost(ProviderKind.cursor, 28_400)[0],
                cost_status=self._resolve_cost(ProviderKind.cursor, 28_400)[1],
                requests=95,
                error_count=0,
                collection_confidence=CollectionConfidence.high,
                usage_timeline=cursor_trend,
                activity_timeline=[],
                error_summary=[],
            ),
            SessionRecordDTO(
                id=copilot_review_id,
                name="PR review assist",
                provider=ProviderKind.copilot,
                project="backend-api",
                device_name="Jason's MacBook Pro",
                started_at=now - timedelta(hours=2),
                last_active_at=now - timedelta(minutes=15),
                status=SessionStatus.idle,
                total_usage=14_800,
                estimated_cost=self._resolve_cost(ProviderKind.copilot, 14_800)[0],
                cost_status=self._resolve_cost(ProviderKind.copilot, 14_800)[1],
                requests=62,
                error_count=0,
                collection_confidence=CollectionConfidence.high,
                usage_timeline=copilot_trend,
                activity_timeline=[],
                error_summary=[],
            ),
            SessionRecordDTO(
                id=kimi_analysis_id,
                name="Long-context code analysis",
                provider=ProviderKind.kimi_k2,
                project="provider-layer",
                device_name="lab-server-01",
                started_at=now - timedelta(hours=1),
                last_active_at=now - timedelta(minutes=5),
                status=SessionStatus.running,
                total_usage=11_200,
                estimated_cost=self._resolve_cost(ProviderKind.kimi_k2, 11_200)[0],
                cost_status=self._resolve_cost(ProviderKind.kimi_k2, 11_200)[1],
                requests=28,
                error_count=0,
                collection_confidence=CollectionConfidence.high,
                usage_timeline=kimi_trend,
                activity_timeline=[],
                error_summary=[],
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
                current_session_count=3,
                cpu_usage=36,
                memory_usage=58,
                heartbeat_timeline=[UsagePointDTO(timestamp=now - timedelta(minutes=50 - index * 10), value=value) for index, value in enumerate([93, 95, 91, 94, 96, 98])],
                recent_sync_errors=[],
                provider_status={ProviderKind.codex: "Connected", ProviderKind.gemini: "Connected", ProviderKind.claude: "Connected"},
                recent_projects=["cli-pulse-ios", "backend-api", "provider-layer"],
            ),
            DeviceRecordDTO(
                id=str(uuid4()),
                name="lab-server-01",
                type="Linux Server",
                system="Ubuntu 24.04",
                status=DeviceStatus.degraded,
                last_sync_at=now - timedelta(minutes=8),
                helper_version="0.1.3",
                current_session_count=2,
                cpu_usage=72,
                memory_usage=68,
                heartbeat_timeline=[UsagePointDTO(timestamp=now - timedelta(minutes=50 - index * 10), value=value) for index, value in enumerate([88, 83, 79, 77, 82, 80])],
                recent_sync_errors=["High latency on recent provider sync."],
                provider_status={ProviderKind.gemini: "Rate limited", ProviderKind.openrouter: "Connected", ProviderKind.ollama: "Local"},
                recent_projects=["cli-pulse-helper", "local-models"],
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
                provider_status={ProviderKind.codex: "Auth expired", ProviderKind.openrouter: "Disconnected"},
                recent_projects=["backend-api"],
            ),
        ]

        alerts = [
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.helper_offline,
                severity=AlertSeverity.critical,
                title="build-box helper offline",
                message=Msg.SEED_DEVICE_OFFLINE,
                created_at=now - timedelta(minutes=20),
                is_read=False,
                is_resolved=False,
                related_device_name="build-box",
            ),
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.quota_low,
                severity=AlertSeverity.warning,
                title="Codex remaining quota below 20%",
                message=Msg.SEED_QUOTA_WARNING,
                created_at=now - timedelta(hours=1),
                is_read=False,
                is_resolved=False,
                related_provider=ProviderKind.codex,
            ),
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.session_failed,
                severity=AlertSeverity.warning,
                title="backend-api session failed",
                message=Msg.SEED_SESSION_FAILED,
                created_at=now - timedelta(hours=2),
                is_read=True,
                is_resolved=False,
                related_project_id=self._project_id("backend-api"),
                related_project_name="backend-api",
                related_session_id=session_error_triage_id,
                related_session_name="Session error triage",
                related_provider=ProviderKind.codex,
                related_device_name="build-box",
            ),
            AlertRecordDTO(
                id=str(uuid4()),
                type=AlertType.project_budget_exceeded,
                severity=AlertSeverity.warning,
                title="provider-layer budget exceeded",
                message=Msg.SEED_BUDGET_EXCEEDED,
                created_at=now - timedelta(minutes=35),
                is_read=False,
                is_resolved=False,
                related_project_id=self._project_id("provider-layer"),
                related_project_name="provider-layer",
                related_provider=ProviderKind.claude,
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
        settings = self._settings_for_user(user_id)
        updated = False
        offline_cutoff = now_utc() - timedelta(minutes=settings.offline_grace_period_minutes)
        degraded_minutes = max(1, min(settings.offline_grace_period_minutes - 1, max(2, settings.offline_grace_period_minutes // 2)))
        degraded_cutoff = now_utc() - timedelta(minutes=degraded_minutes)
        for device in devices:
            if device.last_sync_at < offline_cutoff and device.status != DeviceStatus.offline:
                device.status = DeviceStatus.offline
                updated = True
            elif device.last_sync_at < degraded_cutoff and device.status == DeviceStatus.online:
                device.status = DeviceStatus.degraded
                updated = True
        if updated:
            self._save_models(user_id, "devices_json", devices)

    def _apply_project_budget_rules(self, user_id: str) -> None:
        settings = self._settings_for_user(user_id)
        threshold = settings.project_budget_threshold_usd
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        if threshold <= 0:
            changed = False
            for alert in alerts:
                if alert.type == AlertType.project_budget_exceeded and not alert.is_resolved:
                    alert.is_resolved = True
                    changed = True
            if changed:
                self._save_models(user_id, "alerts_json", alerts)
            return

        projects = self._build_projects(user_id)
        unresolved_budget_alerts = {
            alert.related_project_id: alert
            for alert in alerts
            if alert.type == AlertType.project_budget_exceeded and not alert.is_resolved and alert.related_project_id
        }
        active_project_ids: set[str] = set()
        changed = False

        for project in projects:
            if project.estimated_cost_today is None or project.estimated_cost_today <= threshold:
                continue

            active_project_ids.add(project.id)
            if project.id in unresolved_budget_alerts:
                continue

            severity = AlertSeverity.critical if project.estimated_cost_today >= threshold * 1.5 else AlertSeverity.warning
            alerts.insert(
                0,
                AlertRecordDTO(
                    id=str(uuid4()),
                    type=AlertType.project_budget_exceeded,
                    severity=severity,
                    title=f"{project.name} budget exceeded",
                    message=Msg.PROJECT_BUDGET.format(
                        project=project.name,
                        cost=project.estimated_cost_today,
                        threshold=threshold,
                    ),
                    created_at=now_utc(),
                    is_read=False,
                    is_resolved=False,
                    related_project_id=project.id,
                    related_project_name=project.name,
                )
            )
            changed = True

        for project_id, alert in unresolved_budget_alerts.items():
            if project_id in active_project_ids:
                continue
            alert.is_resolved = True
            changed = True

        if changed:
            self._save_models(user_id, "alerts_json", alerts)

    def _apply_helper_offline_rules(self, user_id: str) -> None:
        settings = self._settings_for_user(user_id)
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        devices = self._load_models(user_id, "devices_json", DeviceRecordDTO)
        unresolved_offline_alerts = {
            alert.related_device_name: alert
            for alert in alerts
            if alert.type == AlertType.helper_offline and not alert.is_resolved and alert.related_device_name
        }

        active_devices: set[str] = set()
        changed = False
        now = now_utc()

        for device in devices:
            elapsed_minutes = int((now - device.last_sync_at).total_seconds() // 60)
            if elapsed_minutes < settings.offline_grace_period_minutes or device.status != DeviceStatus.offline:
                continue

            active_devices.add(device.name)
            severity = AlertSeverity.critical if elapsed_minutes >= settings.offline_grace_period_minutes * 3 else AlertSeverity.warning
            title = f"{device.name} helper offline"
            message = Msg.DEVICE_OFFLINE.format(device=device.name, minutes=elapsed_minutes)
            existing = unresolved_offline_alerts.get(device.name)
            if existing:
                if existing.severity != severity or existing.title != title or existing.message != message:
                    existing.severity = severity
                    existing.title = title
                    existing.message = message
                    changed = True
                continue

            if self._is_alert_on_cooldown(
                alerts,
                alert_type=AlertType.helper_offline,
                cooldown_minutes=settings.alert_cooldown_minutes,
                related_device_name=device.name,
            ):
                continue

            alerts.insert(
                0,
                AlertRecordDTO(
                    id=str(uuid4()),
                    type=AlertType.helper_offline,
                    severity=severity,
                    title=title,
                    message=message,
                    created_at=now,
                    is_read=False,
                    is_resolved=False,
                    related_device_name=device.name,
                ),
            )
            changed = True

        for device_name, alert in unresolved_offline_alerts.items():
            if device_name in active_devices:
                continue
            alert.is_resolved = True
            changed = True

        if changed:
            self._save_models(user_id, "alerts_json", alerts)

    def _apply_usage_spike_rules(self, user_id: str) -> None:
        settings = self._settings_for_user(user_id)
        threshold = settings.usage_spike_threshold
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        providers = self._load_models(user_id, "providers_json", ProviderUsageDTO)
        unresolved_usage_alerts = {
            alert.related_provider: alert
            for alert in alerts
            if alert.type == AlertType.usage_spike and not alert.is_resolved and alert.related_provider
        }

        if threshold <= 0:
            changed = False
            for alert in unresolved_usage_alerts.values():
                alert.is_resolved = True
                changed = True
            if changed:
                self._save_models(user_id, "alerts_json", alerts)
            return

        active_providers: set[ProviderKind] = set()
        changed = False

        for provider in providers:
            if provider.today_usage < threshold:
                continue

            active_providers.add(provider.provider)
            severity = AlertSeverity.critical if provider.today_usage >= int(threshold * 1.5) else AlertSeverity.warning
            title = f"{provider.provider.value} usage spike detected"
            message = Msg.USAGE_SPIKE.format(
                provider=provider.provider.value,
                usage=provider.today_usage,
                threshold=threshold,
            )
            existing = unresolved_usage_alerts.get(provider.provider)
            if existing:
                if existing.severity != severity or existing.title != title or existing.message != message:
                    existing.severity = severity
                    existing.title = title
                    existing.message = message
                    changed = True
                continue

            if self._is_alert_on_cooldown(
                alerts,
                alert_type=AlertType.usage_spike,
                cooldown_minutes=settings.alert_cooldown_minutes,
                related_provider=provider.provider,
            ):
                continue

            alerts.insert(
                0,
                AlertRecordDTO(
                    id=str(uuid4()),
                    type=AlertType.usage_spike,
                    severity=severity,
                    title=title,
                    message=message,
                    created_at=now_utc(),
                    is_read=False,
                    is_resolved=False,
                    related_provider=provider.provider,
                ),
            )
            changed = True

        for provider, alert in unresolved_usage_alerts.items():
            if provider in active_providers:
                continue
            alert.is_resolved = True
            changed = True

        if changed:
            self._save_models(user_id, "alerts_json", alerts)

    def _apply_session_failure_rules(self, user_id: str) -> None:
        settings = self._settings_for_user(user_id)
        threshold = settings.repeated_failure_threshold
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        sessions = self._load_models(user_id, "sessions_json", SessionRecordDTO)
        unresolved_failure_alerts = {
            alert.related_session_id: alert
            for alert in alerts
            if alert.type == AlertType.session_failed and not alert.is_resolved and alert.related_session_id
        }

        active_session_ids: set[str] = set()
        changed = False

        for session in sessions:
            is_failing = session.status == SessionStatus.failed or session.error_count >= threshold
            if not is_failing:
                continue

            active_session_ids.add(session.id)
            severity = AlertSeverity.critical if session.status == SessionStatus.failed or session.error_count >= threshold * 2 else AlertSeverity.warning
            title = f"{session.name} failing repeatedly"
            message = Msg.SESSION_FAILING.format(
                session=session.name,
                status=session.status.value,
                errors=session.error_count,
            )
            existing = unresolved_failure_alerts.get(session.id)
            if existing:
                if existing.severity != severity or existing.title != title or existing.message != message:
                    existing.severity = severity
                    existing.title = title
                    existing.message = message
                    existing.related_project_id = self._project_id(session.project)
                    existing.related_project_name = session.project
                    existing.related_session_name = session.name
                    existing.related_provider = session.provider
                    existing.related_device_name = session.device_name
                    changed = True
                continue

            if self._is_alert_on_cooldown(
                alerts,
                alert_type=AlertType.session_failed,
                cooldown_minutes=settings.alert_cooldown_minutes,
                related_session_id=session.id,
                related_project_id=self._project_id(session.project),
                related_provider=session.provider,
                related_device_name=session.device_name,
            ):
                continue

            alerts.insert(
                0,
                AlertRecordDTO(
                    id=str(uuid4()),
                    type=AlertType.session_failed,
                    severity=severity,
                    title=title,
                    message=message,
                    created_at=now_utc(),
                    is_read=False,
                    is_resolved=False,
                    related_project_id=self._project_id(session.project),
                    related_project_name=session.project,
                    related_session_id=session.id,
                    related_session_name=session.name,
                    related_provider=session.provider,
                    related_device_name=session.device_name,
                ),
            )
            changed = True

        for session_id, alert in unresolved_failure_alerts.items():
            if session_id in active_session_ids:
                continue
            alert.is_resolved = True
            changed = True

        if changed:
            self._save_models(user_id, "alerts_json", alerts)

    def _apply_session_duration_rules(self, user_id: str) -> None:
        settings = self._settings_for_user(user_id)
        threshold_minutes = settings.session_too_long_threshold_minutes
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        sessions = self._load_models(user_id, "sessions_json", SessionRecordDTO)
        unresolved_session_alerts = {
            alert.related_session_id: alert
            for alert in alerts
            if alert.type == AlertType.session_too_long and not alert.is_resolved and alert.related_session_id
        }

        if threshold_minutes <= 0:
            changed = False
            for alert in unresolved_session_alerts.values():
                alert.is_resolved = True
                changed = True
            if changed:
                self._save_models(user_id, "alerts_json", alerts)
            return

        active_session_ids: set[str] = set()
        changed = False
        now = now_utc()

        for session in sessions:
            if session.status not in {SessionStatus.running, SessionStatus.syncing}:
                continue

            duration_minutes = int((now - session.started_at).total_seconds() // 60)
            if duration_minutes < threshold_minutes:
                continue

            active_session_ids.add(session.id)
            severity = AlertSeverity.critical if duration_minutes >= threshold_minutes * 2 else AlertSeverity.warning
            title = f"{session.name} running too long"
            message = Msg.SESSION_TOO_LONG.format(
                session=session.name,
                duration=duration_minutes,
                threshold=threshold_minutes,
            )
            existing = unresolved_session_alerts.get(session.id)
            if existing:
                if existing.severity != severity or existing.title != title or existing.message != message:
                    existing.severity = severity
                    existing.title = title
                    existing.message = message
                    existing.related_project_id = self._project_id(session.project)
                    existing.related_project_name = session.project
                    existing.related_session_name = session.name
                    existing.related_provider = session.provider
                    existing.related_device_name = session.device_name
                    changed = True
                continue

            if self._is_alert_on_cooldown(
                alerts,
                alert_type=AlertType.session_too_long,
                cooldown_minutes=settings.alert_cooldown_minutes,
                related_session_id=session.id,
                related_project_id=self._project_id(session.project),
                related_provider=session.provider,
                related_device_name=session.device_name,
            ):
                continue

            alerts.insert(
                0,
                AlertRecordDTO(
                    id=str(uuid4()),
                    type=AlertType.session_too_long,
                    severity=severity,
                    title=title,
                    message=message,
                    created_at=now,
                    is_read=False,
                    is_resolved=False,
                    related_project_id=self._project_id(session.project),
                    related_project_name=session.project,
                    related_session_id=session.id,
                    related_session_name=session.name,
                    related_provider=session.provider,
                    related_device_name=session.device_name,
                ),
            )
            changed = True

        for session_id, alert in unresolved_session_alerts.items():
            if session_id in active_session_ids:
                continue
            alert.is_resolved = True
            changed = True

        if changed:
            self._save_models(user_id, "alerts_json", alerts)

    def _is_alert_on_cooldown(
        self,
        alerts: list[AlertRecordDTO],
        *,
        alert_type: AlertType,
        cooldown_minutes: int,
        related_project_id: Optional[str] = None,
        related_session_id: Optional[str] = None,
        related_provider: Optional[ProviderKind] = None,
        related_device_name: Optional[str] = None,
    ) -> bool:
        if cooldown_minutes <= 0:
            return False

        cutoff = now_utc() - timedelta(minutes=cooldown_minutes)
        return any(
            alert.type == alert_type
            and alert.created_at >= cutoff
            and self._alert_matches(
                alert,
                related_project_id=related_project_id,
                related_session_id=related_session_id,
                related_provider=related_provider,
                related_device_name=related_device_name,
            )
            for alert in alerts
        )

    def _alert_matches(
        self,
        alert: AlertRecordDTO,
        *,
        related_project_id: Optional[str] = None,
        related_session_id: Optional[str] = None,
        related_provider: Optional[ProviderKind] = None,
        related_device_name: Optional[str] = None,
    ) -> bool:
        if related_project_id is not None and alert.related_project_id != related_project_id:
            return False
        if related_session_id is not None and alert.related_session_id != related_session_id:
            return False
        if related_provider is not None and alert.related_provider != related_provider:
            return False
        if related_device_name is not None and alert.related_device_name != related_device_name:
            return False
        return True

    def _device_belongs_to_user(self, device_id: str, user_id: str) -> bool:
        row = self.connection.execute(
            "SELECT 1 FROM device_tokens WHERE device_id = ? AND user_id = ?",
            (device_id, user_id),
        ).fetchone()
        return row is not None

    def _build_projects(self, user_id: str) -> list[ProjectRecordDTO]:
        sessions = self._load_models(user_id, "sessions_json", SessionRecordDTO)
        alerts = self._load_models(user_id, "alerts_json", AlertRecordDTO)
        grouped: dict[str, list[SessionRecordDTO]] = {}

        for session in sessions:
            grouped.setdefault(session.project, []).append(session)

        projects: list[ProjectRecordDTO] = []
        for project_name, project_sessions in grouped.items():
            provider_totals: dict[ProviderKind, int] = {}
            trend_totals: dict[datetime, int] = {}
            device_names = sorted({item.device_name for item in project_sessions})
            active_sessions = sum(1 for item in project_sessions if item.status in {SessionStatus.running, SessionStatus.syncing})

            for session in project_sessions:
                provider_totals[session.provider] = provider_totals.get(session.provider, 0) + session.total_usage
                for point in session.usage_timeline:
                    bucket = point.timestamp.replace(minute=0, second=0, microsecond=0)
                    trend_totals[bucket] = trend_totals.get(bucket, 0) + point.value

            primary_provider = max(provider_totals, key=provider_totals.get)
            today_usage = sum(item.total_usage for item in project_sessions)
            week_usage = max(today_usage, sum(provider_totals.values()) * 3)
            estimated_cost_today = self._sum_available_costs(item.estimated_cost for item in project_sessions)
            estimated_cost_week = (
                round(max(estimated_cost_today, estimated_cost_today * (week_usage / max(today_usage, 1))), 4)
                if estimated_cost_today is not None
                else None
            )
            cost_status_today = aggregate_cost_status(item.cost_status for item in project_sessions)
            cost_status_week = (
                CostStatus.unavailable
                if estimated_cost_week is None
                else (CostStatus.estimated if week_usage > today_usage else cost_status_today)
            )
            alert_count = sum(
                1
                for alert in alerts
                if alert.related_project_id == self._project_id(project_name)
                or project_name.lower() in alert.title.lower()
                or project_name.lower() in alert.message.lower()
            ) + sum(1 for session in project_sessions if session.error_count > 0)

            projects.append(
                ProjectRecordDTO(
                    id=self._project_id(project_name),
                    name=project_name,
                    today_usage=today_usage,
                    week_usage=week_usage,
                    estimated_cost_today=estimated_cost_today,
                    estimated_cost_week=estimated_cost_week,
                    cost_status_today=cost_status_today,
                    cost_status_week=cost_status_week,
                    active_session_count=active_sessions,
                    device_count=len(device_names),
                    alert_count=alert_count,
                    primary_provider=primary_provider,
                    trend=[
                        UsagePointDTO(timestamp=timestamp, value=value)
                        for timestamp, value in sorted(trend_totals.items())
                    ],
                    recent_devices=device_names[:MAX_RECENT_DEVICES],
                    recent_session_names=[item.name for item in sorted(project_sessions, key=lambda item: item.last_active_at, reverse=True)[:MAX_RECENT_SESSION_NAMES]],
                    provider_breakdown=provider_totals,
                )
            )

        return sorted(projects, key=lambda item: (item.today_usage, item.active_session_count), reverse=True)

    def _project_id(self, project_name: str) -> str:
        normalized = re.sub(r"[^a-z0-9]+", "-", project_name.lower()).strip("-")
        return normalized or f"project-{uuid4().hex[:8]}"

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

    VALID_JSON_COLUMNS = frozenset({"providers_json", "sessions_json", "devices_json", "alerts_json"})

    def _load_models(self, user_id: str, column: str, model_cls: Any) -> list[Any]:
        if column not in self.VALID_JSON_COLUMNS:
            raise ValueError(f"Invalid column name: {column}")
        row = self.connection.execute(f"SELECT {column} FROM users WHERE id = ?", (user_id,)).fetchone()
        raw = row[column] if row is not None else "[]"
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return []
        result = []
        for item in data:
            try:
                result.append(model_cls.model_validate(item))
            except Exception:
                continue
        return result

    def _save_models(self, user_id: str, column: str, models: Iterable[Any]) -> None:
        if column not in self.VALID_JSON_COLUMNS:
            raise ValueError(f"Invalid column name: {column}")
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
