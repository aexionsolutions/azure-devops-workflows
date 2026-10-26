import datetime as dt
import unittest
from unittest.mock import patch
import monitor


class MonitorTests(unittest.TestCase):
    def test_warning_boundaries(self):
        now = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        for days, expected in [(-1, "expired"), (0, "urgent"), (7, "urgent"),
                               (8, "14-days"), (14, "14-days"), (15, "30-days"),
                               (30, "30-days"), (31, "60-days"), (60, "60-days"), (61, "healthy")]:
            self.assertEqual(monitor.classify((now + dt.timedelta(days=days)).isoformat(), now), (expected, days))
        self.assertEqual(monitor.classify(None, now), ("unknown", None))

    @patch("monitor.tls_expiry", side_effect=OSError("sensitive provider response"))
    def test_unreachable_is_not_healthy_or_leaked(self, _):
        result = monitor.collect({"hosts": ["example.com"]})
        self.assertEqual(result["items"][0]["status"], "unavailable")
        self.assertNotIn("sensitive", monitor.markdown(result))

    @patch("monitor.az")
    def test_credentials_empty_and_missing_expiry(self, az):
        az.side_effect = [{"name": "oidc", "passwords": [], "certificates": []},
                          {"name": "legacy", "passwords": [{"id": "key", "end": None}]}]
        result = monitor.collect({"applications": ["one", "two"]}, azure=True)
        self.assertEqual([r["status"] for r in result["items"]], ["no-expiring-credentials", "unknown"])

    @patch("monitor.az", side_effect=RuntimeError("forbidden"))
    def test_permission_failure_is_reported(self, _):
        result = monitor.collect({"subscriptions": ["subscription"]}, azure=True)
        self.assertEqual(result["items"][0]["status"], "unavailable")


if __name__ == "__main__":
    unittest.main()
