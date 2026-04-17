"""Yield score: scan tracked project repos for new commits and submit to Supabase.

Triggered by the helper daemon on session-set changes (a new tracked session
appears or one disappears), with a 10-minute backstop while any tracked session
is active, and a 5-minute follow-up after a session disappears. Per Codex review:
do not scan every minute; do not scan when no sessions are active.

Privacy guarantees:
- Only commit hash, HMAC-hashed project path, ISO timestamp, and is_merge flag
  are sent to the server. NO commit message, diff, file paths, or author identity.
- Merge commits are filtered out with `--no-merges` and additionally tagged
  `is_merge=true` if a multi-parent commit slips through, so the server can
  exclude them from yield attribution.
- All git invocations are bounded with a 10-second timeout and `--since` window
  so a corrupt or huge repo can't stall the daemon.
"""
from __future__ import annotations

import logging
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional

import user_secret as _user_secret_module


logger = logging.getLogger(__name__)


@dataclass
class CommitRecord:
    commit_hash: str        # SHA1
    project_hash: str       # HMAC-SHA256 of absolute project path
    committed_at: str       # ISO8601 from git's %aI
    is_merge: bool

    def to_dict(self) -> dict:
        return {
            "commit_hash": self.commit_hash,
            "project_hash": self.project_hash,
            "committed_at": self.committed_at,
            "is_merge": self.is_merge,
        }


class GitCollector:
    """Stateful scanner. Remembers the last seen commit per project so each
    poll only emits new commits, even across helper restarts (state survives
    in-memory only — first poll after restart re-scans the `--since` window).
    """

    def __init__(self, secret: bytes, since_window: str = "2 hours ago", subprocess_timeout: float = 10.0):
        self._secret = secret
        self._since_window = since_window
        self._subprocess_timeout = subprocess_timeout
        self._last_seen_commit_per_project: dict[str, str] = {}

    def scan_project(self, project_path: Path) -> list[CommitRecord]:
        """Run `git log` for one project and return new commits since last scan.

        Returns an empty list on any error (git missing, repo corrupt,
        permission denied, timeout). Errors are logged at WARNING level.
        """
        if not project_path.exists() or not (project_path / ".git").exists():
            return []

        try:
            result = subprocess.run(
                [
                    "git", "-C", str(project_path), "log",
                    "--no-merges",                     # exclude merge commits up front
                    f"--since={self._since_window}",
                    "--pretty=format:%H|%aI|%P",       # hash | iso_committer_date | parent_hashes
                ],
                capture_output=True, text=True, timeout=self._subprocess_timeout,
            )
        except FileNotFoundError:
            logger.warning("git executable not found; skipping git scan for %s", project_path)
            return []
        except subprocess.TimeoutExpired:
            logger.warning("git log timed out for %s", project_path)
            return []
        except OSError as exc:
            logger.warning("git log failed for %s: %s", project_path, exc)
            return []

        if result.returncode != 0:
            logger.warning("git log returned %s for %s: %s",
                           result.returncode, project_path, result.stderr.strip()[:200])
            return []

        project_str = str(project_path)
        last_seen = self._last_seen_commit_per_project.get(project_str)
        commits: list[CommitRecord] = []
        first_hash: Optional[str] = None

        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            parts = line.split("|", 2)
            if len(parts) < 2:
                continue
            commit_hash, committed_at = parts[0], parts[1]
            parents = parts[2] if len(parts) > 2 else ""
            if first_hash is None:
                first_hash = commit_hash
            if commit_hash == last_seen:
                # Reached previously-seen commit; everything older is already submitted.
                break
            commits.append(CommitRecord(
                commit_hash=commit_hash,
                project_hash=_user_secret_module.project_hash(self._secret, project_str),
                committed_at=committed_at,
                # `git log --no-merges` should already have filtered merges, but defend in depth.
                is_merge=len(parents.split()) > 1,
            ))

        if first_hash is not None:
            self._last_seen_commit_per_project[project_str] = first_hash
        return commits

    def collect(self, project_paths: Iterable[Path]) -> list[CommitRecord]:
        """Scan multiple projects, returning the union of new commits."""
        out: list[CommitRecord] = []
        seen: set[str] = set()  # dedupe by commit_hash (same commit in multiple worktrees)
        for path in project_paths:
            for record in self.scan_project(path):
                if record.commit_hash in seen:
                    continue
                seen.add(record.commit_hash)
                out.append(record)
        return out


def project_paths_from_sessions(sessions: list) -> list[Path]:
    """Extract unique project_root paths from a list of CollectedSession objects.

    Sessions whose project_root is None are skipped. Caller is responsible for
    enforcing the user's `track_git_activity` setting before invoking the scanner.
    """
    seen: set[str] = set()
    paths: list[Path] = []
    for session in sessions:
        root = getattr(session, "project_root", None)
        if not root or root in seen:
            continue
        seen.add(root)
        paths.append(Path(root))
    return paths
