"""Metadata-only expiry monitoring. Never retrieves secret values or private keys."""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import socket
import ssl
import subprocess
import shutil
import sys

UTC = dt.timezone.utc


def classify(expires, now):
    if not expires:
        return "unknown", None
    end = dt.datetime.fromisoformat(expires.replace("Z", "+00:00"))
    days = math.floor((end - now).total_seconds() / 86400)
    for limit, status in [(0, "expired"), (7, "urgent"), (14, "14-days"),
                          (30, "30-days"), (60, "60-days")]:
        if (limit == 0 and days < 0) or (limit != 0 and days <= limit):
            return status, days
    return "healthy", days


def az(*args):
    # Deliberately omit stderr: provider errors can contain sensitive context.
    executable = [sys.executable, "-IBm", "azure.cli"] if os.name == "nt" and "CLI2" in sys.executable else [shutil.which("az") or "az"]
    result = subprocess.run([*executable, *args, "--only-show-errors", "-o", "json"],
                            capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError("Azure metadata query failed; check identity and read permissions")
    return json.loads(result.stdout)


def tls_expiry(host):
    # Default trust store, hostname validation and SNI; no insecure fallback.
    with socket.create_connection((host, 443), timeout=15) as connection:
        with ssl.create_default_context().wrap_socket(connection, server_hostname=host) as secure:
            value = secure.getpeercert()["notAfter"]
    return dt.datetime.fromtimestamp(ssl.cert_time_to_seconds(value), UTC).isoformat()


def collect(config, azure=False):
    now = dt.datetime.now(UTC)
    rows = []

    def add(kind, name, expiry, **extra):
        status, days = classify(expiry, now)
        rows.append(dict(kind=kind, name=name, expires=expiry, days=days, status=status, **extra))

    def guarded(kind, name, action):
        try:
            action()
        except Exception as error:
            rows.append(dict(kind=kind, name=name, status="unavailable", expires=None, days=None,
                             errorType=type(error).__name__))

    for host in config.get("hosts", []):
        guarded("tls", host, lambda host=host: add("tls", host, tls_expiry(host)))

    if azure:
        for app in config.get("applications", []):
            def credentials(app=app):
                data = az("ad", "app", "show", "--id", app,
                          "--query", "{name:displayName,passwords:passwordCredentials[].{id:keyId,end:endDateTime},certificates:keyCredentials[].{id:keyId,end:endDateTime}}")
                for kind, key in [("entra-secret", "passwords"), ("entra-certificate", "certificates")]:
                    for item in data.get(key) or []:
                        add(kind, f"{data['name']}/{item['id']}", item.get("end"))
                if not data.get("passwords") and not data.get("certificates"):
                    rows.append(dict(kind="entra", name=data["name"], status="no-expiring-credentials", expires=None, days=None))
            guarded("entra", app, credentials)

        for subscription in config.get("subscriptions", []):
            def resources(subscription=subscription):
                certificates = az("resource", "list", "--subscription", subscription,
                                  "--resource-type", "Microsoft.Web/certificates", "--query", "[].id")
                for certificate in certificates:
                    def inspect_certificate(certificate=certificate):
                        cert = az("resource", "show", "--ids", certificate, "--api-version", "2023-12-01",
                                  "--query", "{name:name,end:properties.expirationDate}")
                        add("appservice-certificate", certificate, cert.get("end"))
                    guarded("appservice-certificate", certificate, inspect_certificate)
                vaults = az("keyvault", "list", "--subscription", subscription, "--query", "[].name")
                for vault in vaults:
                    for kind in ["secret", "key", "certificate"]:
                        def items(vault=vault, kind=kind):
                            values = az("keyvault", kind, "list", "--vault-name", vault,
                                        "--query", "[?attributes.enabled!=`false`].{id:id,end:attributes.expires}")
                            for item in values:
                                add(f"keyvault-{kind}", item["id"], item.get("end"))
                        guarded(f"keyvault-{kind}", vault, items)
            guarded("subscription", subscription, resources)
    return {"checkedAt": now.isoformat(), "azureRequested": azure, "items": rows}


def markdown(report):
    lines = ["# Certificate and credential expiry", "", f"Checked: {report['checkedAt']}", "",
             "Statuses include 60/30/14/7-day warnings. Unknown expiry and unavailable checks require investigation.",
             "This report contains metadata only. GitHub secret values and external-provider credentials are not inspected.", "",
             "| Type | Resource | Status | Days remaining |", "|---|---|---|---|"]
    for item in report["items"]:
        name = item["name"].replace("|", "\\|").replace("\n", " ").replace("\r", " ")
        lines.append(f"| {item['kind']} | {name} | {item['status']} | {item['days'] if item['days'] is not None else '—'} |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--azure", action="store_true")
    parser.add_argument("--output", default="expiry-report")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    if not config.get("hosts") and not (args.azure and config.get("applications")) and not (args.azure and config.get("subscriptions")):
        parser.error("At least one monitoring target is required")
    report = collect(config, args.azure)
    Path(args.output + ".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    rendered = markdown(report)
    Path(args.output + ".md").write_text(rendered, encoding="utf-8")
    if os.getenv("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(rendered)
    print(rendered)
    return int(any(item["status"] not in {"healthy", "no-expiring-credentials"} for item in report["items"]))


if __name__ == "__main__":
    raise SystemExit(main())
