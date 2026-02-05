# TEMS E2E Migration Guide

## Quick Start: Migrate TEMS to Reusable E2E Workflow

This guide helps TEMS migrate from the local PowerShell E2E test script to the reusable `web-e2e-ci.yml` workflow.

---

## ⚠️ CRITICAL Configuration Differences

**TEMS uses different ports and database names than the workflow defaults.**

### Easy Solution: Use the Preset

Use `repo_preset: 'tems'` to auto-configure most settings:

```yaml
with:
  repo_preset: 'tems'              # ✅ Auto-configures ports 5000/3000, database 'Tems_test'
  database_port: 5434              # ⚠️ REQUIRED: Must be set explicitly (GitHub Actions limitation)
  postgres_user: 'tems_e2e'        # ⚠️ REQUIRED: TEMS uses custom username
  postgres_password: 'tems_e2e_pw' # ⚠️ REQUIRED: Must match what TEMS test code expects
```

This automatically sets:
- API Port: `5000` (instead of default 5100)
- Web Port: `3000` (instead of default 3100)  
- Database: `Tems_test` (instead of default e2e_test)
- **Database Port: Must be set to `5434` explicitly** (preset can't control service ports)
- **Username/Password: Must match what your test code uses** (TEMS uses `tems_e2e`/`tems_e2e_pw`)

### Settings Reference

| Setting | Workflow Default | TEMS Value | How to Set |
|---------|------------------|------------|------------|
| API Port | 5100 | **5000** | `api_port: 5000` |
| Web Port | 3100 | **3000** | `web_port: 3000` |
| Database | `e2e_test` | **`Tems_test`** | `postgres_db: 'Tems_test'` |

**If you don't use the preset or manual overrides, tests will fail with "Connection refused" errors.**

---

## Step 1: Update PR Workflow

Replace your current E2E job with:

```yaml
# .github/workflows/pr-ci.yml
name: PR CI

on:
  pull_request:
    branches: [main]

jobs:
  # Backend: Unit + Integration tests
  api-ci:
    name: API CI (Unit + Integration)
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.0.1
    with:
      solution: Ems.sln
      run_integration: true
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      js_lcov_path: web/tems-portal/coverage/lcov.info
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/.github/workflows/**,**/Program.cs'
      sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/*.config.{ts,js,mjs},web/tems-portal/vitest.{config,setup}.ts,web/tems-portal/tests/**'
      sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**'
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.head_ref }}
      pr_base: ${{ github.base_ref }}
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_ORG: ${{ secrets.SONAR_ORG }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}

  # Frontend: Unit tests + Build verification
  web-ci:
    name: Web CI (Unit + Build)
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-ci.yml@v4.0.1
    with:
      working_directory: web/tems-portal
      run_tests: true
      node_version: '20'

  # E2E: Smoke tests only (fast feedback)
  web-e2e:
    name: Web E2E (Smoke Tests)
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.2.0
    with:
      # Required inputs
      solution: TEMS.sln
      api_project: backend/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      
      # TEMS preset (auto-configures ports 5000/3000 and database Tems_test)
      repo_preset: 'tems'
      database_port: 5434            # ⚠️ REQUIRED: Preset can't control service ports
      postgres_user: 'tems_e2e'      # ⚠️ REQUIRED: TEMS uses custom username
      postgres_password: 'tems_e2e_pw'  # ⚠️ REQUIRED: Must match TEMS test code
      
      # Test configuration
      run_smoke_only: true     # Fast feedback: smoke only in PR
      test_filter: '@smoke'    # Only run @smoke tagged scenarios
      node_version: '20'
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

---

## Step 2: Create Deployment E2E Workflow (Optional)

For full E2E regression after deployment:

```yaml
# .github/workflows/e2e-full.yml
name: Full E2E Regression

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to test'
        required: true
        type: choice
        options:
          - dev
          - staging
          - prod

jobs:
  e2e-full:
    name: Full E2E Regression
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.2.0
    with:
      solution: TEMS.sln
      api_project: backend/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      
      # TEMS preset + database port
      repo_preset: 'tems'
      database_port: 5434              # ⚠️ REQUIRED: Preset can't control service ports
      postgres_user: 'tems_e2e'        # ⚠️ REQUIRED: TEMS uses custom username
      postgres_password: 'tems_e2e_pw' # ⚠️ REQUIRED: Must match TEMS test code
      
      run_smoke_only: false      # Run ALL tests
      e2e_retry_attempts: 2      # Retry flaky tests
      e2e_enable_video: true     # Capture videos for debugging
      
      # Optional: Custom seed data
      seed_data_script: tests/e2e-seed-data.sql
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

---

## Step 3: Tag Your Scenarios

Ensure your Reqnroll/SpecFlow scenarios are tagged:

```gherkin
@smoke @critical
Scenario: User can log in
  Given I am on the login page
  When I enter valid credentials
  Then I should see the dashboard

@smoke
Scenario: Health check passes
  Given the API is running
  When I check the health endpoint
  Then it should return healthy

@regression @orders
Scenario: User can create an order
  Given I am logged in as dispatcher
  When I create a new parcel delivery order
  Then the order should appear in the orders list
```

**PR runs:** Only `@smoke` scenarios (~3-5 minutes)  
**Full runs:** All scenarios (~15-20 minutes)

---

## Step 4: Configure GitHub Secrets

Generate and add JWT signing key:

```bash
# Generate a secure key
openssl rand -base64 48

# Add to GitHub: Settings > Secrets > Actions
# Name: E2E_JWT_SIGNING_KEY
# Value: <paste-generated-key>
```

---

## Comparison: Local Script vs Workflow

| Feature | Local Script | Reusable Workflow |
|---------|--------------|-------------------|
| Docker Services | Manual setup | ✅ Automatic (PostgreSQL + Azurite) |
| API Port | 5000 | ✅ 5000 (via `repo_preset: 'tems'`) |
| Web Port | 3000 | ✅ 3000 (via `repo_preset: 'tems'`) |
| Database Port | 5434 | ✅ 5434 (via `database_port: 5434` input) |
| Database Name | `Tems_test` | ✅ `Tems_test` (via preset) |
| API Build | Manual | ✅ Automatic |
| Videos | Local only | ✅ Optional CI (`e2e_enable_video: true`) |
| Cleanup | Manual | ✅ Automatic |

---

## Benefits

✅ **Consistent** - Same environment every time (no "works on my machine")  
✅ **Fast** - Smoke tests in PRs give quick feedback (~3-5 min)  
✅ **Comprehensive** - Full suite available for deployment validation  
✅ **Debuggable** - Screenshots, videos, logs automatically uploaded  
✅ **Retryable** - Handles flaky tests with configurable retry logic  
✅ **Maintainable** - Updates to workflow benefit all repos  

---

## Troubleshooting

### Tests fail with "Connection Refused"

**Cause:** Port mismatch

**Fix:** Use the TEMS preset:
```yaml
with:
  repo_preset: 'tems'  # Auto-configures correct ports
```

Or verify manual overrides match your configuration:
```yaml
with:
  api_port: 5000  # Must match appsettings.json
  web_port: 3000  # Must match test expectations
```

### Database not found

**Cause:** Database name mismatch

**Fix:** Use the TEMS preset (includes database name):
```yaml
with:
  repo_preset: 'tems'
  database_port: 5434  # Don't forget this!
```

### PostgreSQL connection refused (port 5434)

**Error:** `Failed to connect to 127.0.0.1:5434 - Connection refused`

**Cause:** `database_port` not set (GitHub Actions limitation - preset can't control service ports)

**Fix:** Explicitly set `database_port` as an input:
```yaml
with:
  repo_preset: 'tems'
  database_port: 5434  # ⚠️ REQUIRED for TEMS
```

### Password authentication failed for user "tems_e2e"

**Error:** `28P01: password authentication failed for user "tems_e2e"`

**Cause:** TEMS tests use custom PostgreSQL username/password (`tems_e2e`/`tems_e2e_pw`), but workflow defaults are `postgres`/`test_password_e2e_123`

**Fix:** Explicitly set both `postgres_user` and `postgres_password`:
```yaml
with:
  repo_preset: 'tems'
  postgres_user: 'tems_e2e'        # Match what TEMS test code uses
  postgres_password: 'tems_e2e_pw' # Match what TEMS test code uses
```

> 💡 **Tip**: Ensure your test code uses the `E2E_DATABASE_CONNECTION_STRING` environment variable provided by the workflow instead of building its own connection string.

**Fix:** Explicitly set `postgres_user`:
```yaml
with:
  repo_preset: 'tems'
  database_port: 5434
  postgres_user: 'tems_e2e'  # ⚠️ REQUIRED for TEMS
```

### Tests expect different environment variables

**Cause:** Local script uses different var names

**Fix:** The workflow sets standard variables. Update test code if needed:
- `E2E_BASE_URL` → Web URL
- `E2E_API_BASE_URL` → API URL (if needed separately)
- `E2E_DATABASE_CONNECTION_STRING` → Database connection

### Migrations don't run

**Cause:** API doesn't run migrations in Development mode

**Fix:** Ensure your `Program.cs` checks for `ENABLE_TEST_MIGRATIONS`:
```csharp
if (app.Environment.IsDevelopment() && 
    !bool.Parse(configuration["SkipDatabaseMigrations"] ?? "false"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}
```

---

## Next Steps

1. ✅ Tag scenarios with `@smoke` for PR runs
2. ✅ Generate and configure `E2E_JWT_SIGNING_KEY` secret
3. ✅ Update PR workflow with correct port overrides
4. ✅ Test with a PR to verify smoke tests run successfully
5. ✅ Create full E2E workflow for deployment validation

---

## Support

- **Workflow Docs:** [web-e2e-ci-guide.md](web-e2e-ci-guide.md)
- **Issues:** [azure-devops-workflows repository](https://github.com/aexionsolutions/azure-devops-workflows/issues)
