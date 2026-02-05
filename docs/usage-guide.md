# Usage Guide

This guide explains how to use the shared workflows in your project.

## Table of Contents

- [Prerequisites](#prerequisites)
- [CI/CD Workflows](#cicd-workflows)
  - [.NET CI](#net-ci)
  - [Web CI](#web-ci)
  - [Web E2E CI](#web-e2e-ci)
  - [Web E2E Deployed](#web-e2e-deployed)
- [Deployment Workflows](#deployment-workflows)
  - [Azure Infrastructure Deploy](#azure-infrastructure-deploy)
  - [API Deploy](#api-deploy)
  - [Web Deploy](#web-deploy)
- [Best Practices](#best-practices)

## Prerequisites

### 1. Azure Setup

Complete the [Azure OIDC Setup](azure-oidc-setup.md) guide to configure:
- Service principal with required roles
- Federated credentials for each environment
- Resource provider registrations

### 2. GitHub Secrets

Configure repository secrets:

```
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Configure environment secrets (per environment):

```
POSTGRES_ADMIN_PASSWORD
AZURE_LOCATION
```

## Azure Infrastructure Deploy

**Workflow**: `azure-infra-deploy.yml`

**Purpose**: Deploy Bicep templates to Azure with automatic PostgreSQL and Key Vault management.

### Basic Usage

```yaml
name: Deploy Infrastructure

on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: choice
        options: [dev, uat, preprod, prod]

jobs:
  deploy:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v4.1.0
    with:
      environment: ${{ inputs.environment }}
      azure_location: ukwest
      resource_group: myapp-${{ inputs.environment }}-rg
      name_prefix: myapp-${{ inputs.environment }}
      bicep_template_path: infra/main.bicep
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
```

> **Note**: Version tags are auto-generated based on Conventional Commits. Use `@v4.1.0` for stable releases or `@v4.1.0-pr.3.abc123` for pre-release testing.

### Advanced Usage (with all options)

```yaml
jobs:
  deploy:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v4.1.0
    with:
      # Required
      environment: dev
      azure_location: ukwest
      resource_group: myapp-dev-rg
      name_prefix: myapp-dev
      
      # Optional - Bicep Configuration
      bicep_template_path: infra/azure/main.bicep  # Default: infra/main.bicep
      deployment_name: infrastructure              # Default: main
      
      # Optional - PostgreSQL
      postgres_server_name: custom-pg-name         # Default: <name_prefix>-pg
      postgres_admin_user: myadmin                 # Default: pgadmin
      manage_existing_postgres: true               # Default: false
      
      # Optional - Azure AD B2C
      aad_b2c_authority: https://...
      aad_b2c_client_id: abc123
      aad_b2c_api_scope: api://...
      
      # Optional - Feature Flags
      enable_kv_rbac: true                         # Default: true
      validate_secrets: true                       # Default: true
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
```

### Key Features

- ✅ OIDC authentication (no long-lived secrets)
- ✅ Automatic PostgreSQL server management (start/stop/wait)
- ✅ Key Vault RBAC auto-configuration
- ✅ Provider registration (PostgreSQL, Application Insights)
- ✅ Secret validation before deployment
- ✅ Comprehensive error reporting

## .NET CI

**Workflow**: `dotnet-ci.yml`

**Purpose**: Build, test, and analyze .NET solutions with coverage reporting.

### Basic Usage

```yaml
name: .NET CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop]

jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v1.0.0
    with:
      solution_path: MyApp.sln
      coverage_threshold: 80
```

### Advanced Usage

```yaml
jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v1.0.0
    with:
      # Solution Configuration
      solution_path: src/MyApp.sln                 # Default: *.sln
      dotnet_version: '10.0.x'                     # Default: 10.0.x
      
      # Testing
      test_projects: '**/*Tests.csproj'            # Default: **/*Tests.csproj
      run_integration_tests: true                  # Default: false (enables Docker services)
      coverage_threshold: 85                       # Default: 80
      
      # Playwright E2E
      run_playwright: true                         # Default: false
      playwright_project_path: web/portal          # Default: web
      node_version: '20'                           # Default: 20
      
      # SonarCloud
      sonar_enabled: true                          # Default: false
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.event.pull_request.head.ref }}
      pr_base: ${{ github.event.pull_request.base.ref }}
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_ORG: ${{ secrets.SONAR_ORG }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

### Key Features

- ✅ Automatic dependency restoration
- ✅ Code coverage with threshold enforcement
- ✅ Integration test support (PostgreSQL + Azurite)
- ✅ Playwright E2E test support
- ✅ SonarCloud integration with PR decoration
- ✅ Artifact uploads (coverage reports, test results)

## Web CI

**Workflow**: `web-ci.yml`

**Purpose**: Lint, test, and build React/Next.js applications.

### Basic Usage

```yaml
name: Web CI

on:
  pull_request:
    paths:
      - 'web/**'
  push:
    branches: [main]
    paths:
      - 'web/**'

jobs:
  web:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-ci.yml@v1.0.0
    with:
      working_directory: web/portal
      run_tests: true
      run_build: true
```

### Advanced Usage

```yaml
jobs:
  web:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-ci.yml@v1.0.0
    with:
      # Project Configuration
      working_directory: web/my-app               # Default: web
      node_version: '20'                          # Default: 20
      package_manager: npm                        # Default: npm (or pnpm)
      
      # CI Steps
      run_lint: true                              # Default: true
      run_tests: true                             # Default: true
      run_build: true                             # Default: true
      
      # Playwright
      run_playwright: true                        # Default: false
      playwright_install_deps: true               # Default: true
```

### Key Features

- ✅ npm and pnpm support
- ✅ Automatic dependency installation
- ✅ Playwright browser installation
- ✅ Lint, test, and build in one workflow
- ✅ Artifact uploads (build output, Playwright reports)

## Web E2E CI

**Workflow**: `web-e2e-ci.yml`

**Purpose**: End-to-end testing with full stack (API + Web + Database) in Docker.

### Basic Usage

```yaml
name: E2E Tests

on:
  pull_request:
    branches: [main]

jobs:
  e2e:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj
      run_smoke_only: true  # Fast feedback in PRs
      test_filter: '@smoke'
```

### Advanced Usage

```yaml
jobs:
  e2e-full:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@v4.0.1
    with:
      # Required Configuration
      solution: RavenXpress.sln
      api_project: rx-platform/src/RavenXpress.Api/RavenXpress.Api.csproj
      web_directory: rx-web
      
      # Optional Test Projects
      e2e_project: tests/RavenXpress.E2E/RavenXpress.E2E.csproj  # Reqnroll/SpecFlow tests
      
      # Test Execution
      run_smoke_only: false                      # Default: true
      test_filter: '@regression'                 # Default: '' (all tests)
      run_playwright_tests: true                 # Default: true
      e2e_retry_attempts: 2                      # Default: 1 (no retry)
      e2e_enable_video: true                     # Default: false
      
      # Infrastructure
      node_version: '20'                         # Default: 20
      postgres_db: e2e_test                      # Default: e2e_test
      api_port: 5100                             # Default: 5100
      web_port: 3100                             # Default: 3100
      enable_azurite: true                       # Default: true
      
      # Database Seeding
      seed_data_script: tests/e2e-seed-data.sql # Default: '' (no seeding)
    secrets:
      E2E_JWT_SIGNING_KEY: ${{ secrets.E2E_JWT_SIGNING_KEY }}
```

### Key Features

- ✅ **Full Stack** - Real API + Web + Database (not mocked)
- ✅ **Docker Services** - PostgreSQL + Azurite blob storage
- ✅ **Reqnroll Support** - BDD tests with tag-based filtering
- ✅ **Playwright Support** - Browser automation tests
- ✅ **Smoke Mode** - Fast feedback with smoke tests in PRs
- ✅ **Test Retry** - Configurable retry for flaky tests
- ✅ **Video Recording** - Optional video capture for debugging
- ✅ **Custom Seeding** - SQL scripts for test data
- ✅ **Comprehensive Artifacts** - Screenshots, videos, logs

### Test Filtering

Use Reqnroll tags to organize tests:

```gherkin
@smoke @critical
Scenario: User can log in
  Given I am on the login page
  When I enter valid credentials
  Then I should see the dashboard

@regression @orders
Scenario: User can create an order
  Given I am logged in
  When I create a new order
  Then the order appears in the list
```

Filter by tag in workflow:

```yaml
with:
  test_filter: '@smoke'           # Only smoke tests
  # OR
  test_filter: '@regression'      # Only regression tests
  # OR
  test_filter: '@smoke or @critical'  # Either tag
```

### Common Scenarios

**1. PR Smoke Tests (Fast)**
```yaml
with:
  run_smoke_only: true
  test_filter: '@smoke'
  # Duration: ~3-5 minutes
```

**2. Full Regression (Deployment)**
```yaml
with:
  run_smoke_only: false
  e2e_retry_attempts: 2
  e2e_enable_video: true
  # Duration: ~10-20 minutes
```

**3. Reqnroll Only**
```yaml
with:
  run_playwright_tests: false
  e2e_project: tests/Ems.E2E/Ems.E2E.csproj
```

### Documentation

See [web-e2e-ci-guide.md](web-e2e-ci-guide.md) for comprehensive documentation including:
- Complete configuration reference
- Reqnroll test filtering strategies
- Environment variables
- Database seeding with SQL scripts
- Troubleshooting common issues
- Migration from local PowerShell scripts

---

## Web E2E Deployed

**Workflow**: `web-e2e-deployed.yml`

**Purpose**: End-to-end testing against **already-deployed environments** (dev, staging, production). No Docker services - tests your actual Azure infrastructure.

### Basic Usage

```yaml
name: Deploy to Staging

on:
  push:
    tags: ['v*']

jobs:
  deploy-api:
    # ... your API deployment
  
  deploy-web:
    needs: deploy-api
    # ... your web deployment
  
  e2e-smoke:
    name: Post-Deploy E2E
    needs: [deploy-api, deploy-web]
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-staging-web.azurewebsites.net
      api_url: https://tems-staging-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@smoke'
    secrets:
      E2E_TEST_USER_EMAIL: ${{ secrets.STAGING_E2E_TEST_USER_EMAIL }}
      E2E_TEST_USER_PASSWORD: ${{ secrets.STAGING_E2E_TEST_USER_PASSWORD }}
```

### Advanced Usage

```yaml
jobs:
  e2e-regression:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      # Required - Deployed Environment URLs
      web_url: https://tems-staging-web.azurewebsites.net
      api_url: https://tems-staging-api.azurewebsites.net
      
      # Test Projects
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_directory: web/tems-portal
      
      # Test Configuration
      test_filter: '@smoke or @regression'
      run_playwright_tests: true
      playwright_project: 'chromium'           # Specific browser
      e2e_retry_attempts: 3                    # Higher for deployed envs
      e2e_enable_video: true
      
      # Health Checks
      health_check_enabled: true               # Wait for services
      health_check_timeout: 600                # 10 minutes
      
      # Infrastructure
      node_version: '20'
      dotnet_version: '10.0.x'
      
      # Authentication (if required)
      api_key: ${{ secrets.STAGING_API_KEY }}
    secrets:
      E2E_AUTH_TOKEN: ${{ secrets.STAGING_AUTH_TOKEN }}
      E2E_TEST_USER_EMAIL: ${{ secrets.STAGING_E2E_TEST_USER_EMAIL }}
      E2E_TEST_USER_PASSWORD: ${{ secrets.STAGING_E2E_TEST_USER_PASSWORD }}
```

### Key Features

- ✅ **Tests Deployed Azure Resources** - API + Web + Database already running
- ✅ **No Docker Services** - Uses your actual cloud infrastructure
- ✅ **Health Checks** - Verifies services are ready before testing
- ✅ **Higher Retry Logic** - Default 3 retries for deployed environment flakiness
- ✅ **Test Artifact Support** - Works with pre-built test packages
- ✅ **Post-Deployment Validation** - Runs after deployment completes
- ✅ **Production Monitoring** - Can run on schedule for health checks

### When to Use

| Scenario | Use This Workflow? |
|----------|-------------------|
| PR validation with Docker services | ❌ Use `web-e2e-ci.yml` |
| After deploying to dev/staging/prod | ✅ Yes |
| Smoke tests on deployed environment | ✅ Yes |
| Release promotion validation | ✅ Yes |
| Production health checks | ✅ Yes |
| Scheduled monitoring | ✅ Yes |

### Comparison: CI vs Deployed

| Aspect | web-e2e-ci.yml | web-e2e-deployed.yml |
|--------|----------------|----------------------|
| **Services** | Docker (Postgres, Azurite) | Azure (deployed) |
| **Build** | Builds API + Web from source | No build, uses deployed apps |
| **Use Case** | PR validation | Post-deployment validation |
| **Speed** | Slower (builds everything) | Faster (no builds) |
| **Retry Default** | 1 | 3 |
| **When to Use** | Before merge | After deployment |

### Scheduled Production Monitoring

```yaml
name: Production Health Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  prod-health:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@v4.0.1
    with:
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      web_url: https://tems-web.azurewebsites.net
      api_url: https://tems-api.azurewebsites.net
      web_directory: web/tems-portal
      test_filter: '@critical'  # Only critical paths
    secrets:
      E2E_TEST_USER_EMAIL: ${{ secrets.PROD_E2E_TEST_USER_EMAIL }}
      E2E_TEST_USER_PASSWORD: ${{ secrets.PROD_E2E_TEST_USER_PASSWORD }}
```

### Documentation

See [web-e2e-deployed-guide.md](web-e2e-deployed-guide.md) for comprehensive documentation including:
- Test artifact strategy (packaging tests during release)
- Health check configuration and custom endpoints
- Post-deployment validation patterns
- Production monitoring with scheduled tests
- Environment-specific secret management
- Troubleshooting deployed environment issues

---
```yaml
with:
  e2e_project: tests/MyApp.E2E/MyApp.E2E.csproj
  run_playwright_tests: false
```

**4. Playwright Only**
```yaml
with:
  # Don't set e2e_project
  run_playwright_tests: true
```

📚 **Detailed Guide**: See [web-e2e-ci-guide.md](web-e2e-ci-guide.md) for comprehensive documentation.
- ✅ Conditional step execution

## Best Practices

### 1. Version Pinning

✅ **Recommended**: Pin to specific version
```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.2.0
```

✅ **Safe**: Auto-update to latest patch
```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1.2
```

⚠️ **Use with caution**: Auto-update to latest minor
```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@v1
```

❌ **Not recommended**: Always use latest
```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/azure-infra-deploy.yml@main
```

**💡 How version immutability works:**

When you reference `@v1.2.0`, GitHub pins the reusable workflow to that exact snapshot.

Reusable workflows run inside the *calling repo* workspace, so this repo’s internal composite actions are resolved by checking out two folders:

- `caller/`: the calling repo (where `run:` steps execute)
- `shared/`: this repo at the same `@ref` the caller pinned in `uses: ...@ref` (passed explicitly as `shared_ref`)

Composite actions are then referenced from `./shared/.github/actions/...`, keeping the workflow + its internals locked to the same version.

If you pin a workflow to a tag (stable or prerelease), set `with: shared_ref: <same tag>`.

### 2. Secrets Management

**Use environment secrets for environment-specific values**:
```yaml
jobs:
  deploy:
    environment: ${{ inputs.environment }}  # This maps to GitHub environment
    uses: aexionsolutions/azure-devops-workflows/...
    secrets:
      POSTGRES_ADMIN_PASSWORD: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}  # From environment
```

**Use repository secrets for shared values**:
```yaml
secrets:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}  # Same for all environments
```

### 3. Conditional Workflow Execution

**Only run on specific paths**:
```yaml
on:
  pull_request:
    paths:
      - 'src/**'
      - 'tests/**'
      - '.github/workflows/dotnet-ci.yml'
```

**Only run for specific branches**:
```yaml
on:
  push:
    branches:
      - main
      - 'release/**'
```

### 4. Workflow Dependencies

**Run workflows sequentially**:
```yaml
jobs:
  ci:
    uses: .../.github/workflows/dotnet-ci.yml@v1.0.0
  
  deploy:
    needs: ci  # Wait for CI to complete
    uses: .../.github/workflows/api-deploy.yml@v4.1.0
```

### 5. Testing Workflow Changes

**Test from feature branch before merging**:
```yaml
# Temporarily change version to test
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@feature/my-test-branch
```

**Revert to stable version after testing**:
```yaml
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v1.0.0
```

## Troubleshooting

### OIDC Authentication Fails

**Error**: "AADSTS70025: No configured federated identity credentials"

**Solution**: Ensure federated credentials created for the environment you're deploying to. See [Azure OIDC Setup](azure-oidc-setup.md).

### PostgreSQL Timeout

**Error**: "PostgreSQL server did not reach Ready state within timeout"

**Solution**: Increase timeout or set `manage_existing_postgres: false` to skip waiting.

### Secret Not Found

**Error**: "Required secret POSTGRES_ADMIN_PASSWORD is not set"

**Solution**: Configure secret in GitHub repository settings under the correct environment.

### Coverage Threshold Not Met

**Error**: "Coverage 75% is below threshold 80%"

**Solution**: Increase test coverage or lower `coverage_threshold` input.

## Next Steps

- Review the main documentation index in [README.md](../README.md)
- Browse the available reusable workflows in [.github/workflows/](../.github/workflows/)
