# App Service cold deployment repair

RavenXpress promotion [41840414671](https://github.com/aexionsolutions/ravenxpress/actions/runs/41840414671)
uploaded and extracted its web package successfully on 4 November 2026. Kudu
reported completion at 13:55:02 UTC. The shared script then requested an extra
restart at 13:55:17, cancelling the startup that had already begun at 13:55:06.
The replacement container's startup probe succeeded at 14:01:25 and the site
started at 14:01:28. Deep HTTP checks still returned 503 until the workflow
failed at 14:04:24. At 14:22, read-only web/deep-web/API probes all returned 200.
No manual restart or redeployment was used to obtain those responses.

Azure Monitor plan samples during 13:45–14:05 showed approximately 99% average
CPU, repeatedly reaching 100%. This is measured resource pressure, not proof of
the exact process consuming it or an application crash. A later ordinary page
request still timed out. A passing health probe is not full UI acceptance. No
capacity/billing change is part of this repair.

The old action used twenty attempts per phase, discarded non-200 response
bodies, and made two separate requests when the first returned 200. It could
record `000000` for a transport timeout. A failed staging warm-up did not prevent
the inline swap command, and a no-slot deployment performed two production
warm-ups. The new helper uses one completed response per attempt and a bounded
20-minute default. Persistent failure still records a marker, collects logs and
fails the composite; it does not convert a failure to success or restart the app.

## Retained files and cache investigation

The promoted ZIP contains 3,507 entries, no `.next/cache` contents, no Oryx
manifest/archive and no prerendered admin paths. Yet the captured startup script
found `node_modules.tar.zst`, extracted it into `/node_modules`, moved aside the
deployed modules directory and linked the expanded modules into the app root.
The archive was on the host rather than shipped in this artifact. The follow-up
run shows Kudu's Node optimizer also creates such archives during deployment, so
its presence alone does not prove it was old. See
[the follow-up investigation](kudu-settings-recycle.md) for this correction and
the confirmed cleanup-command defect in the initial repair.

[Kudu documents](https://github.com/projectkudu/kudu/wiki/Deploying-from-a-zip-file-or-url)
that Linux ZipDeploy restarts the container, that files created outside its
deployment manifest are preserved, and that timestamp-matched copies can be
skipped. `SCM_ZIPDEPLOY_DONOT_PRESERVE_FILETIME=1` forces artifact files to be
updated. The action sets it for extracted Linux packages.

Opt-in Next cleanup removes generated `.next/cache` and known old Oryx artifacts
before extraction. It requires a complete standalone artifact, a confirmed Linux
Node runtime, fixed root and safe cache paths. It preserves compiled page files,
application uploads and real dependency directories. It does not erase the app
root, business data, blob storage or a database. The command's nonzero exit or
HTTP failure prevents upload and produces deployment diagnostics.

The previous platform stale-page evidence proves old HTML was served despite
new chunks being available. Retained files are a credible mechanism, but exact
file/process correlation from that incident is unavailable. Historic stale
customer/driver content is not established. Current artifact inspection shows
some public/client shells are prerendered; forcing artifact replacement protects
those too. PR685's dynamic admin boundary remains useful and is not removed.

## Validation and deployment

Contract tests run the real shell scripts with synthetic curl/Azure responses
and a fake clock, including recovery beyond twenty attempts, a hard wall-clock
deadline, transport/incomplete-200/IIS error responses, failed staging blocking
swaps, Linux/Windows restart ownership and cleanup refusals. Filesystem fixtures
check that uploads and compiled pages survive cleanup; Linux CI also exercises
cache and module symlinks. No live cleanup or deployment is performed by tests.

The consuming RavenXpress PR pins the shared commit exactly and enables cleanup
only for its web package. Review both PRs, then promote web only. No API, database
migration, infrastructure deployment, paid scaling or release tag is required by
the code change. The owner controls merging and promotion. The first live
promotion remains the acceptance check for Kudu cleanup and cold readiness.
