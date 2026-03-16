# CLI Pulse

CLI Pulse is an MVP workspace with three integrated parts:

- `CLI Pulse/`: native iOS SwiftUI app
- `backend/`: FastAPI backend with SQLite persistence
- `helper/`: device helper CLI for Macs or servers

## Backend

Create a local environment and start the API:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.app.main:app --reload
```

Optional environment variables:

```bash
CLI_PULSE_DB_PATH=backend/data/cli_pulse.db
```

Main backend capabilities:

- account sign-in and account creation
- pairing code generation and helper registration
- dashboard, providers, sessions, devices, alerts, settings
- helper heartbeat and sync ingestion
- account deletion

Run backend tests:

```bash
source .venv/bin/activate
pytest tests/test_backend.py
```

## Helper

Generate a pairing code from the app or backend, then pair the local machine:

```bash
python3 helper/cli_pulse_helper.py pair \
  --server http://127.0.0.1:8000 \
  --pairing-code PULSE-XXXXXX \
  --device-name "Jason's MacBook Pro"
```

Inspect the locally collected snapshot before syncing:

```bash
python3 helper/cli_pulse_helper.py inspect
```

Send one heartbeat and one sync:

```bash
python3 helper/cli_pulse_helper.py heartbeat
python3 helper/cli_pulse_helper.py sync
```

Run a short demo loop:

```bash
python3 helper/cli_pulse_helper.py run-demo --cycles 3 --interval 2
```

The helper currently collects:

- local CPU and memory summary
- detected Codex and Gemini CLI processes
- synthetic usage estimates from process lifetime and CPU
- basic local alerts for high CPU and long-running sessions

## iOS App

The app defaults to mock data. To switch to the live backend, set these environment variables in the Xcode scheme:

```bash
CLI_PULSE_USE_REMOTE=1
CLI_PULSE_API_BASE_URL=http://127.0.0.1:8000
```

Current app integration includes:

- remote auth and onboarding
- dashboard, providers, sessions, devices, alerts, settings
- inline error states for failed remote requests
- alert polling every 30 seconds after pairing
- local notification scheduling for warning and critical alerts
- account deletion wired to the backend

After launch:

1. Sign in or create an account.
2. Complete onboarding and get the pairing code.
3. Pair a Mac or server with the helper.
4. Open Dashboard, Sessions, Devices, or Alerts to view live synced data.
5. Allow notifications if you want local alert banners.
