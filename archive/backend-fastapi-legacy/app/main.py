from __future__ import annotations

import os

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import HTMLResponse

from .models import (
    AlertActionResponseDTO,
    AlertRecordDTO,
    AlertRuleDTO,
    AlertRuleUpdateDTO,
    AlertSnoozeRequestDTO,
    AuthRequestDTO,
    AuthResponseDTO,
    CollectionConfidence,
    CostRuleCreateDTO,
    CostRuleDTO,
    CostSummaryDTO,
    CreateTeamRequestDTO,
    DashboardSummaryDTO,
    DeviceRecordDTO,
    HelperHeartbeatRequestDTO,
    HelperRegisterRequestDTO,
    HelperRegisterResponseDTO,
    HelperSyncRequestDTO,
    InviteTeamMemberRequestDTO,
    PairingInfoDTO,
    ProjectRecordDTO,
    ProviderMetadataDTO,
    ProviderUsageDTO,
    SessionRecordDTO,
    SettingsSnapshotDTO,
    SettingsUpdateDTO,
    SubscriptionDTO,
    SubscriptionTier,
    SuccessDTO,
    TeamDTO,
    TeamInviteDTO,
    TeamMemberDTO,
    TierLimitsDTO,
    VerifyReceiptRequestDTO,
)
from .store import SQLiteStore


def build_store() -> SQLiteStore:
    database_path = os.environ.get("CLI_PULSE_DB_PATH", "backend/data/cli_pulse.db")
    return SQLiteStore(database_path)


def create_app(store: SQLiteStore) -> FastAPI:
    app = FastAPI(title="CLI Pulse Backend", version="0.2.0")

    def bearer_token(authorization: str = Header(default="")) -> str:
        prefix = "Bearer "
        if not authorization.startswith(prefix):
            raise HTTPException(status_code=401, detail="Missing bearer token")
        return authorization[len(prefix) :]

    def current_token(token: str = Depends(bearer_token)) -> str:
        session = store.authenticate(token)
        if not session:
            raise HTTPException(status_code=401, detail="Invalid token")
        return token

    def current_token_or_helper(token: str = Depends(bearer_token)) -> str:
        """Accept either a user session token or a helper device token."""
        if store.authenticate(token) or store.authenticate_helper(token):
            return token
        raise HTTPException(status_code=401, detail="Invalid token")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/support", response_class=HTMLResponse)
    def support_page() -> str:
        return _SUPPORT_HTML

    @app.post("/v1/auth/sign-in", response_model=AuthResponseDTO)
    def sign_in(payload: AuthRequestDTO) -> AuthResponseDTO:
        state = store.login(payload.email, payload.password)
        if state is None:
            raise HTTPException(status_code=401, detail="Invalid email or password")
        return AuthResponseDTO(access_token=state.token, user=state.user, paired=state.paired)

    @app.post("/v1/auth/create-account", response_model=AuthResponseDTO)
    def create_account(payload: AuthRequestDTO) -> AuthResponseDTO:
        try:
            state = store.register(payload.email, payload.password, payload.name)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        if state is None:
            raise HTTPException(status_code=409, detail="Email already registered")
        return AuthResponseDTO(access_token=state.token, user=state.user, paired=state.paired)

    @app.get("/v1/auth/me", response_model=AuthResponseDTO)
    def me(token: str = Depends(current_token)) -> AuthResponseDTO:
        state = store.authenticate(token)
        if state is None:
            raise HTTPException(status_code=401, detail="Session expired")
        return AuthResponseDTO(access_token=state.token, user=state.user, paired=state.paired)

    @app.get("/v1/onboarding/pairing-code", response_model=PairingInfoDTO)
    def pairing_code(token: str = Depends(current_token)) -> PairingInfoDTO:
        return store.pairing_info(token)

    @app.post("/v1/onboarding/complete", response_model=SuccessDTO)
    def complete_pairing(token: str = Depends(current_token)) -> SuccessDTO:
        return store.complete_pairing(token)

    @app.get("/v1/dashboard/summary", response_model=DashboardSummaryDTO)
    def dashboard_summary(token: str = Depends(current_token)) -> DashboardSummaryDTO:
        return store.dashboard(token)

    @app.get("/v1/providers", response_model=list[ProviderUsageDTO])
    def providers(token: str = Depends(current_token)) -> list[ProviderUsageDTO]:
        return store.providers(token)

    @app.get("/v1/providers/{provider_name}", response_model=ProviderUsageDTO)
    def provider_detail(provider_name: str, token: str = Depends(current_token)) -> ProviderUsageDTO:
        provider = store.provider_detail(token, provider_name)
        if provider is None:
            raise HTTPException(status_code=404, detail="Provider not found")
        return provider

    @app.get("/v1/projects", response_model=list[ProjectRecordDTO])
    def projects(token: str = Depends(current_token)) -> list[ProjectRecordDTO]:
        return store.projects(token)

    @app.get("/v1/projects/{project_id}", response_model=ProjectRecordDTO)
    def project_detail(project_id: str, token: str = Depends(current_token)) -> ProjectRecordDTO:
        project = store.project_detail(token, project_id)
        if project is None:
            raise HTTPException(status_code=404, detail="Project not found")
        return project

    @app.get("/v1/sessions", response_model=list[SessionRecordDTO])
    def sessions(token: str = Depends(current_token)) -> list[SessionRecordDTO]:
        return store.sessions(token)

    @app.get("/v1/devices", response_model=list[DeviceRecordDTO])
    def devices(token: str = Depends(current_token)) -> list[DeviceRecordDTO]:
        return store.devices(token)

    @app.get("/v1/alerts", response_model=list[AlertRecordDTO])
    def alerts(token: str = Depends(current_token)) -> list[AlertRecordDTO]:
        return store.alerts(token)

    @app.post("/v1/alerts/{alert_id}/read", response_model=AlertActionResponseDTO)
    def mark_alert_read(alert_id: str, token: str = Depends(current_token)) -> AlertActionResponseDTO:
        return store.mark_alert(token, alert_id, resolve=False)

    @app.post("/v1/alerts/{alert_id}/resolve", response_model=AlertActionResponseDTO)
    def resolve_alert(alert_id: str, token: str = Depends(current_token)) -> AlertActionResponseDTO:
        return store.mark_alert(token, alert_id, resolve=True)

    @app.post("/v1/alerts/{alert_id}/ack", response_model=AlertActionResponseDTO)
    def acknowledge_alert(alert_id: str, token: str = Depends(current_token)) -> AlertActionResponseDTO:
        return store.acknowledge_alert(token, alert_id)

    @app.post("/v1/alerts/{alert_id}/snooze", response_model=AlertActionResponseDTO)
    def snooze_alert(
        alert_id: str,
        payload: AlertSnoozeRequestDTO,
        token: str = Depends(current_token),
    ) -> AlertActionResponseDTO:
        return store.snooze_alert(token, alert_id, payload.minutes)

    @app.get("/v1/settings", response_model=SettingsSnapshotDTO)
    def settings(token: str = Depends(current_token)) -> SettingsSnapshotDTO:
        return store.settings(token)

    @app.put("/v1/settings", response_model=SettingsSnapshotDTO)
    def update_settings(payload: SettingsUpdateDTO, token: str = Depends(current_token)) -> SettingsSnapshotDTO:
        return store.update_settings(token, payload)

    @app.delete("/v1/account", response_model=SuccessDTO)
    def delete_account(token: str = Depends(current_token)) -> SuccessDTO:
        return store.delete_account(token)

    # ── Subscription endpoints ──

    @app.get("/v1/subscription", response_model=SubscriptionDTO)
    def subscription(token: str = Depends(current_token)) -> SubscriptionDTO:
        return store.get_subscription(token)

    @app.post("/v1/subscription/verify", response_model=SubscriptionDTO)
    def verify_subscription(
        payload: VerifyReceiptRequestDTO, token: str = Depends(current_token)
    ) -> SubscriptionDTO:
        try:
            return store.verify_apple_receipt(token, payload.receipt_data)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error

    @app.get("/v1/subscription/limits", response_model=TierLimitsDTO)
    def subscription_limits(token: str = Depends(current_token)) -> TierLimitsDTO:
        return store.get_tier_limits(token)

    # ── Alert rules endpoints ──

    @app.get("/v1/alerts/rules", response_model=list[AlertRuleDTO])
    def alert_rules(token: str = Depends(current_token)) -> list[AlertRuleDTO]:
        return store.get_alert_rules(token)

    @app.put("/v1/alerts/rules", response_model=AlertRuleDTO)
    def update_alert_rule(
        payload: AlertRuleUpdateDTO, token: str = Depends(current_token)
    ) -> AlertRuleDTO:
        return store.update_alert_rule(token, payload)

    # ── Cost estimation endpoints ──

    @app.get("/v1/costs/summary", response_model=CostSummaryDTO)
    def cost_summary(token: str = Depends(current_token)) -> CostSummaryDTO:
        return store.cost_summary(token)

    @app.get("/v1/costs/rules", response_model=list[CostRuleDTO])
    def cost_rules(token: str = Depends(current_token)) -> list[CostRuleDTO]:
        return store.get_cost_rules(token)

    @app.put("/v1/costs/rules", response_model=CostRuleDTO)
    def upsert_cost_rule(
        payload: CostRuleCreateDTO, token: str = Depends(current_token)
    ) -> CostRuleDTO:
        return store.upsert_cost_rule(token, payload)

    @app.delete("/v1/costs/rules/{rule_id}", response_model=SuccessDTO)
    def delete_cost_rule(
        rule_id: str, token: str = Depends(current_token)
    ) -> SuccessDTO:
        return store.delete_cost_rule(token, rule_id)

    # ── Team management endpoints ──

    @app.post("/v1/team", response_model=TeamDTO)
    def create_team(
        payload: CreateTeamRequestDTO, token: str = Depends(current_token)
    ) -> TeamDTO:
        try:
            return store.create_team(token, payload.name)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.get("/v1/team", response_model=TeamDTO)
    def get_team(token: str = Depends(current_token)) -> TeamDTO:
        team = store.get_team(token)
        if team is None:
            raise HTTPException(status_code=404, detail="No team found")
        return team

    @app.get("/v1/team/members", response_model=list[TeamMemberDTO])
    def team_members(token: str = Depends(current_token)) -> list[TeamMemberDTO]:
        return store.get_team_members(token)

    @app.post("/v1/team/invite", response_model=TeamInviteDTO)
    def invite_team_member(
        payload: InviteTeamMemberRequestDTO, token: str = Depends(current_token)
    ) -> TeamInviteDTO:
        try:
            return store.invite_team_member(token, payload.email, payload.role)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.post("/v1/team/invite/{invite_id}/accept", response_model=TeamMemberDTO)
    def accept_team_invite(
        invite_id: str, token: str = Depends(current_token)
    ) -> TeamMemberDTO:
        try:
            return store.accept_team_invite(token, invite_id)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.delete("/v1/team/members/{user_id}", response_model=SuccessDTO)
    def remove_team_member(
        user_id: str, token: str = Depends(current_token)
    ) -> SuccessDTO:
        try:
            return store.remove_team_member(token, user_id)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.get("/v1/team/dashboard", response_model=DashboardSummaryDTO)
    def team_dashboard(token: str = Depends(current_token)) -> DashboardSummaryDTO:
        try:
            return store.get_team_dashboard(token)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.post("/v1/helper/register", response_model=HelperRegisterResponseDTO)
    def helper_register(payload: HelperRegisterRequestDTO) -> HelperRegisterResponseDTO:
        response = store.register_helper(payload)
        if response is None:
            raise HTTPException(status_code=404, detail="Invalid or expired pairing code")
        return response

    @app.post("/v1/helper/heartbeat", response_model=SuccessDTO)
    def helper_heartbeat(payload: HelperHeartbeatRequestDTO, token: str = Depends(current_token_or_helper)) -> SuccessDTO:
        try:
            return store.helper_heartbeat(token, payload)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.post("/v1/helper/sync", response_model=SuccessDTO)
    def helper_sync(payload: HelperSyncRequestDTO, token: str = Depends(current_token_or_helper)) -> SuccessDTO:
        try:
            return store.helper_sync(token, payload)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    return app


_SUPPORT_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CLI Pulse — Support</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
       background:#f5f5f7;color:#1d1d1f;line-height:1.6}
  .container{max-width:680px;margin:60px auto;padding:0 24px}
  h1{font-size:2rem;font-weight:700;margin-bottom:8px}
  .tagline{color:#86868b;font-size:1.1rem;margin-bottom:40px}
  h2{font-size:1.25rem;font-weight:600;margin:32px 0 12px}
  p,li{font-size:1rem;color:#424245}
  ul{padding-left:20px;margin-bottom:16px}
  li{margin-bottom:6px}
  a{color:#0066cc;text-decoration:none}
  a:hover{text-decoration:underline}
  .card{background:#fff;border-radius:12px;padding:24px;margin-bottom:20px;
        box-shadow:0 1px 3px rgba(0,0,0,.08)}
  .footer{text-align:center;color:#86868b;font-size:.85rem;margin-top:48px;padding-bottom:40px}
</style>
</head>
<body>
<div class="container">
  <h1>CLI Pulse</h1>
  <p class="tagline">Real-time monitoring for AI coding tools</p>

  <div class="card">
    <h2>About</h2>
    <p>CLI Pulse monitors your usage across Claude, Codex, Gemini, OpenRouter, Ollama,
       and 20+ AI coding providers in real-time. Track token usage, costs, sessions,
       and alerts across all your devices from a single dashboard.</p>
  </div>

  <div class="card">
    <h2>Getting Help</h2>
    <ul>
      <li>For bug reports and feature requests, email
          <a href="mailto:clipulse.support@gmail.com">clipulse.support@gmail.com</a></li>
      <li>Response time: within 48 hours on business days</li>
    </ul>
  </div>

  <div class="card">
    <h2>FAQ</h2>
    <p><strong>How does CLI Pulse collect data?</strong><br>
       A lightweight helper daemon runs on your Mac or server and detects AI tool processes.
       It periodically syncs usage snapshots to your private dashboard.</p>
    <p style="margin-top:12px"><strong>Is my data private?</strong><br>
       Yes. Each account's data is isolated. We do not share or sell usage data.</p>
    <p style="margin-top:12px"><strong>Which platforms are supported?</strong><br>
       iOS, macOS, watchOS, and Home Screen widgets. The helper runs on macOS and Linux.</p>
  </div>

  <div class="card">
    <h2>Privacy Policy</h2>
    <p>CLI Pulse collects only aggregated usage metrics (token counts, cost estimates,
       session durations) from locally detected AI tool processes. No source code, prompts,
       or conversation content is ever collected or transmitted. You can delete your account
       and all associated data at any time from Settings.</p>
  </div>

  <div class="footer">
    <p>&copy; 2026 CLI Pulse. All rights reserved.</p>
  </div>
</div>
</body>
</html>
"""

app = create_app(build_store())
