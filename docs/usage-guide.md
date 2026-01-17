# Usage Guide

This guide explains how to use the shared workflows in your project.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Azure Infrastructure Deploy](#azure-infrastructure-deploy)
- [.NET CI](#net-ci)
- [Web CI](#web-ci)
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
    uses: .../.github/workflows/azure-api-deploy.yml@v1.0.0
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

- Review [Parameters Reference](parameters-reference.md) for complete input/secret documentation
- Check [Examples](examples/) for real-world usage
- See [Migration Guide](migration-guide.md) to migrate from inline workflows
