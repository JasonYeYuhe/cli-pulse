import sys
from pathlib import Path

from fastapi.testclient import TestClient
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from backend.app.main import create_app
from backend.app.store import SQLiteStore


@pytest.fixture()
def client(tmp_path: Path) -> TestClient:
    app = create_app(SQLiteStore(str(tmp_path / "cli_pulse_test.db")))
    return TestClient(app)


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
    assert body["active_sessions"] >= 1
    assert len(body["provider_breakdown"]) == 2


def test_helper_registration_and_sync(client: TestClient) -> None:
    headers = auth_headers(client)
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
                    "requests": 40,
                    "error_count": 0,
                    "started_at": "2026-03-16T00:00:00Z",
                    "last_active_at": "2026-03-16T00:05:00Z",
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
