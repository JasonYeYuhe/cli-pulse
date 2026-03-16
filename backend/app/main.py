from __future__ import annotations

import os

from fastapi import Depends, FastAPI, Header, HTTPException

from .models import (
    AlertActionResponseDTO,
    AlertRecordDTO,
    AuthRequestDTO,
    AuthResponseDTO,
    DashboardSummaryDTO,
    DeviceRecordDTO,
    HelperHeartbeatRequestDTO,
    HelperRegisterRequestDTO,
    HelperRegisterResponseDTO,
    HelperSyncRequestDTO,
    PairingInfoDTO,
    ProviderUsageDTO,
    SessionRecordDTO,
    SettingsSnapshotDTO,
    SettingsUpdateDTO,
    SuccessDTO,
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

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/v1/auth/sign-in", response_model=AuthResponseDTO)
    def sign_in(payload: AuthRequestDTO) -> AuthResponseDTO:
        state = store.login(payload.email, payload.name)
        return AuthResponseDTO(access_token=state.token, user=state.user, paired=state.paired)

    @app.post("/v1/auth/create-account", response_model=AuthResponseDTO)
    def create_account(payload: AuthRequestDTO) -> AuthResponseDTO:
        state = store.login(payload.email, payload.name)
        return AuthResponseDTO(access_token=state.token, user=state.user, paired=state.paired)

    @app.get("/v1/auth/me", response_model=AuthResponseDTO)
    def me(token: str = Depends(current_token)) -> AuthResponseDTO:
        state = store.authenticate(token)
        assert state is not None
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

    @app.get("/v1/settings", response_model=SettingsSnapshotDTO)
    def settings(token: str = Depends(current_token)) -> SettingsSnapshotDTO:
        return store.settings(token)

    @app.put("/v1/settings", response_model=SettingsSnapshotDTO)
    def update_settings(payload: SettingsUpdateDTO, token: str = Depends(current_token)) -> SettingsSnapshotDTO:
        return store.update_settings(token, payload)

    @app.delete("/v1/account", response_model=SuccessDTO)
    def delete_account(token: str = Depends(current_token)) -> SuccessDTO:
        return store.delete_account(token)

    @app.post("/v1/helper/register", response_model=HelperRegisterResponseDTO)
    def helper_register(payload: HelperRegisterRequestDTO) -> HelperRegisterResponseDTO:
        response = store.register_helper(payload)
        if response is None:
            raise HTTPException(status_code=404, detail="Invalid or expired pairing code")
        return response

    @app.post("/v1/helper/heartbeat", response_model=SuccessDTO)
    def helper_heartbeat(payload: HelperHeartbeatRequestDTO, token: str = Depends(current_token)) -> SuccessDTO:
        try:
            return store.helper_heartbeat(token, payload)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    @app.post("/v1/helper/sync", response_model=SuccessDTO)
    def helper_sync(payload: HelperSyncRequestDTO, token: str = Depends(current_token)) -> SuccessDTO:
        try:
            return store.helper_sync(token, payload)
        except PermissionError as error:
            raise HTTPException(status_code=403, detail=str(error)) from error

    return app


app = create_app(build_store())
