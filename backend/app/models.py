from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional

from pydantic import BaseModel, Field


class SubscriptionTier(str, Enum):
    free = "free"
    pro = "pro"
    team = "team"


class ProviderKind(str, Enum):
    codex = "Codex"
    gemini = "Gemini"
    claude = "Claude"
    cursor = "Cursor"
    opencode = "OpenCode"
    droid = "Droid"
    antigravity = "Antigravity"
    copilot = "Copilot"
    zai = "z.ai"
    minimax = "MiniMax"
    augment = "Augment"
    jetbrains_ai = "JetBrains AI"
    kimi_k2 = "Kimi K2"
    amp = "Amp"
    synthetic = "Synthetic"
    warp = "Warp"
    kilo = "Kilo"
    ollama = "Ollama"
    openrouter = "OpenRouter"
    alibaba = "Alibaba"


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


class PushPolicy(str, Enum):
    all = "All Alerts"
    warnings_and_critical = "Warnings + Critical"
    critical_only = "Critical Only"


class CollectionConfidence(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"


class CostStatus(str, Enum):
    exact = "Exact"
    estimated = "Estimated"
    unavailable = "Unavailable"


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


class ProviderMetadataDTO(BaseModel):
    display_name: str
    category: str = "cloud"  # cloud, local, aggregator, ide
    supports_exact_cost: bool = False
    supports_quota: bool = True
    default_quota: Optional[int] = None
    api_base_url: Optional[str] = None


class ProviderUsageDTO(BaseModel):
    provider: ProviderKind
    today_usage: int
    week_usage: int
    estimated_cost_today: Optional[float] = None
    estimated_cost_week: Optional[float] = None
    cost_status_today: CostStatus = CostStatus.estimated
    cost_status_week: CostStatus = CostStatus.estimated
    quota: int
    remaining: int
    status_text: str
    trend: List[UsagePointDTO]
    recent_session_names: List[str]
    recent_errors: List[str]
    metadata: Optional[ProviderMetadataDTO] = None


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
    estimated_cost: Optional[float] = None
    cost_status: CostStatus = CostStatus.estimated
    requests: int
    error_count: int
    collection_confidence: CollectionConfidence = CollectionConfidence.medium
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
    acknowledged_at: Optional[datetime] = None
    snoozed_until: Optional[datetime] = None
    related_project_id: Optional[str] = None
    related_project_name: Optional[str] = None
    related_session_id: Optional[str] = None
    related_session_name: Optional[str] = None
    related_provider: Optional[ProviderKind] = None
    related_device_name: Optional[str] = None


class AlertTypeSummaryDTO(BaseModel):
    type: AlertType
    count: int


class AlertSummaryDTO(BaseModel):
    unread_count: int
    open_count: int
    resolved_count: int
    critical_open_count: int
    warning_open_count: int
    info_open_count: int
    type_breakdown: List[AlertTypeSummaryDTO]


class SettingsSnapshotDTO(BaseModel):
    notifications_enabled: bool
    push_policy: PushPolicy = PushPolicy.warnings_and_critical
    digest_notifications_enabled: bool = True
    digest_interval_minutes: int = Field(default=15, ge=5, le=180)
    usage_spike_threshold: int
    project_budget_threshold_usd: float = Field(default=0.25, ge=0)
    session_too_long_threshold_minutes: int = Field(default=180, ge=30)
    offline_grace_period_minutes: int = Field(default=5, ge=1)
    repeated_failure_threshold: int = Field(default=3, ge=1)
    alert_cooldown_minutes: int = Field(default=30, ge=0)
    data_retention_days: int
    login_method: str


class DashboardSummaryDTO(BaseModel):
    total_usage: int
    total_estimated_cost: Optional[float] = None
    cost_status: CostStatus = CostStatus.estimated
    total_requests: int
    active_sessions: int
    online_devices: int
    unresolved_alerts: int
    provider_breakdown: List[ProviderUsageDTO]
    top_projects: List["ProjectRecordDTO"]
    trend: List[UsagePointDTO]
    recent_activity: List[ActivityItemDTO]
    risk_signals: List[str]
    alert_summary: AlertSummaryDTO


class ProjectRecordDTO(BaseModel):
    id: str
    name: str
    today_usage: int
    week_usage: int
    estimated_cost_today: Optional[float] = None
    estimated_cost_week: Optional[float] = None
    cost_status_today: CostStatus = CostStatus.estimated
    cost_status_week: CostStatus = CostStatus.estimated
    active_session_count: int
    device_count: int
    alert_count: int
    primary_provider: ProviderKind
    trend: List[UsagePointDTO]
    recent_devices: List[str]
    recent_session_names: List[str]
    provider_breakdown: Dict[ProviderKind, int]


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


class AlertSnoozeRequestDTO(BaseModel):
    minutes: int = Field(ge=5, le=1440)


class SettingsUpdateDTO(BaseModel):
    notifications_enabled: bool
    push_policy: PushPolicy
    digest_notifications_enabled: bool
    digest_interval_minutes: int = Field(ge=5, le=180)
    usage_spike_threshold: int
    project_budget_threshold_usd: float = Field(ge=0)
    session_too_long_threshold_minutes: int = Field(ge=30)
    offline_grace_period_minutes: int = Field(ge=1)
    repeated_failure_threshold: int = Field(ge=1)
    alert_cooldown_minutes: int = Field(ge=0)
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
    exact_cost: Optional[float] = Field(default=None, ge=0)
    requests: int
    error_count: int
    collection_confidence: CollectionConfidence = CollectionConfidence.medium
    started_at: datetime
    last_active_at: datetime


class HelperAlertSyncDTO(BaseModel):
    id: str
    type: AlertType
    severity: AlertSeverity
    title: str
    message: str
    created_at: datetime
    related_project_id: Optional[str] = None
    related_project_name: Optional[str] = None
    related_session_id: Optional[str] = None
    related_session_name: Optional[str] = None
    related_provider: Optional[ProviderKind] = None
    related_device_name: Optional[str] = None


class HelperSyncRequestDTO(BaseModel):
    device_id: str
    sessions: List[HelperSessionSyncDTO]
    alerts: List[HelperAlertSyncDTO] = []
    provider_remaining: Dict[ProviderKind, int] = {}


class SubscriptionDTO(BaseModel):
    tier: SubscriptionTier
    status: str  # active, trialing, past_due, canceled
    current_period_start: Optional[datetime] = None
    current_period_end: Optional[datetime] = None
    trial_end: Optional[datetime] = None
    cancel_at_period_end: bool = False
    apple_transaction_id: Optional[str] = None
    apple_original_transaction_id: Optional[str] = None
    apple_product_id: Optional[str] = None


class TeamDTO(BaseModel):
    id: str
    name: str
    owner_id: str
    member_count: int
    max_members: int
    created_at: datetime


class TeamMemberDTO(BaseModel):
    user_id: str
    name: str
    email: str
    role: str  # owner, admin, member
    joined_at: datetime


class TeamInviteDTO(BaseModel):
    id: str
    email: str
    role: str
    created_at: datetime
    expires_at: datetime


class TierLimitsDTO(BaseModel):
    max_providers: int  # -1 = unlimited
    max_devices: int
    data_retention_days: int
    alert_rule_types: List[str]
    cost_tracking_range: str  # "today", "30d", "full"
    has_project_budgets: bool
    has_api_access: bool
    max_team_members: int
    export_formats: List[str]


class CostRuleDTO(BaseModel):
    id: str
    provider: ProviderKind
    model: str = "*"  # "*" = default for provider, or specific model name
    input_rate_per_1k: Optional[float] = None  # $/1K input tokens
    output_rate_per_1k: Optional[float] = None  # $/1K output tokens
    blended_rate_per_1k: Optional[float] = None  # $/1K usage (when input/output split unknown)
    currency: str = "USD"
    source: str = "default"  # default, user, provider_api
    updated_at: Optional[datetime] = None


class CostRuleCreateDTO(BaseModel):
    provider: ProviderKind
    model: str = "*"
    input_rate_per_1k: Optional[float] = Field(default=None, ge=0)
    output_rate_per_1k: Optional[float] = Field(default=None, ge=0)
    blended_rate_per_1k: Optional[float] = Field(default=None, ge=0)


class ProviderCostBreakdownDTO(BaseModel):
    provider: ProviderKind
    today_usage: int
    week_usage: int
    today_cost: Optional[float] = None
    week_cost: Optional[float] = None
    cost_status: CostStatus = CostStatus.estimated
    model_breakdown: Dict[str, float] = {}  # model_name → cost


class ProjectCostBreakdownDTO(BaseModel):
    project_id: str
    project_name: str
    today_cost: Optional[float] = None
    week_cost: Optional[float] = None
    cost_status: CostStatus = CostStatus.estimated
    budget_threshold: Optional[float] = None
    budget_percent: Optional[float] = None  # cost / threshold * 100
    provider_breakdown: Dict[str, float] = {}  # provider_name → cost


class CostSummaryDTO(BaseModel):
    total_cost_today: Optional[float] = None
    total_cost_week: Optional[float] = None
    total_cost_month: Optional[float] = None
    cost_status: CostStatus = CostStatus.estimated
    currency: str = "USD"
    cost_tracking_range: str = "today"  # today, 30d, full (per tier)
    provider_breakdown: List[ProviderCostBreakdownDTO]
    project_breakdown: List[ProjectCostBreakdownDTO]
    daily_trend: List[UsagePointDTO]  # cost per day as value (cents)


class VerifyReceiptRequestDTO(BaseModel):
    receipt_data: str


class CreateTeamRequestDTO(BaseModel):
    name: str


class InviteTeamMemberRequestDTO(BaseModel):
    email: str
    role: str = "member"


class SuccessDTO(BaseModel):
    success: bool = True
