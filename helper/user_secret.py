"""Per-user secret for project_hash HMAC.

Generated once on first run and stored on the local filesystem with 0600 perms.
Used to compute HMAC-SHA256 of project paths so the database stores hashes
that can't be enumerated/dictionary-attacked across users.

The secret never leaves the device — only the resulting HMAC values do.
"""
from __future__ import annotations

import hmac
import os
import secrets
from hashlib import sha256
from pathlib import Path
from typing import Optional


_SECRET_DIR = Path.home() / ".cli_pulse"
_SECRET_PATH = _SECRET_DIR / "secret.bin"
_SECRET_BYTES = 32


def _ensure_dir() -> None:
    _SECRET_DIR.mkdir(parents=True, exist_ok=True)
    # Best-effort permissions tightening; on Windows this is a no-op.
    try:
        os.chmod(_SECRET_DIR, 0o700)
    except OSError:
        pass


def load_or_create_secret() -> bytes:
    """Return the per-user secret, generating it on first call."""
    if _SECRET_PATH.exists():
        try:
            data = _SECRET_PATH.read_bytes()
            if len(data) == _SECRET_BYTES:
                return data
        except OSError:
            pass

    _ensure_dir()
    secret = secrets.token_bytes(_SECRET_BYTES)
    _SECRET_PATH.write_bytes(secret)
    try:
        os.chmod(_SECRET_PATH, 0o600)
    except OSError:
        pass
    return secret


def project_hash(secret: bytes, absolute_path: str | Path) -> str:
    """Compute HMAC-SHA256 hex digest of an absolute project path.

    Determinism: same secret + same path always yields the same hash.
    Cross-platform: same secret + same path string yields same hash on Python and Swift,
    so long as both sides agree on path normalization (lowercased on macOS, as-is elsewhere).
    """
    path_str = str(absolute_path)
    return hmac.new(secret, path_str.encode("utf-8"), sha256).hexdigest()


def reset_secret_for_testing() -> Optional[Path]:
    """Test helper: delete the secret file. Returns its previous path if it existed."""
    if _SECRET_PATH.exists():
        _SECRET_PATH.unlink()
        return _SECRET_PATH
    return None
