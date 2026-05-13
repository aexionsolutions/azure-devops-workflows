# Web E2E Deployed Workflow Guide

## Overview

The `web-e2e-deployed.yml` reusable workflow runs end-to-end tests against **already-deployed environments** (dev, staging, production). Unlike the CI workflow which spins up local Docker services, this workflow:

- ✅ **Tests deployed Azure resources** - API + Web + Database already running
- ✅ **No Docker services** - Uses your actual cloud infrastructure
- ✅ **Health checks** - Verifies services are ready before testing
- ✅ **Deployed-safe Reqnroll default** - Runs `@deployed-smoke` by default to avoid accidental mutating full-suite runs
- ✅ **Bounded Playwright setup** - Installs only the needed browser dependencies and times out clearly if setup stalls
- ✅ **Higher retry logic** - Default 3 retries for deployed environment flakiness
- ✅ **Supports test artifacts** - Works with pre-built test packages
- ✅ **Post-deployment validation** - Runs after deployment completes

---

## When to Use This Workflow

| Scenario | Use This Workflow? |
|----------|-------------------|
| PR validation with Docker services | ❌ Use `web-e2e-ci.yml` |
| After deploying to dev/staging/prod | ✅ Yes |
| Smoke tests on deployed environment | ✅ Yes |
| Release promotion validation | ✅ Yes |
| Production health checks | ✅ Yes |
| Local development testing | ❌ Use local scripts |

---

## Basic Usage

### Minimum Required Inputs

```yaml
jobs:
  e2e-smoke:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
```

This will:
- Wait for API and Web health checks
- Run Reqnroll tests with `@deployed-smoke` filter (default)
- Run Playwright tests (default)
- Retry failed tests up to 3 times (default for deployed envs)

---

## Common Scenarios

### 1. Post-Deployment Smoke Tests

Run fast smoke tests after deploying to validate the deployment succeeded:

```yaml
# .github/workflows/deploy-to-dev.yml
name: Deploy to Dev

on:
  push:
    branches: [develop]

jobs:
  deploy-api:
    name: Deploy API
    # ... your API deployment steps
  
  deploy-web:
    name: Deploy Web
    needs: deploy-api
    # ... your web deployment steps
  
  e2e-smoke:
    name: E2E Smoke Tests
    needs: [deploy-api, deploy-web]
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@deployed-smoke'  # Fast feedback without mutating full-suite coverage
      e2e_retry_attempts: 3
    secrets:
      B2C_TEST_USER_EMAIL: ${{ secrets.DEV_E2E_TEST_USER_EMAIL }}
      B2C_TEST_USER_PASSWORD: ${{ secrets.DEV_E2E_TEST_USER_PASSWORD }}
```

**Duration:** ~3-5 minutes  
**Purpose:** Catch deployment issues early

---

### 2. Release Promotion with Full Regression

Run comprehensive tests when promoting a release to staging/production:

```yaml
# .github/workflows/promote-release.yml
name: Promote Release

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: ['staging', 'production']

jobs:
  deploy:
    name: Deploy to ${{ inputs.environment }}
    # ... deployment steps
  
  e2e-regression:
    name: Full E2E Regression
    needs: deploy
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      git_ref: ${{ inputs.release_tag }}  # ✅ Use release tag to match deployed code
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-${{ inputs.environment }}-web.azurewebsites.net
      api_url: https://tems-${{ inputs.environment }}-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '(Category=smoke|Category=regression|TestCategory=smoke|TestCategory=regression)'  # More comprehensive
      e2e_retry_attempts: 3
      e2e_enable_video: true  # Capture failures
      health_check_timeout: 600  # Longer timeout for production
    secrets:
      B2C_TEST_USER_EMAIL: ${{ secrets[format('{0}_E2E_TEST_USER_EMAIL', inputs.environment)] }}
      B2C_TEST_USER_PASSWORD: ${{ secrets[format('{0}_E2E_TEST_USER_PASSWORD', inputs.environment)] }}
```

**Duration:** ~10-20 minutes  
**Purpose:** Comprehensive validation before production

---

### 3. With Azure Key Vault for Database Connection

For tests that need database access (e.g., TEMS Reqnroll tests), retrieve the connection string from Azure Key Vault:

```yaml
# .github/workflows/promote-release.yml
name: Promote Release

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, uat, preprod, prod]
      release_tag:
        required: true

jobs:
  deploy-api:
    name: Deploy API
    # ... deployment steps
  
  deploy-web:
    name: Deploy Web
    needs: deploy-api
    # ... deployment steps
  
  e2e-tests:
    name: E2E Tests (Deployed)
    needs: [deploy-api, deploy-web]
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.2.0
    permissions:
      id-token: write  # Required for Azure OIDC authentication
      contents: read
    with:
      git_ref: ${{ inputs.release_tag }}
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-${{ inputs.environment }}-web.azurewebsites.net
      api_url: https://tems-${{ inputs.environment }}-api.azurewebsites.net
      web_directory: web/tems-portal
      
      # Environment & Database Configuration
      environment_name: ${{ inputs.environment }}  # Loads appsettings.{env}.json
      azure_keyvault_name: tems-${{ inputs.environment }}-kv
      azure_keyvault_secret_name: PostgresConnectionString
      
      # Test Configuration
      test_filter: '@deployed-smoke'
      e2e_retry_attempts: 3
    secrets:
      # Azure Authentication (for Key Vault access)
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}  # Fallback if OIDC not configured
      # Test Credentials
      B2C_TEST_USER_EMAIL: ${{ secrets[format('{0}_E2E_TEST_USER_EMAIL', inputs.environment)] }}
      B2C_TEST_USER_PASSWORD: ${{ secrets[format('{0}_E2E_TEST_USER_PASSWORD', inputs.environment)] }}
```

**What this does:**
- Authenticates to Azure using workload identity (OIDC)
- Retrieves database connection string from Key Vault
- Sets `ConnectionStrings__Postgres` environment variable for tests
- Tests can connect to the deployed database

---

### 4. Scheduled Production Health Checks

Monitor production continuously with scheduled smoke tests:

```yaml
# .github/workflows/production-health-check.yml
name: Production Health Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  prod-health:
    name: Production E2E Health
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-web.azurewebsites.net
      api_url: https://tems-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@critical'  # Only critical paths
      e2e_retry_attempts: 2  # Less retries for health checks
    secrets:
      B2C_TEST_USER_EMAIL: ${{ secrets.PROD_E2E_TEST_USER_EMAIL }}
      B2C_TEST_USER_PASSWORD: ${{ secrets.PROD_E2E_TEST_USER_PASSWORD }}
```

**Duration:** ~2-3 minutes  
**Purpose:** Proactive monitoring

---

### 5. Playwright Only (No Reqnroll)

Run only Playwright browser tests:

```yaml
jobs:
  playwright-only:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
      web_directory: web/tems-portal
      run_playwright_tests: true
      # Don't specify e2e_project - Reqnroll will be skipped
      playwright_project: 'chromium'  # Only Chrome tests
```

---

### 6. Reqnroll Only (No Playwright)

Run only Reqnroll BDD tests:

```yaml
jobs:
  reqnroll-only:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
      run_playwright_tests: false
      test_filter: '(Category=api|Category=backend|TestCategory=api|TestCategory=backend)'
```

---

## Reqnroll Filter Behavior

Deployed Reqnroll tests now default to `@deployed-smoke`. This is intentionally narrower than the CI `@smoke` convention so deployed environments do not run mutating or broad scenarios unless the caller opts in.

Filter handling:
- Empty or omitted `test_filter` becomes `@deployed-smoke`.
- A simple tag such as `@deployed-smoke` or `@critical` is converted to `(Category=<tag>|TestCategory=<tag>)`, which supports both NUnit category names emitted by Reqnroll.
- Advanced VSTest filters containing operators such as `=`, `~`, `&`, `|`, `(`, or `)` are passed through unchanged.
- Intentional deployed-safety skips that surface in TRX as `NotExecuted` are not retried by the smart retry action.

Use explicit filters when you really want a broader deployed run:

```yaml
with:
  # Default safe smoke set
  test_filter: '@deployed-smoke'

  # A broader category set
  test_filter: '(Category=smoke|Category=regression|TestCategory=smoke|TestCategory=regression)'
```

---

## Configuration Reference

### Required Inputs

| Input | Description | Example |
|-------|-------------|---------|
| `web_url` | Deployed web app URL | `https://tems-dev-web.azurewebsites.net` |
| `api_url` | Deployed API URL | `https://tems-dev-api.azurewebsites.net` |

### Version Control

| Input | Default | Description |
|-------|---------|-------------|
| `git_ref` | `''` (current branch) | Git ref (tag/branch/SHA) to checkout. **Important:** Use release tag to ensure test version matches deployed code. |

### Test Configuration

| Input | Default | Description |
|-------|---------|-------------|
| `e2e_project` | `''` | Path to Reqnroll test .csproj. Empty = skip Reqnroll tests. |
| `test_filter` | `'@deployed-smoke'` | Reqnroll test filter. Simple tags are mapped to both `Category` and `TestCategory`; advanced VSTest filters are passed through unchanged. |
| `run_playwright_tests` | `true` | Run Playwright tests |
| `playwright_config` | `''` | Playwright config file for deployed tests. If set, `--config` is passed to `npx playwright test`. |
| `playwright_project` | `''` | Playwright project (e.g., `chromium`, `firefox`). Empty = run all projects; install step defaults to Chromium dependencies. |
| `e2e_retry_attempts` | `3` | Retry attempts (higher default than CI workflow) |
| `playwright_retry_attempts` | `2` | Retry attempts passed to Playwright |
| `playwright_install_timeout_minutes` | `15` | Maximum minutes for Playwright browser/system dependency installation |
| `e2e_enable_video` | `false` | Capture video recordings |
| `console_verbosity` | `normal` | Console logger verbosity for `dotnet test` |

### Infrastructure

| Input | Default | Description |
|-------|---------|-------------|
| `node_version` | `'20'` | Node.js version for Playwright |
| `dotnet_version` | `'10.0.x'` | .NET version for Reqnroll |
| `web_directory` | `''` | Path to web project (required if run_playwright_tests is true) |

### Health Checks

| Input | Default | Description |
|-------|---------|-------------|
| `health_check_enabled` | `true` | Perform health checks before tests |
| `health_check_timeout` | `300` | Health check timeout in seconds (5 minutes) |

### Authentication

| Input | Default | Description |
|-------|---------|-------------|
| `api_key` | `''` | API key if required by deployed environment |

### Database Configuration

| Input | Default | Description |
|-------|---------|-------------|
| `environment_name` | `''` | Environment name (dev, uat, preprod, prod) - used for loading appsettings.{env}.json |
| `database_connection_string` | `''` | Database connection string (direct). Use this for non-Azure deployments. |
| `azure_keyvault_name` | `''` | Azure Key Vault name to retrieve database connection string from |
| `azure_keyvault_secret_name` | `'PostgresConnectionString'` | Secret name in Key Vault for database connection string |

### Additional E2E Configuration

| Input | Default | Description |
|-------|---------|-------------|
| `e2e_env_vars` | `'{}'` | JSON object of additional non-secret environment variables to expose to tests. |
| `b2c_authority` | `''` | Azure B2C authority URL for Reqnroll and Playwright auth flows. |
| `b2c_client_id` | `''` | Azure B2C client ID for deployed E2E auth flows. |
| `b2c_scope` | `''` | Azure B2C API scope for deployed E2E auth flows. |

**Note:** Database connection retrieval priority:
1. Azure Key Vault (if `azure_keyvault_name` is set)
2. Direct input (`database_connection_string`)
3. Secret (`DATABASE_CONNECTION_STRING`)
4. Not set (env var not added; tests use default/local configuration from appsettings.json)

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `AZURE_CLIENT_ID` | No | Azure Client ID for Key Vault access (workload identity/OIDC) |
| `AZURE_TENANT_ID` | No | Azure Tenant ID for Key Vault access |
| `AZURE_SUBSCRIPTION_ID` | No | Azure Subscription ID for Key Vault access |
| `AZURE_CREDENTIALS` | No | Azure credentials JSON (legacy service principal auth method for Key Vault) |
| `E2E_AUTH_TOKEN` | No | Authentication token for deployed environment |
| `DATABASE_CONNECTION_STRING` | No | Database connection string (alternative to Key Vault) |
| `b2c_client_secret` | No | Preferred B2C client secret for E2E auth flows |
| `e2e_secrets` | No | JSON object of additional secret environment variables to expose to tests. Values are masked in logs. |
| `AAD_B2C_AUTHORITY` | No | Legacy B2C authority secret. Prefer `b2c_authority` input. |
| `B2C_SMOKE_CLIENT_ID` | No | Legacy B2C client ID secret. Prefer `b2c_client_id` input. |
| `AAD_B2C_API_SCOPE` | No | Legacy B2C scope secret. Prefer `b2c_scope` input. |
| `B2C_SMOKE_CLIENT_SECRET` | No | Legacy B2C client secret. Prefer `secrets.b2c_client_secret`. |
| `B2C_TEST_USER_EMAIL` | No | B2C test user email for deployed Playwright auth tests |
| `B2C_TEST_USER_PASSWORD` | No | B2C test user password for deployed Playwright auth tests |

---

## Environment Variables

The workflow automatically sets these environment variables for your tests:

### For Reqnroll Tests

```bash
RUN_E2E=true
E2E_ENVIRONMENT=dev  # From environment_name input
E2E_BASE_URL=https://tems-dev-web.azurewebsites.net
E2E_API_BASE_URL=https://tems-dev-api.azurewebsites.net
E2E_HEADLESS=true
E2E_SLOWMO=0
E2E_ENABLE_VIDEO=false
E2E_AUTH_TOKEN=<secret>
E2E_API_KEY=<input>
E2E_RETRY_ATTEMPTS=3
B2C_AUTHORITY=<input-or-legacy-secret>
B2C_CLIENT_ID=<input-or-legacy-secret>
B2C_SCOPE=<input-or-legacy-secret>
B2C_CLIENT_SECRET=<secret>
ConnectionStrings__Postgres=<from Key Vault or input>
```

### For Playwright Tests

```bash
BASE_URL=https://tems-dev-web.azurewebsites.net
API_BASE_URL=https://tems-dev-api.azurewebsites.net
E2E_AUTH_TOKEN=<secret>
E2E_API_KEY=<input>
B2C_AUTHORITY=<input-or-legacy-secret>
B2C_CLIENT_ID=<input-or-legacy-secret>
B2C_SCOPE=<input-or-legacy-secret>
B2C_CLIENT_SECRET=<secret>
B2C_TEST_USER_EMAIL=<secret>
B2C_TEST_USER_PASSWORD=<secret>
```

---

## Health Checks

The workflow performs health checks before running tests to ensure the deployed environment is ready:

### Health Check Endpoints

The workflow tries these endpoints in order:

**API:**
1. `{api_url}/healthz` (preferred)
2. `{api_url}/health`
3. `{api_url}/` (fallback)

**Web:**
1. `{web_url}/api/healthz` (Next.js API route)
2. `{web_url}/` (fallback)

### Implementing Health Endpoints

**API (Program.cs):**
```csharp
app.MapGet("/healthz", () => Results.Ok(new { 
    status = "Healthy",
    timestamp = DateTime.UtcNow 
}));
```

**Next.js (pages/api/healthz.ts):**
```typescript
export default function handler(req, res) {
  res.status(200).json({ ok: true });
}
```

### Health Check Behavior

- **Default timeout:** 300 seconds (5 minutes)
- **Check interval:** 10 seconds
- **Failure:** Tests will not run if health checks fail
- **Disable:** Set `health_check_enabled: false` to skip

---

## Test Artifact Strategy

### Option 1: Use Pre-Built Test Artifacts (Recommended)

**✅ Best for TEMS:** This approach is consistent with how you already package `api.zip` and `web.zip`. The complexity is already solved—just add `e2e-tests.zip` to your release artifacts.

Package tests during release creation and reuse them:

**Step 1: Create release with test artifacts**

```yaml
# .github/workflows/create-release.yml
name: Create Release

on:
  workflow_dispatch:
    inputs:
      version:
        required: true
        type: string

jobs:
  build-tests:
    name: Build E2E Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      
      - name: Publish E2E Tests
        run: |
          dotnet publish tests/Ems.E2E/Ems.E2E.csproj \
            -c Release \
            -o e2e-tests \
            --self-contained false
      
      - name: Package Playwright Tests
        run: |
          cd web/tems-portal
          npm ci
          # Browser/system dependencies are installed by the deployed workflow at run time.
          # Copy entire web directory for Playwright.
          cd ../..
          cp -r web/tems-portal e2e-tests/playwright
      
      - name: Create test artifact
        run: |
          cd e2e-tests
          tar -czf ../e2e-tests-${{ inputs.version }}.tar.gz .
      
      - name: Upload to release
        uses: softprops/action-gh-release@v1
        with:
          tag_name: ${{ inputs.version }}
          files: e2e-tests-${{ inputs.version }}.tar.gz
```

**Step 2: Use test artifacts during deployment**

```yaml
# .github/workflows/promote-release.yml
name: Promote Release

on:
  workflow_dispatch:
    inputs:
      version:
        required: true
      environment:
        required: true

jobs:
  deploy-api:
    # ... deploy API
  
  deploy-web:
    # ... deploy web
  
  download-test-artifact:
    name: Download Test Artifact
    runs-on: ubuntu-latest
    steps:
      - name: Download release asset
        run: |
          gh release download ${{ inputs.version }} \
            --pattern "e2e-tests-*.tar.gz" \
            --dir ./e2e-tests
          
          cd e2e-tests
          tar -xzf e2e-tests-*.tar.gz
      
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: e2e-tests
          path: e2e-tests/
  
  e2e-tests:
    name: E2E Tests (Artifact)
    needs: [deploy-api, deploy-web, download-test-artifact]
    runs-on: ubuntu-latest
    steps:
      - name: Download test artifact
        uses: actions/download-artifact@v4
        with:
          name: e2e-tests
          path: e2e-tests/
      
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      
      - name: Run Reqnroll tests
        working-directory: e2e-tests
        env:
          E2E_BASE_URL: https://tems-${{ inputs.environment }}-web.azurewebsites.net
          E2E_API_BASE_URL: https://tems-${{ inputs.environment }}-api.azurewebsites.net
        run: |
          dotnet test Ems.E2E.dll --filter "(Category=deployed-smoke|TestCategory=deployed-smoke)"
      
      - name: Run Playwright tests
        working-directory: e2e-tests/playwright
        env:
          BASE_URL: https://tems-${{ inputs.environment }}-web.azurewebsites.net
        run: npx playwright test
```

**Pros:**
- ✅ **Consistent with api.zip/web.zip** - same artifact pattern
- ✅ **Faster** - no rebuild (saves ~2-3 minutes per promotion)
- ✅ **Truly immutable** - exact same test binary for all environments
- ✅ **Traceability** - audit trail of exact tests used
- ✅ **Version matching guaranteed** - compiled from same commit as deployed code

**Cons:**
- ~~More complex setup~~ ✅ Already solved if you're packaging api.zip/web.zip

**When to use:**
- ✅ You already package deployment artifacts (api.zip, web.zip)
- ✅ Promoting releases to multiple environments
- ✅ Need audit trail / compliance requirements

---

### Option 2: Build from Source (Alternative)

The workflow checks out your repository and builds tests from source:

```yaml
jobs:
  e2e:
    uses: .../web-e2e-deployed.yml
    with:
      git_ref: ${{ inputs.release_tag }}  # ✅ Use release tag to match deployed code
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
```

**Pros:**
- ✅ Simpler - no artifact management
- ✅ Test version matches deployed code (when using git_ref)

**Cons:**
- ❌ Slower - rebuilds tests every promotion (~2-3 minutes overhead)
- ❌ Inconsistent with api.zip/web.zip approach
- ❌ Requires git checkout (dependency on repository access)

**When to use:**
- Only if you're NOT packaging deployment artifacts
- Simple projects with fast test builds
- Prefer simplicity over speed

---

## Comparison: CI vs Deployed Workflows

| Aspect | web-e2e-ci.yml | web-e2e-deployed.yml |
|--------|----------------|----------------------|
| **Services** | Docker (Postgres, Azurite) | Azure (deployed) |
| **Build** | Builds API + Web from source | No build, uses deployed apps |
| **Database** | Local PostgreSQL | Azure SQL Database |
| **Use Case** | PR validation | Post-deployment validation |
| **Speed** | Slower (builds everything) | Faster (no builds) |
| **Retry Default** | 1 (PRs should be stable) | 3 (deployed envs can be flaky) |
| **Health Checks** | No (local services) | Yes (wait for deployments) |
| **Auth** | Test JWT tokens | Real Azure AD / API keys |
| **When to Use** | Before merge | After deployment |

---

## Troubleshooting

### Health Checks Fail

**Symptom:** "API health check failed after 300s"

**Solutions:**

1. **Check health endpoint exists:**
   ```bash
   curl https://tems-dev-api.azurewebsites.net/healthz
   ```

2. **Increase timeout for slow deployments:**
   ```yaml
   with:
     health_check_timeout: 600  # 10 minutes
   ```

3. **Disable health checks (not recommended):**
   ```yaml
   with:
     health_check_enabled: false
   ```

---

### Tests Fail with Authentication Errors

**Symptom:** "401 Unauthorized" or "403 Forbidden"

**Solutions:**

1. **Verify secrets are set:**
   ```yaml
   secrets:
     B2C_TEST_USER_EMAIL: ${{ secrets.DEV_E2E_TEST_USER_EMAIL }}
     B2C_TEST_USER_PASSWORD: ${{ secrets.DEV_E2E_TEST_USER_PASSWORD }}
   ```

2. **Check API key if required:**
   ```yaml
   with:
     api_key: ${{ secrets.DEV_API_KEY }}
   ```

3. **Ensure test user exists in deployed environment:**
   - Create test user in Azure portal
   - Add credentials to GitHub secrets per environment

---

### Tests Are Flaky

**Symptom:** Tests pass sometimes, fail other times

**Solutions:**

1. **Increase retry attempts:**
   ```yaml
   with:
     e2e_retry_attempts: 5  # More retries
   ```

2. **Enable video recording to debug:**
   ```yaml
   with:
     e2e_enable_video: true
   ```

3. **Check deployed environment stability:**
   - Azure App Service plan scaling
   - Database connection pool limits
   - Network latency issues

---

### Playwright Install Times Out

**Symptom:** Browser or Linux dependency installation fails after the configured timeout.

**Solutions:**

1. **Increase the bounded install window:**
   ```yaml
   with:
     playwright_install_timeout_minutes: 20
   ```

2. **Pin the deployed Playwright project to one browser when possible:**
   ```yaml
   with:
     playwright_project: chromium
   ```

3. **Use a deployed-specific Playwright config to avoid local-only projects:**
   ```yaml
   with:
     playwright_config: playwright.prod.config.ts
   ```

---

### Wrong Test Version Running

**Symptom:** Tests fail because they expect newer features that don't exist in the deployed code

**Root cause:** You deployed code from `v1.2.0` but tests are running from `main` branch which has moved ahead.

**Solution:** Use **Option 1: Pre-Built Test Artifacts** (recommended). This packages tests at release creation time, ensuring the test binary matches the deployed code binary. Same pattern as your `api.zip` and `web.zip`.

---

## Best Practices

### 1. Use Different Test Filters per Environment

```yaml
# Development: deployed-safe smoke coverage
test_filter: '@deployed-smoke'

# Staging: More comprehensive
test_filter: '(Category=smoke|Category=regression|TestCategory=smoke|TestCategory=regression)'

# Production: Critical paths only
test_filter: '@critical'
```

### 2. Set Higher Retry Counts for Deployed Environments

```yaml
# CI workflow (local Docker)
e2e_retry_attempts: 1

# Deployed workflow (real Azure)
e2e_retry_attempts: 3
```

### 3. Use Environment-Specific Secrets

```yaml
secrets:
  B2C_TEST_USER_EMAIL: ${{ secrets[format('{0}_E2E_TEST_USER_EMAIL', inputs.environment)] }}
  B2C_TEST_USER_PASSWORD: ${{ secrets[format('{0}_E2E_TEST_USER_PASSWORD', inputs.environment)] }}
```

### 4. Monitor Production with Scheduled Tests

```yaml
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
```

### 5. Use Pre-Built Test Artifacts (Highly Recommended)

Package `e2e-tests.zip` alongside `api.zip` and `web.zip` during release creation. This ensures:
- ✅ Test version matches deployed code version
- ✅ Consistent artifact pattern across all releases
- ✅ Faster promotions (no rebuild)
- ✅ Audit trail for compliance

---

## Example: Complete Deployment Workflow

```yaml
# .github/workflows/deploy-to-staging.yml
name: Deploy to Staging

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  # Deploy API
  deploy-api:
    name: Deploy API
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to Azure
        # ... your deployment steps
  
  # Deploy Web
  deploy-web:
    name: Deploy Web
    needs: deploy-api
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to Azure
        # ... your deployment steps
  
  # E2E Smoke Tests
  e2e-smoke:
    name: E2E Smoke Tests
    needs: [deploy-api, deploy-web]
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-staging-web.azurewebsites.net
      api_url: https://tems-staging-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@deployed-smoke'
      e2e_retry_attempts: 3
      health_check_timeout: 600
    secrets:
      B2C_TEST_USER_EMAIL: ${{ secrets.STAGING_E2E_TEST_USER_EMAIL }}
      B2C_TEST_USER_PASSWORD: ${{ secrets.STAGING_E2E_TEST_USER_PASSWORD }}
  
  # E2E Regression (only if smoke passes)
  e2e-regression:
    name: E2E Regression
    needs: e2e-smoke
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-staging-web.azurewebsites.net
      api_url: https://tems-staging-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@regression'
      e2e_retry_attempts: 3
      e2e_enable_video: true
    secrets:
      B2C_TEST_USER_EMAIL: ${{ secrets.STAGING_E2E_TEST_USER_EMAIL }}
      B2C_TEST_USER_PASSWORD: ${{ secrets.STAGING_E2E_TEST_USER_PASSWORD }}
```

---

## Support

For issues or questions:
1. Check [troubleshooting](#troubleshooting) section
2. Review [artifacts](#artifacts) from failed runs
3. Open an issue in the `azure-devops-workflows` repository
