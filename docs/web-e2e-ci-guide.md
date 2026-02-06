# Web E2E CI Workflow Guide

## Overview

The `web-e2e-ci.yml` reusable workflow provides comprehensive end-to-end testing for applications with both web and API components. It spins up a complete testing environment including:

- **PostgreSQL** - Database service in Docker
- **Azurite** - Azure Blob Storage emulator (optional)
- **API Server** - Built from your .NET project
- **Web Server** - Built from your Next.js/React project
- **Test Runners** - Supports both Reqnroll (SpecFlow) and Playwright

## Key Features

✅ **Full Stack Testing** - Real API + Web + Database (not mocked)  
✅ **Reqnroll Support** - Run BDD tests with tag-based filtering  
✅ **Playwright Support** - Run browser-based E2E tests  
✅ **Smoke Mode** - Fast feedback with smoke tests only in PRs  
✅ **Test Retry** - Configurable retry logic for flaky tests  
✅ **Video Recording** - Optional video capture for debugging  
✅ **Azurite Emulator** - Test Azure Blob Storage operations locally  
✅ **Flexible Seeding** - Custom SQL seed scripts  
✅ **No Defaults** - Explicit configuration prevents silent failures  

---

## Basic Usage

> **⚠️ CRITICAL: Port & Database Configuration**
>
> The workflow defaults are optimized for **RavenXpress** (ports 5100/3100, database `e2e_test`).
>
> **TEMS users:** Use the `repo_preset` input for automatic configuration:
> ```yaml
> with:
>   repo_preset: 'tems'        # Auto-configures ports 5000/3000, database 'Tems_test'
>   database_port: 5434        # ⚠️ REQUIRED for TEMS (GitHub Actions can't set service ports via preset)
>   postgres_user: 'tems_e2e'  # ⚠️ REQUIRED if tests use custom username (default: 'postgres')
> ```
>
> Alternatively, override manually:
> ```yaml
> with:
>   api_port: 5000
>   web_port: 3000
>   postgres_db: 'Tems_test'
> ```
>
> See [Repository-Specific Configuration](#repository-specific-configuration) below for examples.

### Minimum Required Inputs

```yaml
jobs:
  e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
```

This will:
- Build the API from the specified project
- Start API on port 5100 with PostgreSQL on 5432 (RavenXpress defaults)
- Build and start Next.js on port 3100
- Run Playwright smoke tests only (default)

---

## Common Scenarios

### 1. PR Smoke Tests (Fast Feedback)

```yaml
# .github/workflows/pr-ci.yml
name: PR CI

on:
  pull_request:
    branches: [main]

jobs:
  web-e2e:
    name: E2E Smoke Tests
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      run_smoke_only: true  # ⚡ Fast: Only @smoke tagged tests
      test_filter: '@smoke'
      node_version: '20'
```

**Duration:** ~3-5 minutes  
**Tests Run:** Only tests tagged with `@smoke` in Reqnroll + Playwright smoke.spec.ts

---

### 2. Full Regression Suite (Deployment)

```yaml
# .github/workflows/deploy-staging.yml
name: Deploy to Staging

on:
  workflow_dispatch:
  push:
    tags: ['v*']

jobs:
  e2e-full:
    name: Full E2E Regression
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      run_smoke_only: false  # 🔄 Run ALL tests
      e2e_retry_attempts: 2   # Retry flaky tests
      e2e_enable_video: true  # 📹 Capture videos for debugging
      seed_data_script: tests/e2e-seed-data.sql
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

**Duration:** ~10-20 minutes (depending on test count)  
**Tests Run:** All Reqnroll scenarios + All Playwright tests

---

### 3. Reqnroll Only (No Playwright)

```yaml
jobs:
  reqnroll-e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: Ems.sln
      api_project: backend/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      run_playwright_tests: false  # ❌ Skip Playwright
      test_filter: '@critical'      # Only critical Reqnroll tests
```

---

### 4. Playwright Only (No Reqnroll)

```yaml
jobs:
  playwright-e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: Ems.sln
      api_project: backend/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      # Don't set e2e_project - Reqnroll tests will be skipped
      run_playwright_tests: true
      run_smoke_only: false
```

---

## Repository-Specific Configuration

### TEMS-Specific Configuration

**TEMS uses different ports and database names than the workflow defaults.**

**Option 1: Use the preset (RECOMMENDED)**

```yaml
# .github/workflows/pr-ci.yml (TEMS)
name: PR CI

on:
  pull_request:
    branches: [main]

jobs:
  web-e2e:
    name: E2E Smoke Tests
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      # Required
      solution: Ems.sln
      api_project: backend/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      
      # EASY: Use TEMS preset (auto-configures ports and database)
      repo_preset: 'tems'        # Sets api_port: 5000, web_port: 3000, postgres_db: 'Tems_test'
      database_port: 5434        # ⚠️ REQUIRED: Preset can't control service ports (GH Actions limitation)
      postgres_user: 'tems_e2e'  # ⚠️ REQUIRED if tests use custom username
      
      # Test configuration
      run_smoke_only: true
      test_filter: '@smoke'
      node_version: '20'
```

**Option 2: Manual override**

```yaml
with:
  solution: Ems.sln
  api_project: backend/Ems.Api/Ems.Api.csproj
  web_directory: web/tems-portal
  e2e_project: tests/Ems.E2E/Ems.E2E.csproj
  
  # Manual: Override TEMS-specific values
  api_port: 5000           # TEMS uses 5000 (default: 5100)
  web_port: 3000           # TEMS uses 3000 (default: 3100)
  postgres_db: 'Tems_test' # TEMS convention (default: e2e_test)
  
  run_smoke_only: true
  test_filter: '@smoke'
```

**What the preset configures:**
- API port: `5000` (your E2E tests expect `http://localhost:5000`)
- Web port: `3000` (your E2E tests expect `http://localhost:3000`)
- Database: `Tems_test` (TEMS naming convention)

Without the preset or manual overrides, tests will fail with "Connection refused" errors.

### RavenXpress Configuration

**RavenXpress uses the workflow defaults** - use preset or no overrides needed:

**Option 1: Use the preset (explicit)**

```yaml
# .github/workflows/pr-ci.yml (RavenXpress)
jobs:
  web-e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      
      repo_preset: 'ravenxpress'  # Explicit: sets ports 5100/3100, database 'e2e_test'
      
      run_smoke_only: true
      test_filter: '@smoke'
```

**Option 2: Use defaults (implicit)**

```yaml
jobs:
  web-e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      run_smoke_only: true
      test_filter: '@smoke'
      # No repo_preset = uses defaults (5100/3100/e2e_test) ✅
```

---

## Configuration Reference

### Required Inputs

| Input | Description | Example |
|-------|-------------|---------|
| `solution` | Path to .sln file | `RavenXpress.sln` |
| `api_project` | Path to API .csproj | `rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj` |
| `web_directory` | Path to web project | `rx-web` |

### Repository Preset (Recommended)

| Input | Default | Description | Available Presets |
|-------|---------|-------------|-------------------|
| `repo_preset` | `''` (none) | Auto-configure ports and database for known repos | `'tems'`, `'ravenxpress'` |

> ⚠️ **Important**: `database_port` cannot be set by presets due to GitHub Actions limitation (services start before preset configuration step runs). Repos using non-default database ports (e.g., TEMS with 5434) must pass `database_port` explicitly as an input.

### Test Configuration

| Input | Default | Description |
|-------|---------|-------------|
| `e2e_project` | `''` | Path to Reqnroll/NUnit test project. If empty, Reqnroll tests are skipped. |
| `run_smoke_only` | `true` | `true` = smoke tests only, `false` = full suite |
| `test_filter` | `''` | Reqnroll test filter (e.g., `@smoke`, `@regression`, `@critical`) |
| `run_playwright_tests` | `true` | Run Playwright tests from web_directory |
| `e2e_retry_attempts` | `1` | Number of retry attempts for flaky tests (1 = no retry) |
| `e2e_enable_video` | `false` | Capture video recordings (increases artifact size) |

### Infrastructure Configuration

| Input | Default | Description | TEMS Override |
|-------|---------|-------------|---------------|
| `node_version` | `'20'` | Node.js version | - |
| `database_port` | `5432` | PostgreSQL host port | ⚠️ **`5434`** (must set explicitly) |
| `postgres_db` | `'e2e_test'` | PostgreSQL database name | ⚠️ `'Tems_test'` (via preset) |
| `postgres_user` | `'postgres'` | PostgreSQL username | ⚠️ `'tems_e2e'` |
| `postgres_password` | `'test_password_e2e_123'` | PostgreSQL password | ⚠️ `'tems_e2e_pw'` |
| `api_port` | `5100` | Port for API server | ⚠️ `5000` (via preset) |
| `web_port` | `3100` | Port for Next.js server | ⚠️ `3000` (via preset) |
| `enable_azurite` | `true` | Enable Azurite blob storage emulator | - |
| `seed_data_script` | `''` | Path to SQL seed file (e.g., `tests/seed-data.sql`) | - |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `E2E_JWT_SIGNING_KEY` | No | JWT signing key (auto-generated if not provided) |
| `E2E_JWT_AUDIENCE` | No | JWT audience (defaults to `e2e-api`) |

---

## Reqnroll Test Filtering

### Using Tags

Tag your Reqnroll scenarios with BDD tags:

```gherkin
@smoke
Scenario: User can log in
  Given I am on the login page
  When I enter valid credentials
  Then I should see the dashboard

@regression @orders
Scenario: User can create an order
  Given I am logged in as dispatcher
  When I create a new parcel delivery order
  Then the order should appear in the orders list
```

### Filter Examples

```yaml
# Run only smoke tests
test_filter: '@smoke'

# Run regression tests (@ prefix optional - will be stripped automatically)
test_filter: '@regression'  # or just 'regression'

# Run critical tests
test_filter: '@critical'

# Run all order-related tests
test_filter: '@orders'

# Multiple tags (AND logic - must have both)
test_filter: '@smoke&@orders'  # Use & for AND (NUnit syntax)

# Multiple tags (OR logic - must have at least one)
test_filter: '@smoke|@critical'  # Use | for OR (NUnit syntax)
```

> **Note**: Reqnroll tags (e.g., `@smoke`) are converted to NUnit categories. The workflow automatically strips the `@` prefix when building the filter. The actual NUnit filter used is `Category=smoke` for `test_filter: '@smoke'`.

---

## Environment Variables

The workflow automatically sets these environment variables for your tests:

### For Reqnroll/NUnit Tests

```bash
RUN_E2E=true
E2E_BASE_URL=http://localhost:3100
E2E_API_BASE_URL=http://localhost:5100
E2E_DATABASE_CONNECTION_STRING=Host=localhost;Port=5432;Database=e2e_test;...
E2E_JWT_SIGNING_KEY=<generated-or-provided>
E2E_JWT_ISSUER=https://e2e-auth-issuer
E2E_JWT_AUDIENCE=e2e-api
E2E_HEADLESS=true
E2E_SLOWMO=0
E2E_ENABLE_VIDEO=false
```

### For Playwright Tests

```bash
BASE_URL=http://localhost:3100
START_WEB_SERVER=false  # Server already running
```

### For Next.js Build

```bash
API_BASE=http://localhost:5100
NEXT_PUBLIC_API_BASE=http://localhost:5100
NEXT_PUBLIC_TEST_MOCK_MSAL=true
NEXT_PUBLIC_E2E_JWT_SIGNING_KEY=<key>
NEXT_PUBLIC_E2E_JWT_ISSUER=<issuer>
NEXT_PUBLIC_E2E_JWT_AUDIENCE=<audience>
NEXT_PUBLIC_VERSION=e2e-test
NEXT_PUBLIC_BUILD_SHA=<commit-sha>
NODE_ENV=production
```

---

## Database Seeding

### Using SQL Scripts

Create a seed script with test data:

```sql
-- tests/e2e-seed-data.sql
INSERT INTO users ("Id", "Email", "PasswordHash", "Roles", "TenantId", "CreatedUtc")
VALUES (
  '11111111-1111-1111-1111-111111111111',
  'testuser@example.com',
  '$2a$12$hashed_password',
  'Admin,Dispatcher',
  '11111111-1111-1111-1111-111111111111',
  NOW()
)
ON CONFLICT ("Email", "TenantId") DO NOTHING;
```

Reference it in your workflow:

```yaml
with:
  seed_data_script: tests/e2e-seed-data.sql
```

### Using Migrations

The workflow automatically runs EF migrations on startup with:

```bash
SkipDatabaseMigrations=false
ENABLE_TEST_MIGRATIONS=true
```

If your migrations include seed data, you don't need a separate seed script.

---

## Artifacts

The workflow uploads these artifacts on test failure:

| Artifact | Contents | Retention |
|----------|----------|-----------|
| `playwright-e2e-{run}` | Playwright HTML reports, screenshots | 7 days |
| `reqnroll-screenshots-{run}` | Reqnroll failure screenshots | 7 days |
| `reqnroll-videos-{run}` | Reqnroll video recordings (if enabled) | 3 days |
| `reqnroll-results-{run}` | TRX test result files, all retry attempts | 7 days |
| `e2e-diagnostic-logs-{run}` | API and web server logs (on failure) | 7 days |

---

## Troubleshooting

### Tests Fail with "Connection Refused"

**Symptom:** Tests can't connect to API or Web

**Root Cause:** Port mismatch between workflow defaults and your test expectations.

**Solution:** Override ports to match your project:

```yaml
# For TEMS (uses 5000/3000)
with:
  api_port: 5000
  web_port: 3000

# For RavenXpress (uses defaults 5100/3100)
# No override needed
```

**How to verify your ports:**
1. Check `appsettings.json` or test configuration for `E2E_BASE_URL`
2. Check local test scripts (e.g., PowerShell) for port values
3. Update workflow inputs to match

### API Migrations Don't Run

**Symptom:** Tables not found in database

**Solution:** Check your API startup configuration:
```csharp
// Ensure migrations run on startup in Development mode with ENABLE_TEST_MIGRATIONS
if (app.Environment.IsDevelopment() && 
    !bool.Parse(configuration["SkipDatabaseMigrations"] ?? "false"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}
```

### Azurite Not Available

**Symptom:** Tests fail with blob storage errors

**Solution:** Enable Azurite in workflow:
```yaml
with:
  enable_azurite: true
```

Update connection string in test code:
```csharp
var connectionString = Environment.GetEnvironmentVariable("AZURE_STORAGE_CONNECTION_STRING")
    ?? "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;...";
```

### Flaky Tests

**Symptom:** Tests pass sometimes, fail other times

**Solution:** Enable retries:
```yaml
with:
  e2e_retry_attempts: 3  # Retry up to 3 times
  e2e_enable_video: true  # Capture videos to debug
```

### Tests Take Too Long

**Symptom:** E2E tests timeout or run >10 minutes

**Solution:** Use smoke tests in PRs:
```yaml
# PR workflow - fast feedback
with:
  run_smoke_only: true
  test_filter: '@smoke'

# Deployment workflow - full suite
with:
  run_smoke_only: false
```

---

## Best Practices

### 1. Tag Tests Appropriately

```gherkin
@smoke @critical
Scenario: User can log in

@regression @orders
Scenario: User can create complex order with multiple parcels

@wip
Scenario: Work in progress - skip in CI
```

### 2. Use Smoke Tests in PRs

- Run only `@smoke` tagged tests in PRs (~3-5 minutes)
- Run full suite on deployment/merge (~15-20 minutes)

### 3. Generate JWT Keys

Don't commit JWT signing keys to your repo. Use GitHub secrets:

```bash
# Generate a secure key
openssl rand -base64 48

# Add to GitHub: Settings > Secrets > Actions
# Name: E2E_JWT_SIGNING_KEY
# Value: <generated-key>
```

### 4. Keep Seed Data Minimal

Only seed data required for tests to run:
- Test users (1-2)
- Test tenants (1-2)
- Reference data (if needed)

Don't seed thousands of records - tests will be slow.

### 5. Use Health Endpoints

Ensure your API and Web have health endpoints:

```csharp
// API: Program.cs
app.MapGet("/healthz", () => Results.Ok(new { status = "Healthy" }));
```

```typescript
// Next.js: pages/api/healthz.ts
export default function handler(req, res) {
  res.status(200).json({ ok: true });
}
```

---

## Migration from Local Scripts

If you're migrating from a local PowerShell script (like the example provided), here's the mapping:

| Local Script | Workflow Equivalent |
|--------------|-------------------|
| `docker run postgres` | `services.postgres` in workflow |
| `docker run azurite` | `services.azurite` in workflow |
| `dotnet publish` | `build-api` job |
| `npm run build` | `Build Next.js app` step |
| `npm run start` | `Start Next.js server` step |
| `./api-publish/Ems.Api.exe` | `Start API server` step |
| `npx playwright test` | `Run Playwright tests` step |
| `dotnet test E2E.csproj` | `Run Reqnroll E2E tests` step |

**Environment variables** map directly - the workflow sets the same variables your local script used.

---

## Example: Complete PR Workflow

```yaml
# .github/workflows/pr-ci.yml
name: PR CI

on:
  pull_request:
    branches: [main]

jobs:
  # Backend: Unit + Integration tests
  api-ci:
    name: API CI
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      run_integration: true
      js_lcov_path: rx-web/coverage/lcov.info
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**'
      sonar_coverage_exclusions: '**/*.g.cs,**/Migrations/**'
    secrets: inherit

  # Frontend: Unit tests + Build
  web-ci:
    name: Web CI
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-ci.yml@v4.0.1
    with:
      working_directory: rx-web
      run_tests: true
      node_version: '20'

  # E2E: Smoke tests only
  web-e2e:
    name: E2E Smoke
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      run_smoke_only: true
      test_filter: '@smoke'
      node_version: '20'
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

---

## Support

For issues or questions:
1. Check [troubleshooting](#troubleshooting) section
2. Review [diagnostic logs](#artifacts) from failed runs
3. Open an issue in the `azure-devops-workflows` repository
