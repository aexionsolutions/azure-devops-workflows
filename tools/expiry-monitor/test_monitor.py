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

    @patch("monitor.az")
    def test_certificate_failure_does_not_skip_vaults_and_only_lists_metadata(self, az):
        az.side_effect = [["certificate-id"], RuntimeError("denied"), ["vault"],
                          [{"id": "secret-id", "end": None}], [], []]
        result = monitor.collect({"subscriptions": ["subscription"]}, azure=True)
        self.assertEqual([(r["kind"], r["status"]) for r in result["items"]],
                         [("appservice-certificate", "unavailable"), ("keyvault-secret", "unknown")])
        calls = [call.args for call in az.call_args_list]
        self.assertIn(("resource", "list", "--subscription", "subscription", "--resource-type",
                       "Microsoft.Web/certificates", "--query", "[].id"), calls)
        vault_calls = [call for call in calls if call[0] == "keyvault" and call[1] in {"secret", "key", "certificate"}]
        self.assertEqual(len(vault_calls), 3)
        self.assertTrue(all(call[2] == "list" for call in vault_calls))

    @patch("monitor.subprocess.run")
    def test_azure_errors_do_not_include_provider_output(self, run):
        run.return_value.returncode = 1
        run.return_value.stderr = "sensitive response"
        with self.assertRaisesRegex(RuntimeError, "metadata query failed") as caught:
            monitor.az("ad", "app", "show")
        self.assertNotIn("sensitive", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
