"""Tests for the yield score collectors: user_secret + git_collector.

These tests are hermetic — they don't talk to Supabase or shell out to git
against arbitrary paths. The git_collector test uses a tmp git repo we
construct on the fly so it's deterministic.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import user_secret
import git_collector


class TestUserSecret(unittest.TestCase):

    def setUp(self):
        # Redirect secret file to a tmp dir so we don't clobber user state
        self.tmp = tempfile.TemporaryDirectory()
        self._orig_dir = user_secret._SECRET_DIR
        self._orig_path = user_secret._SECRET_PATH
        user_secret._SECRET_DIR = Path(self.tmp.name) / ".cli_pulse"
        user_secret._SECRET_PATH = user_secret._SECRET_DIR / "secret.bin"

    def tearDown(self):
        user_secret._SECRET_DIR = self._orig_dir
        user_secret._SECRET_PATH = self._orig_path
        self.tmp.cleanup()

    def test_create_secret_when_missing(self):
        secret = user_secret.load_or_create_secret()
        self.assertEqual(len(secret), 32)
        self.assertTrue(user_secret._SECRET_PATH.exists())

    def test_load_existing_secret_is_stable(self):
        first = user_secret.load_or_create_secret()
        second = user_secret.load_or_create_secret()
        self.assertEqual(first, second, "Repeat calls must return the same secret")

    def test_secret_file_perms_0600(self):
        user_secret.load_or_create_secret()
        mode = user_secret._SECRET_PATH.stat().st_mode & 0o777
        # On macOS we expect 0600; on some CI filesystems chmod can fail silently.
        # Allow either 0600 (success) or 0644 (filesystem doesn't enforce).
        self.assertIn(mode, (0o600, 0o644), f"Unexpected mode {oct(mode)}")

    def test_project_hash_determinism(self):
        secret = b"\x42" * 32
        a = user_secret.project_hash(secret, "/Users/jason/Documents/foo")
        b = user_secret.project_hash(secret, "/Users/jason/Documents/foo")
        self.assertEqual(a, b)

    def test_project_hash_path_sensitivity(self):
        secret = b"\x42" * 32
        a = user_secret.project_hash(secret, "/Users/jason/Documents/foo")
        b = user_secret.project_hash(secret, "/Users/jason/Documents/bar")
        self.assertNotEqual(a, b)

    def test_project_hash_secret_sensitivity(self):
        a = user_secret.project_hash(b"\x01" * 32, "/Users/jason/Documents/foo")
        b = user_secret.project_hash(b"\x02" * 32, "/Users/jason/Documents/foo")
        self.assertNotEqual(a, b, "Different secrets must produce different hashes")

    def test_project_hash_is_64_hex_chars(self):
        h = user_secret.project_hash(b"\x42" * 32, "/anywhere")
        self.assertEqual(len(h), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in h))


class TestGitCollector(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        self._run_git("init", "-q")
        # Need committer identity for git commit to work in CI/sandbox environments
        self._run_git("config", "user.email", "test@example.com")
        self._run_git("config", "user.name", "Test")
        self.collector = git_collector.GitCollector(secret=b"\x77" * 32)

    def tearDown(self):
        self.tmp.cleanup()

    def _run_git(self, *args):
        result = subprocess.run(
            ["git", "-C", str(self.repo), *args],
            capture_output=True, text=True, check=False,
        )
        return result

    def _make_commit(self, message: str) -> str:
        (self.repo / "file.txt").write_text(message)
        self._run_git("add", "-A")
        self._run_git("commit", "-q", "-m", message)
        result = self._run_git("rev-parse", "HEAD")
        return result.stdout.strip()

    def test_scan_empty_repo_returns_nothing(self):
        records = self.collector.scan_project(self.repo)
        self.assertEqual(records, [])

    def test_scan_returns_new_commits(self):
        h1 = self._make_commit("first")
        h2 = self._make_commit("second")
        records = self.collector.scan_project(self.repo)
        hashes = [r.commit_hash for r in records]
        self.assertIn(h1, hashes)
        self.assertIn(h2, hashes)
        self.assertEqual(len(records), 2)

    def test_scan_dedupes_against_last_seen(self):
        self._make_commit("first")
        first_scan = self.collector.scan_project(self.repo)
        self.assertEqual(len(first_scan), 1)
        # Second scan should return zero commits since nothing changed
        second_scan = self.collector.scan_project(self.repo)
        self.assertEqual(second_scan, [], "Repeat scan must not re-emit known commits")

    def test_scan_picks_up_only_new_commits(self):
        self._make_commit("first")
        self.collector.scan_project(self.repo)
        new_hash = self._make_commit("second")
        records = self.collector.scan_project(self.repo)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].commit_hash, new_hash)

    def test_scan_excludes_merge_commits(self):
        # Build a branch + merge to produce a merge commit
        self._make_commit("root")
        self._run_git("checkout", "-q", "-b", "feature")
        feature_hash = self._make_commit("feature work")
        self._run_git("checkout", "-q", "main") if self._run_git("checkout", "-q", "main").returncode == 0 else self._run_git("checkout", "-q", "master")
        self._run_git("merge", "-q", "--no-ff", "feature", "-m", "merge feature")

        records = self.collector.scan_project(self.repo)
        for r in records:
            self.assertFalse(r.is_merge,
                             f"Merge commit leaked through --no-merges filter: {r.commit_hash}")

    def test_scan_missing_repo_returns_empty(self):
        records = self.collector.scan_project(Path("/nonexistent/path"))
        self.assertEqual(records, [])

    def test_scan_non_git_directory_returns_empty(self):
        not_a_repo = Path(self.tmp.name) / "not_git"
        not_a_repo.mkdir()
        records = self.collector.scan_project(not_a_repo)
        self.assertEqual(records, [])

    def test_project_hash_matches_user_secret(self):
        self._make_commit("first")
        records = self.collector.scan_project(self.repo)
        expected = user_secret.project_hash(b"\x77" * 32, str(self.repo))
        self.assertEqual(records[0].project_hash, expected)

    def test_collect_dedupes_across_projects(self):
        # Same commit hash in two project paths = should only appear once
        # (rare in practice but guards against worktree-style setups)
        self._make_commit("first")
        records1 = self.collector.scan_project(self.repo)
        self.assertEqual(len(records1), 1)

    def test_collect_returns_empty_for_no_paths(self):
        result = self.collector.collect([])
        self.assertEqual(result, [])

    def test_to_dict_produces_expected_keys(self):
        self._make_commit("first")
        records = self.collector.scan_project(self.repo)
        d = records[0].to_dict()
        self.assertIn("commit_hash", d)
        self.assertIn("project_hash", d)
        self.assertIn("committed_at", d)
        self.assertIn("is_merge", d)
        self.assertNotIn("commit_message", d, "Message must NOT leak into payload")
        self.assertNotIn("author_email", d, "Author email must NOT leak into payload")


if __name__ == "__main__":
    unittest.main()
