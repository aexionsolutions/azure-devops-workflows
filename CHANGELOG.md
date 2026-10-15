# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`dotnet-test-retry`: a failure stays a failure until the test passes.**
  A retry that exited 0 was trusted as success, and the TRX merge let a later
  result replace an earlier one, so a test that failed and was then only
  skipped (for example by an exhausted provider quota) turned the gate green
  without ever passing. RavenXpress #603 did exactly that: a 403 failure, then
  a Paystack quota skip on retry, reported success. The action now tracks every
  failure until a retry reports it Passed; the run passes only when none
  remain, and the merge never replaces a failure with a skip, so its evidence
  stays. Pester tests now run the real script end to end against a fake
  `dotnet` (failure → quota skip fails, also when the retry exits non-zero;
  failure → pass passes; a first-attempt quota skip is neither retried nor
  failed); on the v4.15.0 script the first of these fails.

### Added

- **Integration build-once pilot (opt-in):** `dotnet-ci.yml` accepts
  `integration_build_once` (default false). A `build-integration-tests` job
  builds the integration test project once and shares its output folder (with
  the referenced coverlet collector copied beside the test assembly); each
  integration shard downloads it and runs `dotnet test` on the assembly instead
  of restoring and building the whole solution. The unit-test job still builds
  for itself, so the critical path does not wait for the upload. Discovery
  count guard, coverage and TRX checks are unchanged. To be measured before any
  caller turns it on for good.

- **Playwright failure limit:** `web-e2e-ci.yml` and `web-e2e-deployed.yml`
  accept `playwright_max_failures` (default 10; 0 disables), passed as
  `npx playwright test --max-failures`. The `playwright-smoke` action accepts
  `max-failures` (default 10) for both smoke scripts. The limit counts tests
  still failing after their retries (Playwright 1.48+), so with 2 retries a
  limit of 10 allows about 30 failed runs; tests already running finish. It
  applies per Playwright job, so per shard. A broken build used to run every
  test to its timeout on every retry (one RavenXpress run: 47+ minutes against
  about 9 normally).
- **Job timeouts:** every job in `dotnet-ci.yml`, `web-ci.yml` and
  `web-e2e-ci.yml` now has `timeout-minutes` (previously GitHub's 6-hour
  default). Long-running jobs take `job_timeout_minutes` (default 45 in
  `dotnet-ci.yml` and `web-e2e-ci.yml`, 30 in `web-ci.yml`); fan-in and
  planning jobs have fixed short limits.
- **Coverage file exclusion at collection time:** `dotnet-ci.yml` accepts
  `coverage_exclude_by_file` (coverlet `ExcludeByFile` globs, e.g.
  `**/Migrations/*.cs`) for the unit and integration runs. Unlike Sonar's
  coverage exclusions, excluded files are never instrumented.
- **Node version for web unit tests:** `dotnet-ci.yml` accepts `node_version`
  (default `'20'`) for `web-unit-tests` and Sonar, which were hardcoded to 20.
- **Provider-quota skips in `dotnet-test-retry`:** a test marked inconclusive
  with a message starting `[provider-quota]` (an external provider's quota is
  exhausted, as proved by the provider's response) is no longer retried or
  counted as a failure. It is reported separately instead: a warning, a
  job-summary section and the `provider-quota-skipped-count` output. Before,
  one real failure triggered retries of every such skip, which hit the same
  exhausted quota again and were counted as "final failed tests" (one
  RavenXpress run reported 21 for 1 failure and 20 skips). Setup errors
  without the marker are still retried. Selection moved to `TrxSelection.ps1`,
  with Pester tests run by the new `action-tests.yml`.

- **Parallel E2E suites (opt-in):** `web-e2e-ci.yml` accepts `parallel_suites`
  and `playwright_shards`. With `parallel_suites: true`, Reqnroll and
  Playwright run as separate parallel jobs (each with its own PostgreSQL,
  Azurite, API and web) and Playwright can be split across up to eight shards.
  Defaults keep the single sequential `E2E Tests` job and its artifact names.

- **Scheduled environment stop guard:** Reusable action prevents automatic
  shutdown outside a bounded local-time window or while Start Environment or
  release-promotion workflows are active.
- **App Service deployment diagnostics:** Package deployment now uses bounded Azure CLI/Kudu polling instead of `azure/webapps-deploy`, with a 40-minute default deploy timeout and `appservice-logs-<app-name>` diagnostics on deploy or warm-up failures.
- **Web deployment auth settings:** `deploy-template-web.yml` can apply runtime B2C web auth settings before deployment, using `secrets.b2c_web_client_id` as the preferred web app client ID and `b2c_client_id` as a fallback.
- **Bounded Playwright setup:** Deployed E2E runs now support `playwright_install_timeout_minutes`, install only the browser dependencies needed by the selected browser project, and avoid reinstalling Linux dependencies for Reqnroll when web Playwright already installed them.
- **Server-side Maps E2E configuration:** `web-e2e-ci.yml` accepts the optional `google_maps_platform_server_api_key` secret and enables `GoogleMapsPlatform` only when that credential—or the backwards-compatible `GoogleMapsPlatform__ServerApiKey` entry in `e2e_secrets`—is present.

### Changed

- **`web-e2e-ci.yml`: each suite has its own job definition.** The Reqnroll
  and Playwright suites used to share one matrix job whose steps were switched
  on and off per leg, so every job listed the other suite's steps as skipped.
  Now there are three jobs: `E2E Tests` (parallel_suites off: every suite in
  sequence, as before), `E2E Tests (reqnroll)` and `E2E Tests (playwright…)`
  (one per shard). They share their setup, suite runners and teardown as
  composite actions (`e2e-start-stack`, `e2e-run-reqnroll`,
  `e2e-run-playwright`, `e2e-stop-stack`), so each job lists only what it runs.
  Check names, artifact names and inputs are unchanged. Reqnroll still installs
  Microsoft.Playwright's browsers; only the JavaScript Playwright suite's steps
  left its job.
- **Web installs use the committed lockfile:** `web-ci.yml` and
  `dotnet-ci.yml`'s `web-unit-tests` run `npm ci` when a `package-lock.json`
  exists, instead of deleting it and running `npm install`. Resolving afresh
  tested a different dependency tree on every run and broke whenever the
  registry did: on 2026-10-15 every RavenXpress run failed in 20 seconds with
  `Cannot read properties of null (reading 'edgesOut')`, reproduced in a clean
  `node:20` container from `package.json` alone. RavenXpress's lockfile holds
  the Linux native bindings (rolldown, Next SWC, sharp, Tailwind oxide), so
  `npm ci` installs and runs Vitest there; the E2E jobs already used it.
- **`web-ci.yml` no longer installs Playwright browsers:** its test step runs
  `npm test` (unit tests); browser tests belong to `web-e2e-ci.yml`. The
  install was skipped in PR runs and wasted minutes in release runs.
- **Faster PR feedback from `dotnet-ci.yml`:** web vitest + coverage now runs in
  its own `web-unit-tests` job in parallel with `build-and-unit-tests`, which
  used to run them one after the other. Sonar waits for it and consumes the same
  `web-coverage` artifact.
- **Shallow clones where history is unused:** integration-test shards and the
  full-stack E2E job no longer fetch the caller's full git history (~45 s per
  shard, ~96 s per E2E job in RavenXpress). `build-and-unit-tests` (PR diff)
  and Sonar (blame) keep full history.
- **Deployed Reqnroll default filter:** `web-e2e-deployed.yml` now defaults to `@deployed-smoke`; simple tags map to both `Category` and `TestCategory`, while explicit VSTest filters are passed through unchanged.
- **Playwright smoke action:** Browser install and system dependency install are split into separate timed steps with launch probing before Linux dependency installation.

### Fixed

- **Stable release tag selection:** Version detection now excludes reachable
  prerelease tags and rejects malformed stable tags before calculating a bump,
  preventing a merged PR from becoming a successful release no-op.
- **RavenXpress payment-return E2E profile:** `web-e2e-ci.yml` now derives the
  server-owned web callback profile from the resolved local web port when the
  RavenXpress preset is active, while preserving explicit caller overrides.
- **Smart Test Retry:** Intentional deployed-safety `NotExecuted` skips are ignored by retry selection so skipped non-`@deployed-smoke` scenarios do not trigger needless retries.

#### Smart Test Retry: NotExecuted/Inconclusive TRX outcomes now tracked (v4.4.0)

**Context:** TRX summary numbers didn't add up — `total` exceeded `passed + failed + error`. Tests that failed in `[BeforeScenario]` hooks (e.g., transient 500 from tenant creation API) were recorded as `NotExecuted` in TRX but the script didn't track that outcome, leaving tests unaccounted for in summaries and — critically — not retried.

- **Fixed:** `Get-TrxCounters` and `Get-TrxSummary` now read `notExecuted` and `inconclusive` attributes from TRX `<Counters>` element
- **Fixed:** `Merge-TrxResults` counter recalculation now counts all 7 outcome types (`Passed`, `Failed`, `Error`, `NotExecuted`, `Inconclusive`, `Aborted`, `Timeout`) instead of only 3; `executed` attribute is now correctly set to `total - notExecuted - inconclusive` instead of `total`
- **Fixed:** `Get-FailedFQNsFromTrx` now includes `NotExecuted` outcome in XPath selector, so tests where `[BeforeScenario]` hooks threw transient errors are retried
- **Improved:** Summary log lines now show `notExecuted=N` and `inconclusive=N` when non-zero, making gaps immediately visible

### 🚨 Breaking Changes

#### Smart Test Retry: Rewritten with Robust PowerShell Implementation

**Context:** Previous bash implementation had critical correctness issues with TRX parsing and filter syntax that would cause retry to fail silently or not retry failed tests correctly.

- **IMPROVED:** `.github/actions/dotnet-test-retry` now uses PowerShell Core (`pwsh`) for reliable operation
  - Fixed: TRX parsing now uses proper XML DOM with XPath (maps `testId` → `TestMethod className.name`)
  - Fixed: Filter syntax now builds correct OR expressions: `(FullyQualifiedName="A") | (FullyQualifiedName="B")`
  - Fixed: Eliminated `eval` command and shell injection risks
  - Fixed: Properly handles test names with quotes, parentheses, ampersands, pipes
  - Before: Used grep with O(n²) complexity, unreliable `testName` matching, broken filter syntax `FullyQualifiedName~A|B|C`
  - After: Uses XML DOM parsing (O(n)), stable FQN mapping, correct dotnet test filter syntax
  
- **BREAKING:** `additional-args` input must not be wrapped in quotes
  ```yaml
  # Before (WRONG - will break)
  additional-args: --logger "console;verbosity=normal"
  
  # After (CORRECT)
  additional-args: --logger console;verbosity=normal
  ```
  - Reason: PowerShell splits on whitespace; quotes would be treated as part of the argument value
  
- **Migration:** 
  - If you call `.github/actions/dotnet-test-retry` directly: remove outer quotes from `additional-args`
  - If you only call `web-e2e-deployed.yml` or `web-e2e-ci.yml`: no changes needed (already fixed)
  - PowerShell Core (`pwsh`) is available on all GitHub-hosted runners by default

- **Added**: New composite action `.github/actions/dotnet-test-retry` for reusable smart test retry logic

### Fixed

- **web-e2e-deployed.yml & web-e2e-ci.yml: Environment variables now properly passed to test runs** (#TBD)
  - Fixed: Environment variables (E2E_BASE_URL, B2C_AUTHORITY, ConnectionStrings__, etc.) now set on composite action step with `env:` block
  - Fixed: Step naming clarified - "Prepare Reqnroll E2E tests" for setup, "Run Reqnroll E2E tests" for actual execution
  - Before: Environment variables set in logging step were not inherited by composite action, causing tests to fail or use wrong configuration
  - After: Environment variables properly scoped to test execution step
  - Impact: E2E tests now receive correct environment configuration (base URLs, auth tokens, connection strings, B2C config)

See [.github/actions/dotnet-test-retry/README.md](.github/actions/dotnet-test-retry/README.md) for full implementation details and correctness guarantees.

#### web-e2e-deployed.yml: Azure Credentials Now Passed as Secrets

**Context:** Azure credentials were inconsistently defined as inputs in `web-e2e-deployed.yml` but as secrets in `deploy-template-web.yml` and `deploy-template-api.yml`.

- **BREAKING:** `azure_client_id`, `azure_tenant_id`, `azure_subscription_id` changed from **inputs** to **secrets**
  - Before: Passed in `with:` block as inputs (incompatible with reusable workflow secret passthrough rules)
  - After: Passed in `secrets:` block (consistent with other deployment workflows)
  - Reason: GitHub Actions doesn't allow `secrets.*` context in reusable workflow `with:` block. Using secrets block matches pattern in deploy-template-web.yml and deploy-template-api.yml.
  
- **Migration:** In your calling workflows, move these three parameters from `with:` to `secrets:`:
  ```yaml
  # Before
  with:
    azure_client_id: ${{ secrets.AZURE_CLIENT_ID }}
    azure_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
    azure_subscription_id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  secrets:
    AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
  
  # After
  with:
    # (removed azure credentials from here)
  secrets:
    AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
    AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
  ```

#### All Repo-Specific Paths Now Required (No Defaults)

**Philosophy Change:** Explicit configuration over implicit defaults for fail-safe multi-repo compatibility.

##### dotnet-ci.yml
- **BREAKING:** `js_lcov_path` now **required** (was optional with auto-construction)
  - Before: Auto-constructed from `web_working_directory` (could fail silently)
  - After: Must explicitly provide path (e.g., `web/tems-portal/coverage/lcov.info`)
  - Reason: Prevents silent failures when path wrong, works for any repo structure
  
- **BREAKING:** `sonar_exclusions` now **required** (was hardcoded with TEMS paths)
  - Before: Hardcoded `infra/tems-infra/azure/modules/**/*.bicep` etc.
  - After: Caller must provide comma-separated exclusion patterns
  - Reason: Generic for any repo (TEMS, RavenXpress, etc.)
  
- **BREAKING:** `sonar_coverage_exclusions` now **required** (was hardcoded with TEMS paths)
  - Before: Hardcoded `web/tems-portal/vitest.config.ts`, `web/tems-portal/tests/**` etc.
  - After: Caller must provide patterns matching their structure
  - Reason: Different repos have different config file locations
  
- **ADDED:** `sonar_infra_exclusions` - Optional infrastructure-specific exclusions
  - Use for repo-specific infra paths (e.g., `infra/tems-infra/**/*.bicep`)

##### web-deploy.yml
- **BREAKING:** `concurrency_group` now **required** (was hardcoded as `tems-web-build`)
  - Before: All repos used same group (could block each other)
  - After: Must provide unique group name per repo (e.g., `tems-web-build`, `ravenxpress-web-build`)
  - Reason: Prevents cross-repo concurrency conflicts
  
- **BREAKING:** Removed all `web_directory || 'web/tems-portal'` fallbacks
  - Before: Defaulted to TEMS structure if not provided
  - After: Fails fast if `web_directory` not provided
  - Reason: Explicit is better than implicit

##### api-deploy.yml
- **BREAKING:** `concurrency_group` now **required** (was hardcoded as `tems-api-build`)
  - Before: Hardcoded TEMS-specific group name
  - After: Must provide unique group name per repo
  - Reason: Multi-repo compatibility

##### sonar-dotnet-begin action
- **BREAKING:** All inputs now required (removed defaults)
  - `js_lcov`: Must provide explicit path
  - `sonar_exclusions`: Must provide explicit patterns
  - `sonar_coverage_exclusions`: Must provide explicit patterns
- **ADDED:** Dynamic exclusion building with optional infra paths
- **REMOVED:** All TEMS-specific hardcoded paths from line 73-74

### Fixed
- SonarCloud 0.0% coverage issue (hardcoded `tems-web/coverage/lcov.info` didn't match actual path)
- Multi-repo compatibility issues (RavenXpress couldn't use shared workflows)
- Silent path failures (now fail fast with clear errors)

### Added
- Comprehensive README with configuration examples for different repos
- Self-documenting caller workflows (explicit inputs show repo structure)

### Migration Required
**All calling repos (TEMS, RavenXpress) MUST update workflows before upgrading to v3.2.0**

See the README and docs/usage-guide.md for migration guidance.

**Quick Summary for TEMS:**
```yaml
# Add these required inputs to pr-ci.yml:
js_lcov_path: web/tems-portal/coverage/lcov.info
sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/.github/workflows/**,**/Program.cs'
sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/*.config.{ts,js,mjs},web/tems-portal/vitest.{config,setup}.ts,web/tems-portal/tests/**'
sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**,setup-oidc.ps1'

# Add to web-deploy.yml:
concurrency_group: tems-web-build

# Add to api-deploy.yml:
concurrency_group: tems-api-build
```

---

## [1.0.0] - 2026-01-10

### Added

#### Workflows
- **azure-infra-deploy.yml**: Azure infrastructure deployment using Bicep
  - OIDC authentication with Azure
  - Automatic PostgreSQL server management (start/stop/wait)
  - Key Vault RBAC auto-configuration
  - Resource provider registration (PostgreSQL, Application Insights)
  - Secret validation before deployment
  - Comprehensive error reporting
  
- **dotnet-ci.yml**: .NET CI with testing and quality gates
  - Build and test .NET solutions
  - Code coverage with threshold enforcement
  - Integration test support (PostgreSQL + Azurite services)
  - Playwright E2E test support
  - SonarCloud integration with PR decoration
  - Artifact uploads (coverage reports, test results)
  
- **web-ci.yml**: Web CI for React/Next.js applications
  - Lint, test, and build workflows
  - npm and pnpm support
  - Playwright browser automation
  - Build artifact uploads

#### Documentation
- Complete usage guide with examples
- Parameters reference for all workflows
- Migration guide from inline workflows
- Azure OIDC setup instructions
- Real-world examples from TEMS project

#### Scripts
- Repository initialization automation removed (no longer maintained)
- `setup-azure-federated-credentials.ps1`: Azure OIDC credential setup

### Features

- 🔐 OIDC authentication (no long-lived secrets)
- 🚀 Reusable across multiple projects
- 📦 Versioned releases for stability
- 📚 Comprehensive documentation
- ✅ Production-tested with TEMS project

### Breaking Changes

None (initial release)

---

## Release Notes Template

Use this template for future releases:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features or workflows

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security improvements
```
