import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from backend.app.main import create_app
from backend.app.models import DeviceRecordDTO, DeviceStatus, SubscriptionTier
from backend.app.store import SQLiteStore


@pytest.fixture()
def client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(str(tmp_path / "cli_pulse_test.db"))
    app = create_app(store)
    app.state.store = store
    return TestClient(app)


def _upgrade_to_pro(client: TestClient, headers: dict[str, str]) -> None:
    """Upgrade the authenticated user to Pro tier via the store directly."""
    store: SQLiteStore = client.app.state.store
    token = headers["Authorization"].split(" ", 1)[1]
    store.update_subscription(token, SubscriptionTier.pro)


def _upgrade_to_team(client: TestClient, headers: dict[str, str]) -> None:
    """Upgrade the authenticated user to Team tier via the store directly."""
    store: SQLiteStore = client.app.state.store
    token = headers["Authorization"].split(" ", 1)[1]
    store.update_subscription(token, SubscriptionTier.team)


def _recent_iso(hours_ago: int = 1) -> str:
    """Return an ISO timestamp for a recent time (within free tier retention)."""
    return (datetime.now(timezone.utc) - timedelta(hours=hours_ago)).isoformat()


def auth_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/sign-in",
        json={"email": "jason@example.com", "password": "password123"},
    )
    assert response.status_code == 200
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_dashboard_summary_works(client: TestClient) -> None:
    headers = auth_headers(client)
    pair_response = client.post("/v1/onboarding/complete", headers=headers)
    assert pair_response.status_code == 200

    response = client.get("/v1/dashboard/summary", headers=headers)
    assert response.status_code == 200
    body = response.json()

    assert body["total_usage"] > 0
    assert body["total_estimated_cost"] > 0
    assert body["active_sessions"] >= 1
    provider_names = {item["provider"] for item in body["provider_breakdown"]}
    # Free tier limits to 3 providers
    assert len(provider_names) >= 3
    assert {"Codex", "Gemini", "Claude"}.issubset(provider_names)
    assert len(body["top_projects"]) >= 3
    assert body["provider_breakdown"][0]["cost_status_today"] in {"Exact", "Estimated", "Unavailable"}
    assert body["cost_status"] in {"Exact", "Estimated", "Unavailable"}
    assert body["alert_summary"]["open_count"] >= 1
    assert body["alert_summary"]["type_breakdown"][0]["count"] >= 1


def test_helper_registration_and_sync(client: TestClient) -> None:
    headers = auth_headers(client)
    _upgrade_to_pro(client, headers)
    update_settings = client.put(
        "/v1/settings",
        headers=headers,
        json={
            "notifications_enabled": True,
            "push_policy": "Warnings + Critical",
            "digest_notifications_enabled": True,
            "digest_interval_minutes": 15,
            "usage_spike_threshold": 10_000,
            "project_budget_threshold_usd": 2.50,
            "session_too_long_threshold_minutes": 180,
            "offline_grace_period_minutes": 5,
            "repeated_failure_threshold": 3,
            "alert_cooldown_minutes": 30,
            "data_retention_days": 30,
        },
    )
    assert update_settings.status_code == 200
    assert update_settings.json()["digest_notifications_enabled"] is True
    assert update_settings.json()["digest_interval_minutes"] == 15

    pairing = client.get("/v1/onboarding/pairing-code", headers=headers)
    assert pairing.status_code == 200
    pairing_code = pairing.json()["code"]

    register = client.post(
        "/v1/helper/register",
        json={
            "pairing_code": pairing_code,
            "device_name": "Test Mac",
            "device_type": "Mac",
            "system": "macOS",
            "helper_version": "0.1.0",
        },
    )
    assert register.status_code == 200
    helper_token = register.json()["access_token"]
    device_id = register.json()["device_id"]
    helper_headers = {"Authorization": f"Bearer {helper_token}"}

    heartbeat = client.post(
        "/v1/helper/heartbeat",
        headers=helper_headers,
        json={"device_id": device_id, "cpu_usage": 40, "memory_usage": 52, "active_session_count": 1},
    )
    assert heartbeat.status_code == 200

    sync = client.post(
        "/v1/helper/sync",
        headers=helper_headers,
        json={
            "device_id": device_id,
            "sessions": [
                {
                    "id": "7f101e56-6af1-4a2f-9af3-a978078cff45",
                    "name": "Remote coding task",
                    "provider": "Codex",
                    "project": "cli-pulse-ios",
                    "status": "Running",
                    "total_usage": 12000,
                    "exact_cost": 3.25,
                    "requests": 40,
                    "error_count": 0,
                    "started_at": _recent_iso(2),
                    "last_active_at": _recent_iso(1),
                }
            ],
            "alerts": [],
            "provider_remaining": {"Codex": 35000, "Gemini": 80000},
        },
    )
    assert sync.status_code == 200

    devices = client.get("/v1/devices", headers=headers)
    assert devices.status_code == 200
    assert any(item["id"] == device_id for item in devices.json())

    projects = client.get("/v1/projects", headers=headers)
    assert projects.status_code == 200
    project_items = projects.json()
    assert any(item["name"] == "cli-pulse-ios" for item in project_items)
    assert any(item["name"] == "cli-pulse-ios" and item["estimated_cost_today"] >= 3.25 for item in project_items)
    assert any(item["name"] == "cli-pulse-ios" and item["cost_status_today"] == "Estimated" for item in project_items)

    sessions = client.get("/v1/sessions", headers=headers)
    assert sessions.status_code == 200
    assert any(item["name"] == "Remote coding task" and item["cost_status"] == "Exact" for item in sessions.json())

    alerts = client.get("/v1/alerts", headers=headers)
    assert alerts.status_code == 200
    assert any(
        item["type"] == "Project Budget Exceeded"
        and item["related_project_id"] == "cli-pulse-ios"
        and item["is_resolved"] is False
        for item in alerts.json()
    )
    assert any(
        item["type"] == "Usage Spike"
        and item["related_provider"] == "Codex"
        and item["is_resolved"] is False
        for item in alerts.json()
    )


def test_alert_rules_apply_cooldown_and_resolution(client: TestClient) -> None:
    headers = auth_headers(client)
    _upgrade_to_pro(client, headers)
    update_settings = client.put(
        "/v1/settings",
        headers=headers,
        json={
            "notifications_enabled": True,
            "push_policy": "Critical Only",
            "digest_notifications_enabled": True,
            "digest_interval_minutes": 10,
            "usage_spike_threshold": 5_000,
            "project_budget_threshold_usd": 10.0,
            "session_too_long_threshold_minutes": 240,
            "offline_grace_period_minutes": 3,
            "repeated_failure_threshold": 2,
            "alert_cooldown_minutes": 60,
            "data_retention_days": 30,
        },
    )
    assert update_settings.status_code == 200
    assert update_settings.json()["digest_interval_minutes"] == 10

    pairing = client.get("/v1/onboarding/pairing-code", headers=headers)
    pairing_code = pairing.json()["code"]
    register = client.post(
        "/v1/helper/register",
        json={
            "pairing_code": pairing_code,
            "device_name": "Rule Test Mac",
            "device_type": "Mac",
            "system": "macOS",
            "helper_version": "0.1.0",
        },
    )
    helper_headers = {"Authorization": f"Bearer {register.json()['access_token']}"}
    device_id = register.json()["device_id"]

    failed_sync = client.post(
        "/v1/helper/sync",
        headers=helper_headers,
        json={
            "device_id": device_id,
            "sessions": [
                {
                    "id": "4bf33006-aa2f-4699-94e3-f214433050ea",
                    "name": "Failing sync task",
                    "provider": "Codex",
                    "project": "phase3-rules",
                    "status": "Failed",
                    "total_usage": 9000,
                    "requests": 12,
                    "error_count": 4,
                    "started_at": _recent_iso(3),
                    "last_active_at": _recent_iso(1),
                }
            ],
            "alerts": [],
            "provider_remaining": {"Codex": 25000},
        },
    )
    assert failed_sync.status_code == 200

    alerts = client.get("/v1/alerts", headers=headers)
    body = alerts.json()
    matching_failures = [
        item for item in body
        if item["type"] == "Session Failed" and item["related_session_id"] == "4bf33006-aa2f-4699-94e3-f214433050ea"
    ]
    assert len(matching_failures) == 1
    assert matching_failures[0]["is_resolved"] is False

    recovered_sync = client.post(
        "/v1/helper/sync",
        headers=helper_headers,
        json={
            "device_id": device_id,
            "sessions": [
                {
                    "id": "4bf33006-aa2f-4699-94e3-f214433050ea",
                    "name": "Failing sync task",
                    "provider": "Codex",
                    "project": "phase3-rules",
                    "status": "Running",
                    "total_usage": 9000,
                    "requests": 12,
                    "error_count": 0,
                    "started_at": _recent_iso(3),
                    "last_active_at": _recent_iso(0),
                }
            ],
            "alerts": [],
            "provider_remaining": {"Codex": 25000},
        },
    )
    assert recovered_sync.status_code == 200

    resolved_alerts = client.get("/v1/alerts", headers=headers).json()
    resolved_failures = [
        item for item in resolved_alerts
        if item["type"] == "Session Failed" and item["related_session_id"] == "4bf33006-aa2f-4699-94e3-f214433050ea"
    ]
    assert len(resolved_failures) == 1
    assert resolved_failures[0]["is_resolved"] is True

    store = client.app.state.store
    token = headers["Authorization"].split(" ", 1)[1]
    session_state = store.authenticate(token)
    assert session_state is not None
    devices = store._load_models(session_state.user.id, "devices_json", DeviceRecordDTO)
    for device in devices:
        if device.id == device_id:
            device.last_sync_at = device.last_sync_at.replace(year=2026, month=3, day=15)
            device.status = DeviceStatus.online
            break
    store._save_models(session_state.user.id, "devices_json", devices)

    offline_alerts = client.get("/v1/alerts", headers=headers).json()
    matching_offline = [
        item for item in offline_alerts
        if item["type"] == "Helper Offline" and item["related_device_name"] == "Rule Test Mac" and item["is_resolved"] is False
    ]
    assert len(matching_offline) == 1

    offline_alerts_again = client.get("/v1/alerts", headers=headers).json()
    matching_offline_again = [
        item for item in offline_alerts_again
        if item["type"] == "Helper Offline" and item["related_device_name"] == "Rule Test Mac" and item["is_resolved"] is False
    ]
    assert len(matching_offline_again) == 1

    heartbeat = client.post(
        "/v1/helper/heartbeat",
        headers=helper_headers,
        json={"device_id": device_id, "cpu_usage": 22, "memory_usage": 31, "active_session_count": 1},
    )
    assert heartbeat.status_code == 200

    recovered_offline_alerts = client.get("/v1/alerts", headers=headers).json()
    resolved_offline = [
        item for item in recovered_offline_alerts
        if item["type"] == "Helper Offline" and item["related_device_name"] == "Rule Test Mac"
    ]
    assert len(resolved_offline) == 1
    assert resolved_offline[0]["is_resolved"] is True

    open_alert = next(item for item in recovered_offline_alerts if item["is_resolved"] is False)
    ack_response = client.post(f"/v1/alerts/{open_alert['id']}/ack", headers=headers)
    assert ack_response.status_code == 200

    snooze_response = client.post(
        f"/v1/alerts/{open_alert['id']}/snooze",
        headers=headers,
        json={"minutes": 30},
    )
    assert snooze_response.status_code == 200

    post_snooze_alerts = client.get("/v1/alerts", headers=headers).json()
    snoozed_alert = next(item for item in post_snooze_alerts if item["id"] == open_alert["id"])
    assert snoozed_alert["is_read"] is True
    assert snoozed_alert["acknowledged_at"] is not None
    assert snoozed_alert["snoozed_until"] is not None


def test_subscription_defaults_to_free(client: TestClient) -> None:
    headers = auth_headers(client)

    response = client.get("/v1/subscription", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["tier"] == "free"
    assert body["status"] == "active"
    assert body["cancel_at_period_end"] is False

    limits = client.get("/v1/subscription/limits", headers=headers)
    assert limits.status_code == 200
    lim = limits.json()
    assert lim["max_providers"] == 3
    assert lim["max_devices"] == 1
    assert lim["data_retention_days"] == 7
    assert lim["has_api_access"] is False
    assert lim["has_project_budgets"] is False
    assert lim["export_formats"] == []
    assert lim["max_team_members"] == 1


def test_subscription_upgrade_to_pro(client: TestClient) -> None:
    headers = auth_headers(client)

    # Verify free tier limits providers
    providers_free = client.get("/v1/providers", headers=headers)
    assert providers_free.status_code == 200
    assert len(providers_free.json()) == 3

    # Upgrade to pro
    _upgrade_to_pro(client, headers)

    sub = client.get("/v1/subscription", headers=headers)
    assert sub.status_code == 200
    assert sub.json()["tier"] == "pro"

    limits = client.get("/v1/subscription/limits", headers=headers)
    assert limits.status_code == 200
    lim = limits.json()
    assert lim["max_providers"] == -1
    assert lim["max_devices"] == 5
    assert lim["data_retention_days"] == 90
    assert lim["has_api_access"] is True
    assert lim["has_project_budgets"] is True
    assert "csv" in lim["export_formats"]

    # Pro tier returns all providers (8 seeded: Codex, Gemini, Claude, OpenRouter, Ollama, Cursor, Copilot, Kimi K2)
    providers_pro = client.get("/v1/providers", headers=headers)
    assert providers_pro.status_code == 200
    assert len(providers_pro.json()) == 8


def test_free_tier_alert_filtering(client: TestClient) -> None:
    """Free tier should only see quota_low, usage_spike, helper_offline alerts."""
    headers = auth_headers(client)

    alerts = client.get("/v1/alerts", headers=headers)
    assert alerts.status_code == 200
    for item in alerts.json():
        assert item["type"] in {"Quota Low", "Usage Spike", "Helper Offline"}


def test_apple_receipt_verify_rejects_invalid(client: TestClient) -> None:
    headers = auth_headers(client)

    # Malformed receipt (not a valid JWS) should fail
    response = client.post(
        "/v1/subscription/verify",
        headers=headers,
        json={"receipt_data": "fake-receipt-data"},
    )
    assert response.status_code == 400  # Invalid JWS format

    # Valid JWS structure but unknown product
    import base64, json as _json
    header = base64.urlsafe_b64encode(b'{"alg":"ES256"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(
        _json.dumps({"productId": "unknown_product", "transactionId": "123"}).encode()
    ).rstrip(b"=").decode()
    sig = base64.urlsafe_b64encode(b"fakesig").rstrip(b"=").decode()
    jws = f"{header}.{payload}.{sig}"

    response = client.post(
        "/v1/subscription/verify",
        headers=headers,
        json={"receipt_data": jws},
    )
    assert response.status_code == 400  # Unknown product ID

    # Valid JWS with known product should upgrade
    payload_pro = base64.urlsafe_b64encode(
        _json.dumps({"productId": "clipulse_pro_monthly", "transactionId": "txn_456"}).encode()
    ).rstrip(b"=").decode()
    jws_pro = f"{header}.{payload_pro}.{sig}"

    response = client.post(
        "/v1/subscription/verify",
        headers=headers,
        json={"receipt_data": jws_pro},
    )
    assert response.status_code == 200
    assert response.json()["tier"] == "pro"


def test_team_requires_team_tier(client: TestClient) -> None:
    headers = auth_headers(client)

    # Free user cannot create team
    response = client.post("/v1/team", headers=headers, json={"name": "My Team"})
    assert response.status_code == 403

    # Pro user cannot create team
    _upgrade_to_pro(client, headers)
    response = client.post("/v1/team", headers=headers, json={"name": "My Team"})
    assert response.status_code == 403


def test_team_lifecycle(client: TestClient) -> None:
    headers = auth_headers(client)
    _upgrade_to_team(client, headers)

    # Create team
    create_response = client.post("/v1/team", headers=headers, json={"name": "Test Team"})
    assert create_response.status_code == 200
    team = create_response.json()
    assert team["name"] == "Test Team"
    assert team["member_count"] == 1
    assert team["max_members"] == 50

    # Get team
    get_response = client.get("/v1/team", headers=headers)
    assert get_response.status_code == 200
    assert get_response.json()["name"] == "Test Team"

    # Get members (owner is the only member)
    members_response = client.get("/v1/team/members", headers=headers)
    assert members_response.status_code == 200
    members = members_response.json()
    assert len(members) == 1
    assert members[0]["role"] == "owner"

    # Invite a member
    invite_response = client.post(
        "/v1/team/invite",
        headers=headers,
        json={"email": "teammate@example.com", "role": "member"},
    )
    assert invite_response.status_code == 200
    invite = invite_response.json()
    assert invite["email"] == "teammate@example.com"
    assert invite["role"] == "member"
    invite_id = invite["id"]

    # Create second user and accept invite
    second_user_response = client.post(
        "/v1/auth/sign-in",
        json={"email": "teammate@example.com", "password": "password123"},
    )
    assert second_user_response.status_code == 200
    second_headers = {"Authorization": f"Bearer {second_user_response.json()['access_token']}"}

    accept_response = client.post(
        f"/v1/team/invite/{invite_id}/accept",
        headers=second_headers,
    )
    assert accept_response.status_code == 200
    assert accept_response.json()["role"] == "member"

    # Verify member count
    members_after = client.get("/v1/team/members", headers=headers)
    assert len(members_after.json()) == 2

    # Remove member
    member_user_id = accept_response.json()["user_id"]
    remove_response = client.delete(
        f"/v1/team/members/{member_user_id}",
        headers=headers,
    )
    assert remove_response.status_code == 200

    members_final = client.get("/v1/team/members", headers=headers)
    assert len(members_final.json()) == 1


def test_team_dashboard(client: TestClient) -> None:
    headers = auth_headers(client)
    _upgrade_to_team(client, headers)

    # Create team first
    client.post("/v1/team", headers=headers, json={"name": "Dashboard Team"})

    # Get team dashboard
    response = client.get("/v1/team/dashboard", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total_usage"] > 0
    assert "provider_breakdown" in body
    assert "alert_summary" in body


def test_provider_metadata_included(client: TestClient) -> None:
    """Provider metadata should be attached to seeded providers."""
    headers = auth_headers(client)
    _upgrade_to_pro(client, headers)
    providers = client.get("/v1/providers", headers=headers)
    assert providers.status_code == 200
    for item in providers.json():
        meta = item.get("metadata")
        assert meta is not None, f"Provider {item['provider']} missing metadata"
        assert "display_name" in meta
        assert meta["category"] in {"cloud", "local", "aggregator", "ide"}


def test_collection_confidence_in_sessions(client: TestClient) -> None:
    """Sessions should include collection_confidence field."""
    headers = auth_headers(client)
    sessions = client.get("/v1/sessions", headers=headers)
    assert sessions.status_code == 200
    for item in sessions.json():
        assert item.get("collection_confidence") in {"high", "medium", "low"}


def test_cannot_create_duplicate_team(client: TestClient) -> None:
    headers = auth_headers(client)
    _upgrade_to_team(client, headers)

    first = client.post("/v1/team", headers=headers, json={"name": "Team A"})
    assert first.status_code == 200

    second = client.post("/v1/team", headers=headers, json={"name": "Team B"})
    assert second.status_code == 403
