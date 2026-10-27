import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import monitor
import jmespath


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
                         [("appservice-certificate", "unavailable"), ("keyvault-secret", "no-expiry")])
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


    @patch("monitor.az")
    def test_no_expiry_is_informational_only_for_vault_keys_and_secrets(self, az):
        az.side_effect = [[], ["vault"], [{"id": "secret", "end": None}],
                          [{"id": "key", "end": None}], [{"id": "certificate", "end": None}]]
        rows = monitor.collect({"subscriptions": ["subscription"]}, azure=True)["items"]
        self.assertEqual([r["status"] for r in rows], ["no-expiry", "no-expiry", "unknown"])
        self.assertTrue(all(r["status"] in monitor.NON_FAILING for r in rows[:2]))
        self.assertNotIn(rows[2]["status"], monitor.NON_FAILING)


    @patch("monitor.subprocess.run")
    def test_real_key_list_shape_writes_json_markdown_and_summary(self, run):
        # Raw Azure CLI shapes, before --query projection. Keys have kid, not id.
        raw = {"key": [{"kid": "https://example.vault.azure.net/keys/route-key/version",
                        "attributes": {"enabled": True, "expires": None}}],
               "secret": [{"id": "https://example.vault.azure.net/secrets/setting",
                           "attributes": {"enabled": True, "expires": None}}],
               "certificate": [{"id": "https://example.vault.azure.net/certificates/site",
                                "attributes": {"enabled": True, "expires": "2099-01-01T00:00:00Z"}}]}

        def cli(command, **kwargs):
            offset = command.index("--query")
            args = command[:offset]
            query = command[offset + 1]
            if "resource" in args:
                data = []
            elif "--vault-name" not in args:
                data = [{"name": "example"}]
            else:
                kind = args[args.index("keyvault") + 1]
                data = raw[kind]
            from types import SimpleNamespace
            return SimpleNamespace(returncode=0, stdout=json.dumps(jmespath.search(query, data)))

        run.side_effect = cli
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "config.json"
            config.write_text(json.dumps({"subscriptions": ["subscription"]}))
            output = str(Path(folder) / "report")
            summary = str(Path(folder) / "summary.md")
            with patch("sys.argv", ["monitor", "--config", str(config), "--azure", "--output", output]), patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": summary}):
                self.assertEqual(monitor.main(), 0)
            report = json.loads(Path(output + ".json").read_text())
            key = next(item for item in report["items"] if item["kind"] == "keyvault-key")
            self.assertEqual(key["name"], raw["key"][0]["kid"])
            self.assertEqual(key["status"], "no-expiry")
            self.assertIn(key["name"], Path(output + ".md").read_text(encoding="utf-8"))
            self.assertEqual(Path(summary).read_text(encoding="utf-8"), Path(output + ".md").read_text(encoding="utf-8"))

    def test_missing_names_do_not_crash_or_change_finding_status(self):
        for value in [None, "", 123]:
            row = {"kind": "keyvault-key", "name": value, "status": "expired", "days": -2}
            rendered = monitor.markdown({"checkedAt": "now", "items": [row]})
            self.assertIn(str(value) if value else "(unnamed)", rendered)
            self.assertIn("expired", rendered)
        self.assertIn("(unnamed)", monitor.markdown({"checkedAt": "now", "items": [{"kind": "tls", "status": "unknown", "days": None}]}))


if __name__ == "__main__":
    unittest.main()
