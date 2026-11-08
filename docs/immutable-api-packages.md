# Immutable Linux .NET API deployment

The API workflow previously set `WEBSITE_RUN_FROM_PACKAGE=1` when requested,
but its composite action deleted that setting before Linux ZIP upload. Thus
an opted-in API still extracted its new DLLs over the running application's
files. Preserve the setting and let Kudu mount the completed ZIP instead.

RavenXpress Dev provides a concrete investigation lead: invalid executable/DLL
metadata errors surfaced while formatting exception stacks during several API
promotions (4, 5 and 7 November 2026). On 7 November they occurred at
09:18:18–09:18:23 UTC, within promotion 42358916300 and before the explicit
09:18:34 restart. These are correlated observations, not a controlled
reproduction proving that every intermittent timeout has this cause.

Microsoft documents why extracted deployment can expose partially updated files:
https://learn.microsoft.com/en-us/azure/app-service/deploy-run-package

## Caller and operational requirements

- Opt in with `run-from-package: 'true'` on the API reusable workflow and pin
  `shared_ref` and the reusable workflow reference to the same reviewed version.
- Linux opt-in requires a confirmed `DOTNETCORE` runtime and no Node cleanup.
  Existing Windows OneDeploy remains supported; Node defaults to extraction.
- API application files become read-only. Keep uploads, keys and generated
  output outside `wwwroot` (for example, the existing blob storage/key services).
- The initial setting change recycles the app. Basic plans have no staging slot;
  coordinate a Dev maintenance interval, then verify API health and version.
  Premium/Standard slot deployment still requires normal warm-up and swap gates.
- Rollback uses the preceding complete package. Deliberately disabling package
  mode requires a reviewed workflow change and a coordinated deployment.

This correction does not resize any plan, raise request timeouts, retry writes,
or establish the cause of operating-time database/application stalls. No live
environment was changed during development of this fix.

Validation: 53/53 deployment contract checks on Linux, including immutable
configuration surviving through upload, rejected runtimes/modes, configuration
failure blocking upload, retained Node extraction and Windows OneDeploy.
