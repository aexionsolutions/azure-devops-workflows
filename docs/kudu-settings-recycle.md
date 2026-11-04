# SCM settings recycle and command execution

RavenXpress's second promotion attempt, run 41870793871 on 4 November 2026,
failed package deployment before HTTP readiness. The new warm-up guard correctly
skipped readiness and retained the package failure.

## Evidence

- Configuration writes finished at 16:51:59 UTC. The fixed 45-second delay did
  not cover the pending SCM recycle.
- Kudu accepted the zip at 16:53:30 and began deployment at 16:55:11. Its command
  executor changed from PID 895 to PID 893 at 16:55:34, during deployment.
- The package job was marked failed at 17:05:15 with SCM-container-restart
  status. Azure Activity Log has no settings/restart mutation in that interval;
  the job's later start operation was at 17:05:23, after the failure.
- Startup repeatedly failed with `Cannot find module 'next'` while the copy was
  incomplete. CPU samples were 91–100% for 16:54–17:00; memory peaked at 83%
  over the collected 16:45–17:10 window. Neither an OOM nor the ultimate reason
  for the SCM process replacement is established by these records. A delayed
  settings recycle is consistent with the timing; it is not proven as the sole
  cause of the process replacement.
- The cleanup response had exit code zero, but its output was the encoded
  script followed by literal pipe arguments. Cleanup never ran. This was a bug
  in the previous repair, whose test double had accepted an empty success.

[Kudu's starter](https://github.com/Azure-App-Service/KuduLite/blob/master/Kudu.Core/Scripts/starter.sh)
executes arguments directly. Pipelines require an explicit shell. The corrected
request uses `bash -c` and validates a completion marker as well as the typed
exit code and error output.

The earlier claim that an archive absent from the uploaded ZIP must be an old
leftover was too strong: this deployment's own log shows Kudu's Node optimizer
creating `node_modules.tar.zst`, then excluding the uncompressed directory from
rsync. An archive alone is not evidence of stale dependencies. The earlier
served-build mismatch is a separate observation; its exact cache origin remains
unproven. A failed in-place copy can leave a partially deployed site.

## Change

The web reusable workflow plans its existing version, environment, auth aliases
and extraction settings together. It reads only relevant keys and writes only
actual differences, in a batch. Starting a stopped target happens before this
configuration phase; a running target is left alone.

Before a Linux settings mutation, it captures the Kudu executor PID and process
start ticks with a read-only command. It waits up to ten minutes for a different
executor identity to respond consistently for ten seconds. Transient failures
and further identity changes reset that stability window. An old process's HTTP
200 does not release the gate. If a separate setting removal is required, its
own recycle is observed after the set operation's recycle, before upload.
Unchanged settings need an available SCM process
but require no recycle. Failures block upload and retain diagnostics.

A job-local, target-specific preparation marker prevents the composite from
writing settings or issuing start/create operations after that gate. API callers
and direct composite callers without this web preparation keep their existing
configuration path; this repair does not claim to fix their settings races.

Cleanup is validated through the real direct-exec shell boundary in contract
tests. Deployment logs use the actual observed deployment ID; `/latest/log`
returned 404 on the failed run. No live mutation, restart, cleanup or promotion
was performed while developing this repair. First live deployment remains
necessary to establish the platform-side acceptance result.

## Follow-up: stdin entry point

Run [41893343103](https://github.com/aexionsolutions/ravenxpress/actions/runs/41893343103)
used stable v6.2.3 on 4 November 2026. Settings preparation reported unchanged
at 19:31:41 UTC. At 19:31:49, cleanup returned exit code 1 and
`bash: line 33: BASH_SOURCE[0]: unbound variable`. Its output was empty. Upload
was correctly blocked; the deployment metadata in the diagnostic artifact
refers to the preceding failed deployment, not a new upload or SCM restart.

The direct-exec transport ran the script, but Bash does not populate
`BASH_SOURCE[0]` for a script read from stdin. The cleanup's strict-mode
entry-point check therefore crashed. Default that missing element to `$0`, so
stdin execution calls cleanup while sourcing a file still only defines the
function. All path/symlink guards and completion validation remain active.

The regression uses the complete production cleanup script through the Kudu
request and direct-exec starter. Only the fixed application-root argument is
substituted with an isolated temporary fixture; the root guards stay enabled.
It fails on v6.2.3 with the exact observed error, then passes with this repair,
checking actual removal, preserved application files, and wrong-root refusal.
Existing sourced-script and symlink tests remain required. This is source
validation, not proof of successful live deployment or manual UI acceptance.
