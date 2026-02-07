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
  repo_preset: 'tems'                # ✅ Auto-configures api_port=5000, web_port=3000
  # ⚠️ Database settings must match what TEMS test code (DatabaseHelper.cs) uses:
  database_port: 5434                # REQUIRED (GH Actions limitation)
  postgres_db: 'tems_e2e'            # REQUIRED (test code uses this, not 'Tems_test')
  postgres_user: 'tems_e2e'          # REQUIRED (test code uses this, not 'postgres')
  postgres_password: 'TemsE2e123!'   # REQUIRED (must match test code)
```

This automatically sets:
- API Port: `5000` (instead of default 5100)
- Web Port: `3000` (instead of default 3100)
- **Database settings: Must all match what your `DatabaseHelper.cs` hardcodes**

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
      
      # TEMS preset (auto-configures api_port=5000, web_port=3000)
      repo_preset: 'tems'
      # Database settings must match what DatabaseHelper.cs uses:
      database_port: 5434              # ⚠️ REQUIRED
      postgres_db: 'tems_e2e'          # ⚠️ REQUIRED: Match test code
      postgres_user: 'tems_e2e'        # ⚠️ REQUIRED: Match test code
      postgres_password: 'TemsE2e123!' # ⚠️ REQUIRED: Match test code
      
      # Test configuration
      run_smoke_only: true     # Fast feedback: smoke only in PR
      test_filter: '@smoke'    # Gherkin tag (@ prefix optional, converts to Category=smoke)
      node_version: '20'
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

> **💡 Filter Behavior**: Reqnroll/Gherkin tags (e.g., `@smoke`) become NUnit categories. The workflow automatically converts `@smoke` to `Category=smoke` filter.

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
      
      # TEMS preset + database settings
      repo_preset: 'tems'
      database_port: 5434              # ⚠️ REQUIRED
      postgres_db: 'tems_e2e'          # ⚠️ REQUIRED: Match test code
      postgres_user: 'tems_e2e'        # ⚠️ REQUIRED: Match test code
      postgres_password: 'TemsE2e123!' # ⚠️ REQUIRED: Match test code
      
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

### Database "tems_e2e" does not exist

**Error:** `3D000: database "tems_e2e" does not exist`

**Cause:** Test code hardcodes database name `tems_e2e`, but workflow created database with different name (preset uses `Tems_test`)

**Fix:** Override `postgres_db` to match what test code expects:
```yaml
with:
  repo_preset: 'tems'
  postgres_db: 'tems_e2e'  # ⚠️ REQUIRED: Match DatabaseHelper.cs
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

---

# Part 2: Deployed Environment E2E Tests

## Problem: Too Much Code in promote-release.yml

Your `promote-release.yml` has **~150+ lines** of inline code for E2E tests against deployed environments. This duplicates logic that should be in a reusable workflow.

### ❌ Current Approach (Too Much Code)
```yaml
e2e-deployed:
  runs-on: ubuntu-latest
  steps:
    - name: Download artifact
      # ...
    - name: Extract tests
      # ...
    - name: Setup .NET
      # ...
    - name: Setup Node
      # ...
    - name: Health Check - API
      run: |
        # 15+ lines of bash
    - name: Health Check - Web
      run: |
        # 15+ lines of bash  
    - name: Get database from Key Vault
      run: |
        # 10+ lines of Azure CLI
    - name: Run Reqnroll tests
      run: |
        # 40+ lines of retry logic
    - name: Run Playwright tests
      run: |
        # 20+ lines
    - name: Upload artifacts (multiple steps)
      # ...
```

**Total: ~150+ lines** ❌

---

## ✅ Solution: Use web-e2e-deployed.yml Reusable Workflow

The workflow already exists and handles everything automatically!

### Simplified Code (35 Lines)

```yaml
e2e-deployed:
  name: E2E Tests (Deployed)
  needs: [download-packages, web]
  if: needs.web.result == 'success'
  uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.2.0
  permissions:
    id-token: write  # Required for Azure OIDC
    contents: read
  with:
    # Version Control
    git_ref: ${{ inputs.release_tag }}
    
    # Test Projects
    e2e_project: tests/Ems.E2E/Ems.E2E.csproj
    web_directory: web/tems-portal
    
    # Deployed Environment URLs
    web_url: https://tems-${{ inputs.environment }}-web.azurewebsites.net
    api_url: https://tems-${{ inputs.environment }}-api.azurewebsites.net
    
    # Environment & Database Configuration
    environment_name: ${{ inputs.environment }}
    azure_keyvault_name: tems-${{ inputs.environment }}-kv
    azure_keyvault_secret_name: PostgresConnectionString
    azure_client_id: ${{ secrets.AZURE_CLIENT_ID }}
    azure_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
    azure_subscription_id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    
    # Test Configuration  
    test_filter: '@smoke'
    e2e_retry_attempts: 3
    e2e_enable_video: false
    
    # Infrastructure
    node_version: '20'
    dotnet_version: '10.0.x'
  secrets:
    E2E_TEST_USER_EMAIL: ${{ secrets[format('{0}_E2E_TEST_USER_EMAIL', inputs.environment)] }}
    E2E_TEST_USER_PASSWORD: ${{ secrets[format('{0}_E2E_TEST_USER_PASSWORD', inputs.environment)] }}
    AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
```

**Total: ~35 lines** ✅

---

## What the Reusable Workflow Handles

### ✅ Azure Authentication & Key Vault
- Authenticates to Azure using OIDC (workload identity)
- Retrieves database connection string from Key Vault
- Falls back to service principal if OIDC not configured
- Masks sensitive values in logs

### ✅ Health Checks
- Retries API health endpoint with configurable timeout
- Retries Web health endpoint with configurable timeout
- Supports multiple health endpoint paths (`/healthz`, `/health`, `/`)

### ✅ Test Execution
- Runs Reqnroll tests with retry logic
- Runs Playwright tests with retry logic
- Sets all required environment variables automatically
- Passes database connection string to tests

### ✅ Artifact Management
- Uploads Playwright reports
- Uploads screenshots on failure
- Uploads Reqnroll test results (.trx)
- Uploads videos (if enabled)

### ✅ Test Summary
- Generates GitHub Step Summary
- Shows environment URLs
- Shows test configuration
- Shows results

---

## Steps to Remove from TEMS promote-release.yml

Delete these manual steps from your workflow:

### 1. ❌ Delete: Manual Downloads & Setup
```yaml
- name: Download E2E tests artifact
- name: Extract E2E tests
- name: Setup .NET
- name: Setup Node.js
```

### 2. ❌ Delete: Health Checks (30+ lines)
```yaml
- name: Health Check - API
  run: |
    echo "🏥 Checking API health..."
    timeout=${{ inputs.environment == 'prod' && 600 || 300 }}
    # ... retry logic ...

- name: Health Check - Web
  run: |
    # ... same retry logic ...
```

### 3. ❌ Delete: Key Vault Retrieval (15+ lines)
```yaml
- name: Get database connection string from Key Vault
  id: get_db_conn
  shell: bash
  run: |
    CONN_STR=$(az keyvault secret show ...)
    echo "::add-mask::$CONN_STR"
    echo "connection_string=$CONN_STR" >> $GITHUB_OUTPUT
```

### 4. ❌ Delete: Test Execution with Retry (60+ lines)
```yaml
- name: Run Reqnroll E2E tests
  env:
    RUN_E2E: true
    # ... many env vars ...
  run: |
    attempt=1
    max_attempts=3
    while [ $attempt -le $max_attempts ]; do
      # ... retry logic ...
    done

- name: Run Playwright E2E tests
  run: |
    npm ci
    npx playwright install --with-deps chromium
    npx playwright test --project=chromium --retries=3
```

### 5. ❌ Delete: Artifact Uploads (20+ lines)
```yaml
- name: Upload Playwright report
- name: Upload Playwright screenshots
- name: Upload test results
```

**All of this is handled by the reusable workflow!**

---

## Benefits

| Before | After |
|--------|-------|
| 150+ lines of workflow code | 35 lines of configuration |
| Manual health check logic | Automatic with retries |
| Manual Azure Key Vault integration | Built-in Key Vault support |
| Manual retry logic | Automatic retry with configuration |
| Manual artifact uploads | Automatic uploads |
| Hard to update | Update version tag |
| Inconsistent across repos | Consistent pattern |
| No OIDC support | Built-in OIDC support |

---

## Environment Variable Priority

The reusable workflow sets the database connection string with this priority:

1. **Azure Key Vault** (if `azure_keyvault_name` is set)
2. **Direct input** (`database_connection_string` input)
3. **Secret** (`DATABASE_CONNECTION_STRING` secret)
4. **Not set** (tests use default/local configuration)

---

## Full Example: Complete promote-release.yml

Here's how your simplified `promote-release.yml` should look:

```yaml
name: Promote Release to Environment

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, uat, preprod, prod]
        required: true
      release_tag:
        required: true
      components:
        type: choice
        options: [both, api, web]
        default: both

jobs:
  # ... resolve, download-packages, archived-tests, verify-infrastructure jobs ...
  
  api:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/deploy-template-api.yml@v4.2.0
    # ... api deployment config ...
  
  web:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/deploy-template-web.yml@v4.2.0
    # ... web deployment config ...
  
  # ✅ NEW: Clean E2E tests using reusable workflow
  e2e-deployed:
    name: E2E Tests (Deployed)
    needs: [api, web]
    if: needs.web.result == 'success'
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.2.0
    permissions:
      id-token: write
      contents: read
    with:
      git_ref: ${{ inputs.release_tag }}
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_directory: web/tems-portal
      web_url: https://tems-${{ inputs.environment }}-web.azurewebsites.net
      api_url: https://tems-${{ inputs.environment }}-api.azurewebsites.net
      environment_name: ${{ inputs.environment }}
      azure_keyvault_name: tems-${{ inputs.environment }}-kv
      azure_client_id: ${{ secrets.AZURE_CLIENT_ID }}
      azure_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
      azure_subscription_id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      test_filter: '@smoke'
      e2e_retry_attempts: 3
    secrets:
      E2E_TEST_USER_EMAIL: ${{ secrets[format('{0}_E2E_TEST_USER_EMAIL', inputs.environment)] }}
      E2E_TEST_USER_PASSWORD: ${{ secrets[format('{0}_E2E_TEST_USER_PASSWORD', inputs.environment)] }}
```

---

## Migration Checklist

- [ ] Ensure Azure OIDC is configured (`permissions.id-token: write`)
- [ ] Verify GitHub secrets exist (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, etc.)
- [ ] Update `promote-release.yml` to use reusable workflow
- [ ] Remove all inline E2E test steps (150+ lines)
- [ ] Test in dev environment first
- [ ] Roll out to other environments
- [ ] Document the change in your repo

---

## FAQ

**Q: Do I need to download e2e-tests.zip?**  
A: No! The reusable workflow checks out your repo at the `git_ref` tag, so it uses the test code from that tag directly.

**Q: What about Playwright installation?**  
A: The workflow handles `npm ci` and `npx playwright install --with-deps` automatically.

**Q: Can I use different test filters per environment?**  
A: Yes! Use the `test_filter` input:
- Dev: `@smoke`
- UAT: `@smoke or @regression`  
- Prod: `@critical`

**Q: What if I need custom environment variables?**  
A: The workflow sets the most common ones. If you need more, either:
1. Add them to the reusable workflow (recommended)
2. Create a wrapper job

---

## Consistency with PR CI

Your `pr-ci.yml` already uses reusable workflows:

```yaml
# ✅ PR CI uses reusable workflow
e2e-tests:
  uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.2.0
```

Now `promote-release.yml` follows the same pattern:

```yaml
# ✅ Deployed tests use reusable workflow
e2e-deployed:
  uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.2.0
```

**Consistent patterns = Easier maintenance!** ✅

---

## Next Steps

1. Review the simplified workflow above
2. Update your TEMS `promote-release.yml`
3. Test in dev environment
4. Roll out to other environments
5. Enjoy cleaner workflows! 🎉
