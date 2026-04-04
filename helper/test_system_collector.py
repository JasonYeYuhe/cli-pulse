"""Tests for provider quota parsing and collection in system_collector.py."""
from __future__ import annotations
import unittest
from unittest.mock import patch
from system_collector import (
    _parse_claude_api_response, _parse_claude_usage_output, _infer_claude_plan,
    _parse_gemini_quota_response, _load_gemini_project_id,
    _parse_codex_usage_response, collect_device_snapshot, collect_all,
)


class TestInferClaudePlan(unittest.TestCase):
    def test_max_tier(self):
        self.assertEqual(_infer_claude_plan("max_5x", ""), "Max")

    def test_pro_tier(self):
        self.assertEqual(_infer_claude_plan("pro", ""), "Pro")

    def test_free_sub(self):
        self.assertEqual(_infer_claude_plan("", "free"), "Free")

    def test_sub_type_fallback(self):
        self.assertEqual(_infer_claude_plan("", "team"), "Team")

    def test_unknown(self):
        self.assertEqual(_infer_claude_plan("", ""), "Unknown")


class TestParseClaudeAPIResponse(unittest.TestCase):
    def test_full_response(self):
        data = {
            "five_hour": {"utilization": 45, "resets_at": "2026-04-02T22:00:00Z"},
            "seven_day": {"utilization": 60, "resets_at": "2026-04-09T00:00:00Z"},
            "seven_day_opus": {"utilization": 75, "resets_at": "2026-04-09T00:00:00Z"},
            "seven_day_sonnet": {"utilization": 20, "resets_at": "2026-04-09T00:00:00Z"},
        }
        result = _parse_claude_api_response(data, "Max")
        self.assertIsNotNone(result)
        self.assertEqual(len(result["tiers"]), 4)
        self.assertEqual(result["plan_type"], "Max")

        # 5h Window tier
        t0 = result["tiers"][0]
        self.assertEqual(t0["name"], "5h Window")
        self.assertEqual(t0["quota"], 100)
        self.assertEqual(t0["remaining"], 55)  # 100 - 45
        self.assertEqual(t0["reset_time"], "2026-04-02T22:00:00Z")

        # Weekly tier
        t1 = result["tiers"][1]
        self.assertEqual(t1["name"], "Weekly")
        self.assertEqual(t1["remaining"], 40)  # 100 - 60

        # Opus tier
        t2 = result["tiers"][2]
        self.assertEqual(t2["name"], "Opus (Weekly)")
        self.assertEqual(t2["remaining"], 25)  # 100 - 75

        # Sonnet tier
        t3 = result["tiers"][3]
        self.assertEqual(t3["name"], "Sonnet (Weekly)")
        self.assertEqual(t3["remaining"], 80)  # 100 - 20

        # Top-level quota/remaining from primary tier
        self.assertEqual(result["quota"], 100)
        self.assertEqual(result["remaining"], 55)

    def test_minimal_response(self):
        data = {"five_hour": {"utilization": 10, "resets_at": "2026-04-02T22:00:00Z"}}
        result = _parse_claude_api_response(data)
        self.assertIsNotNone(result)
        self.assertEqual(len(result["tiers"]), 1)
        self.assertEqual(result["tiers"][0]["remaining"], 90)
        self.assertEqual(result["plan_type"], "Max")  # default

    def test_with_extra_usage(self):
        data = {
            "five_hour": {"utilization": 10, "resets_at": "2026-04-02T22:00:00Z"},
            "extra_usage": {
                "is_enabled": True,
                "monthly_limit": 5000.0,
                "used_credits": 1234.56,
                "currency": "USD",
            },
        }
        result = _parse_claude_api_response(data, "Max")
        self.assertEqual(len(result["tiers"]), 2)
        extra = result["tiers"][1]
        self.assertEqual(extra["name"], "Extra Usage")
        self.assertEqual(extra["quota"], 500_000_000)  # 5000 * 100000
        expected_remaining = int(max(0, 5000.0 - 1234.56) * 100_000)
        self.assertEqual(extra["remaining"], expected_remaining)

    def test_empty_response(self):
        self.assertIsNone(_parse_claude_api_response({}))

    def test_disabled_extra_usage(self):
        data = {
            "five_hour": {"utilization": 5, "resets_at": "2026-04-02T22:00:00Z"},
            "extra_usage": {"is_enabled": False, "monthly_limit": 0, "used_credits": 0},
        }
        result = _parse_claude_api_response(data)
        self.assertEqual(len(result["tiers"]), 1, "Disabled extra_usage should not produce a tier")


class TestParseClaudeUsageOutput(unittest.TestCase):
    def test_standard_cli_output(self):
        output = """Settings: Usage

Current session
42% left
Resets in 2 hours

Current week (all models)
75% left
Resets Monday 12:00 AM

Current week (Opus)
60% left
Resets Monday 12:00 AM
"""
        result = _parse_claude_usage_output(output)
        self.assertIsNotNone(result)
        # 42% left → 58% used → remaining=42
        self.assertEqual(result["tiers"][0]["name"], "5h Window")
        self.assertEqual(result["tiers"][0]["remaining"], 42)
        # 75% left → 25% used → remaining=75
        self.assertEqual(result["tiers"][1]["name"], "Weekly")
        self.assertEqual(result["tiers"][1]["remaining"], 75)
        # Opus 60% left → 40% used → remaining=60
        self.assertEqual(result["tiers"][2]["name"], "Opus (Weekly)")
        self.assertEqual(result["tiers"][2]["remaining"], 60)

    def test_no_usage_data(self):
        self.assertIsNone(_parse_claude_usage_output("Loading...\nPlease wait"))

    def test_used_semantics(self):
        output = """Current session
58% used

Current week (all models)
25% used
"""
        result = _parse_claude_usage_output(output)
        self.assertIsNotNone(result)
        # 58% used → remaining=42
        self.assertEqual(result["tiers"][0]["remaining"], 42)
        # 25% used → remaining=75
        self.assertEqual(result["tiers"][1]["remaining"], 75)


class TestParseGeminiQuotaResponse(unittest.TestCase):
    def test_prefers_pro_order_and_primary(self):
        data = {
            "buckets": [
                {"modelId": "gemini-2.5-flash", "remainingFraction": 1.0, "resetTime": "2026-04-03T09:08:42Z", "tokenType": "REQUESTS"},
                {"modelId": "gemini-2.5-flash-lite", "remainingFraction": 1.0, "resetTime": "2026-04-03T09:08:42Z", "tokenType": "REQUESTS"},
                {"modelId": "gemini-2.5-pro", "remainingFraction": 0.81, "resetTime": "2026-04-03T04:39:00Z", "tokenType": "REQUESTS"},
            ]
        }
        result = _parse_gemini_quota_response(data)
        self.assertIsNotNone(result)
        self.assertEqual([tier["name"] for tier in result["tiers"]], ["Pro", "Flash", "Flash Lite"])
        self.assertEqual(result["remaining"], 81)
        self.assertEqual(result["reset_time"], "2026-04-03T04:39:00Z")


class TestGeminiLoadCodeAssist(unittest.TestCase):
    def test_load_project_id_from_string(self):
        import system_collector as sc
        original = sc.urllib.request.urlopen
        class Resp:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self): return b'{"cloudaicompanionProject":"centering-invention-98n20"}'
        try:
            sc.urllib.request.urlopen = lambda *args, **kwargs: Resp()
            self.assertEqual(_load_gemini_project_id("token"), "centering-invention-98n20")
        finally:
            sc.urllib.request.urlopen = original


class TestParseCodexUsageResponse(unittest.TestCase):
    def test_full_response(self):
        data = {
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 23,
                    "reset_after_seconds": 2391,
                    "reset_at": 1775054266,
                },
                "secondary_window": {
                    "used_percent": 10,
                    "reset_after_seconds": 100000,
                    "reset_at": 1775200000,
                },
            },
        }
        result = _parse_codex_usage_response(data)
        self.assertIsNotNone(result)
        self.assertEqual(result["plan_type"], "Plus")
        self.assertEqual(len(result["tiers"]), 2)
        self.assertEqual(result["tiers"][0]["name"], "Session")
        self.assertEqual(result["tiers"][0]["remaining"], 77)
        self.assertEqual(result["tiers"][1]["name"], "Weekly")
        self.assertEqual(result["tiers"][1]["remaining"], 90)

    def test_primary_only(self):
        data = {
            "plan_type": "pro",
            "rate_limit": {
                "primary_window": {"used_percent": 50, "reset_at": 1775054266},
            },
        }
        result = _parse_codex_usage_response(data)
        self.assertIsNotNone(result)
        self.assertEqual(result["remaining"], 50)
        self.assertEqual(len(result["tiers"]), 1)

    def test_empty_rate_limit(self):
        self.assertIsNone(_parse_codex_usage_response({"plan_type": "free", "rate_limit": {}}))

    def test_no_rate_limit(self):
        self.assertIsNone(_parse_codex_usage_response({}))


class TestCollectDeviceSnapshot(unittest.TestCase):
    def test_returns_valid_snapshot(self):
        snapshot = collect_device_snapshot()
        self.assertGreaterEqual(snapshot.cpu_usage, 0)
        self.assertLessEqual(snapshot.cpu_usage, 100)
        self.assertGreaterEqual(snapshot.memory_usage, 0)
        self.assertLessEqual(snapshot.memory_usage, 100)


class TestCollectAll(unittest.TestCase):
    def test_returns_result_with_no_crash(self):
        result = collect_all()
        self.assertIsNotNone(result.device)
        self.assertIsInstance(result.sessions, list)
        self.assertIsInstance(result.alerts, list)
        self.assertIsInstance(result.provider_remaining, dict)
        self.assertIsInstance(result.collection_errors, list)


if __name__ == "__main__":
    unittest.main()
