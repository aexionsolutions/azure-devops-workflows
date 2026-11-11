# External ID browser readiness during API promotion

The protected API smoke test signs in through the caller's Microsoft browser
helper. Its preparation installs the caller's locked npm dependencies and matching
Chromium, then launches a headless browser, renders a local synthetic page, and
closes it. A setup or launch failure blocks the job before credentials are used.
The authentication and protected API checks remain mandatory afterwards.

GitHub's Ubuntu hosted image provides the native Chromium libraries. Preparation
does not run apt or install optional font packages on every promotion. If a future
image is missing a required library, the launch probe must fail; fix the image or
dependency preparation rather than suppressing that failure. Downloads and probes
have a four-minute limit per command. CI's Hosted Ubuntu browser readiness job
exercises this path with a minimal fixture, no Azure or identity credentials and
no real sign-in; it does not substitute for deployed authentication acceptance.

## Incident evidence, 11 November 2026

RavenXpress promotion run 43034665754, attempts 1, 2 and 3, failed at Prepare
External ID browser verification. `playwright install --with-deps chromium`
could not resolve `azure.archive.ubuntu.com` when apt tried to fetch optional
fonts. The browser authentication, subsequent health, Swagger and protected smoke
steps did not run. The upload/warmup/version phase succeeded. On the no-slot dev
plan, the phase named Deploy to Staging actually updates the main dev app; a red
verification job therefore does not imply that the previous package is running.

Check health and the deployed artifact's identity read-only before retrying or
rolling back. Release labels and BUILD_VERSION alone do not prove a source SHA.
The C5 live logging check remains separate from deployment verification.

Release this shared change as a new version after merge. Consumer workflows must
update both the reusable workflow's `uses:` tag and `shared_ref` to that release;
do not move an existing tag or pin a temporary PR commit.
