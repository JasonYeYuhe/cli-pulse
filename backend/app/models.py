from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional

from pydantic import BaseModel, Field


class ProviderKind(str, Enum):
    codex = "Codex"
    gemini = "Gemini"
    claude = "Claude"
    openrouter = "OpenRouter"
    ollama = "Ollama"


class SessionStatus(str, Enum):
    running = "Running"
    idle = "Idle"
    failed = "Failed"
    syncing = "Syncing"


class DeviceStatus(str, Enum):
    online = "Online"
    degraded = "Degraded"
    offline = "Offline"


class AlertType(str, Enum):
    quota_low = "Quota Low"
    usage_spike = "Usage Spike"
    helper_offline = "Helper Offline"
    sync_failed = "Sync Failed"
    auth_expired = "Auth Expired"
    session_failed = "Session Failed"
    session_too_long = "Session Too Long"
    project_budget_exceeded = "Project Budget Exceeded"


class AlertSeverity(str, Enum):
    critical = "Critical"
    warning = "Warning"
    info = "Info"


class UserDTO(BaseModel):
    id: str
    name: str
    email: str


class PairingInfoDTO(BaseModel):
    code: str
    install_command: str


class UsagePointDTO(BaseModel):
    timestamp: datetime
    value: int


class ActivityItemDTO(BaseModel):
    id: str
    title: str
    subtitle: str
    timestamp: datetime


class ProviderUsageDTO(BaseModel):
    provider: ProviderKind
    today_usage: int
    week_usage: int
    quota: int
    remaining: int
    status_text: str
    trend: List[UsagePointDTO]
    recent_session_names: List[str]
    recent_errors: List[str]


class SessionRecordDTO(BaseModel):
    id: str
    name: str
    provider: ProviderKind
    project: str
    device_name: str
    started_at: datetime
    last_active_at: datetime
    status: SessionStatus
    total_usage: int
    requests: int
    error_count: int
    usage_timeline: List[UsagePointDTO]
    activity_timeline: List[ActivityItemDTO]
    error_summary: List[str]


class DeviceRecordDTO(BaseModel):
    id: str
    name: str
    type: str
    system: str
    status: DeviceStatus
    last_sync_at: datetime
    helper_version: str
    current_session_count: int
    cpu_usage: int
    memory_usage: int
    heartbeat_timeline: List[UsagePointDTO]
    recent_sync_errors: List[str]
    provider_status: Dict[ProviderKind, str]
    recent_projects: List[str]


class AlertRecordDTO(BaseModel):
    id: str
    type: AlertType
    severity: AlertSeverity
    title: str
    message: str
    created_at: datetime
    is_read: bool
    is_resolved: bool


class SettingsSnapshotDTO(BaseModel):
    notifications_enabled: bool
    usage_spike_threshold: int
    data_retention_days: int
    login_method: str


class DashboardSummaryDTO(BaseModel):
    total_usage: int
    total_requests: int
    active_sessions: int
    online_devices: int
    unresolved_alerts: int
    provider_breakdown: List[ProviderUsageDTO]
    trend: List[UsagePointDTO]
    recent_activity: List[ActivityItemDTO]
    risk_signals: List[str]


class AuthRequestDTO(BaseModel):
    email: str
    password: str
    name: Optional[str] = None


class AuthResponseDTO(BaseModel):
    access_token: str
    user: UserDTO
    paired: bool


class AlertActionResponseDTO(BaseModel):
    alerts: List[AlertRecordDTO]


class SettingsUpdateDTO(BaseModel):
    notifications_enabled: bool
    usage_spike_threshold: int
    data_retention_days: int


class HelperRegisterRequestDTO(BaseModel):
    pairing_code: str
    device_name: str
    device_type: str
    system: str
    helper_version: str


class HelperRegisterResponseDTO(BaseModel):
    device_id: str
    access_token: str


class HelperHeartbeatRequestDTO(BaseModel):
    device_id: str
    cpu_usage: int = Field(ge=0, le=100)
    memory_usage: int = Field(ge=0, le=100)
    active_session_count: int = Field(ge=0)


class HelperSessionSyncDTO(BaseModel):
    id: str
    name: str
    provider: ProviderKind
    project: str
    status: SessionStatus
    total_usage: int
    requests: int
    error_count: int
    started_at: datetime
    last_active_at: datetime


class HelperAlertSyncDTO(BaseModel):
    id: str
    type: AlertType
    severity: AlertSeverity
    title: str
    message: str
    created_at: datetime


class HelperSyncRequestDTO(BaseModel):
    device_id: str
    sessions: List[HelperSessionSyncDTO]
    alerts: List[HelperAlertSyncDTO] = []
    provider_remaining: Dict[ProviderKind, int] = {}


class SuccessDTO(BaseModel):
    success: bool = True
