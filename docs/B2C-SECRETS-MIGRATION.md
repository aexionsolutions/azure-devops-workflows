# B2C Secrets Migration Guide

## Overview

The reusable E2E workflows now read B2C configuration directly from secrets instead of requiring them as workflow inputs. This improves security and simplifies configuration.

## Required Changes in Caller Workflows

### ✅ What to Change

#### 1. Add B2C Secrets to `secrets:` Section

**Before:**
```yaml
jobs:
  e2e-tests:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@main
    with:
      # ... other inputs
      b2c_authority: ${{ secrets.AAD_B2C_AUTHORITY }}
      b2c_client_id: ${{ secrets.B2C_SMOKE_CLIENT_ID }}
      b2c_scope: ${{ secrets.AAD_B2C_API_SCOPE }}
    secrets:
      e2e_secrets: ${{ secrets.E2E_SECRETS_JSON }}
```

**After (Option 1 - Explicit, Recommended):**
```yaml
jobs:
  e2e-tests:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@main
    with:
      # ... other inputs
      # ❌ REMOVE: b2c_authority, b2c_client_id, b2c_scope
    secrets:
      e2e_secrets: ${{ secrets.E2E_SECRETS_JSON }}
      # ✅ ADD: B2C secrets
      AAD_B2C_AUTHORITY: ${{ secrets.AAD_B2C_AUTHORITY }}
      B2C_SMOKE_CLIENT_ID: ${{ secrets.B2C_SMOKE_CLIENT_ID }}
      AAD_B2C_API_SCOPE: ${{ secrets.AAD_B2C_API_SCOPE }}
      B2C_SMOKE_CLIENT_SECRET: ${{ secrets.B2C_SMOKE_CLIENT_SECRET }}
```

**After (Option 2 - Inherit all, Simpler):**
```yaml
jobs:
  e2e-tests:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@main
    with:
      # ... other inputs
      # ❌ REMOVE: b2c_authority, b2c_client_id, b2c_scope
    secrets: inherit  # ✅ Passes all repository secrets automatically
```

#### 2. Remove B2C Inputs from `with:` Section

Remove these lines from the `with:` block:
- ❌ `b2c_authority: ${{ secrets.AAD_B2C_AUTHORITY }}`
- ❌ `b2c_client_id: ${{ secrets.B2C_SMOKE_CLIENT_ID }}`
- ❌ `b2c_scope: ${{ secrets.AAD_B2C_API_SCOPE }}`

These are now unused. The reusable workflow reads them directly from `secrets.*`.

### 📋 Complete Example

#### For `web-e2e-ci.yml` Callers

```yaml
name: PR E2E Tests

on:
  pull_request:
    branches: [main, develop]

jobs:
  e2e-smoke:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-ci.yml@main
    with:
      repo_preset: tems
      solution: Ems.sln
      api_project: api/Ems.Api/Ems.Api.csproj
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      run_smoke_only: true
      database_port: 5434
      # Other configs...
    secrets:
      e2e_secrets: ${{ secrets.E2E_SECRETS_JSON }}
      # B2C secrets now passed explicitly
      AAD_B2C_AUTHORITY: ${{ secrets.AAD_B2C_AUTHORITY }}
      B2C_SMOKE_CLIENT_ID: ${{ secrets.B2C_SMOKE_CLIENT_ID }}
      AAD_B2C_API_SCOPE: ${{ secrets.AAD_B2C_API_SCOPE }}
      B2C_SMOKE_CLIENT_SECRET: ${{ secrets.B2C_SMOKE_CLIENT_SECRET }}
```

#### For `web-e2e-deployed.yml` Callers

```yaml
name: Deployed E2E Tests

on:
  deployment_status:

jobs:
  e2e-deployed:
    if: github.event.deployment_status.state == 'success'
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-e2e-deployed.yml@main
    with:
      git_ref: ${{ github.event.deployment.ref }}
      web_url: https://tems-dev-web.azurewebsites.net
      api_url: https://tems-dev-api.azurewebsites.net
      web_directory: web/tems-portal
      e2e_project: tests/Ems.E2E/Ems.E2E.csproj
      run_playwright_tests: true
      test_filter: '@smoke'
    secrets:
      e2e_secrets: ${{ secrets.E2E_SECRETS_JSON }}
      # B2C secrets now passed explicitly
      AAD_B2C_AUTHORITY: ${{ secrets.AAD_B2C_AUTHORITY }}
      B2C_SMOKE_CLIENT_ID: ${{ secrets.B2C_SMOKE_CLIENT_ID }}
      AAD_B2C_API_SCOPE: ${{ secrets.AAD_B2C_API_SCOPE }}
      B2C_SMOKE_CLIENT_SECRET: ${{ secrets.B2C_SMOKE_CLIENT_SECRET }}
```

## Required Repository Secrets

Ensure these secrets are configured in your repository:

| Secret Name | Description | Example |
|------------|-------------|---------|
| `AAD_B2C_AUTHORITY` | Azure B2C authority URL | `https://yourtenantname.b2clogin.com/yourtenantname.onmicrosoft.com/B2C_1A_SIGNUP_SIGNIN` |
| `B2C_SMOKE_CLIENT_ID` | Azure B2C client ID for smoke test user | `12345678-1234-1234-1234-123456789abc` |
| `AAD_B2C_API_SCOPE` | Azure B2C API scope | `https://yourtenantname.onmicrosoft.com/api/access_as_user` |
| `B2C_SMOKE_CLIENT_SECRET` | Azure B2C client secret | `secret_value_here` |
| `E2E_SECRETS_JSON` | Additional test secrets as JSON | `{"E2E_ADMIN_PASSWORD":"secret123"}` |

## What Changed in the Reusable Workflows

### New Secret Declarations

Both `web-e2e-ci.yml` and `web-e2e-deployed.yml` now declare:

```yaml
on:
  workflow_call:
    secrets:
      # ... existing secrets
      AAD_B2C_AUTHORITY:
        description: 'Azure B2C authority URL'
        required: false
      B2C_SMOKE_CLIENT_ID:
        description: 'Azure B2C client ID for smoke test user ROPC flow'
        required: false
      AAD_B2C_API_SCOPE:
        description: 'Azure B2C API scope'
        required: false
      B2C_SMOKE_CLIENT_SECRET:
        description: 'Azure B2C client secret for smoke test user ROPC flow'
        required: false
```

### Automatic Setup and Validation

The workflows now include:

1. **Setup B2C secrets** - Reads from `secrets.*` and sets environment variables
2. **Validate B2C configuration** - Fails with a clear message if required secrets are missing
3. **JSON validation** - Validates `e2e_env_vars` and `e2e_secrets` JSON syntax with fail-fast

## Benefits

✅ **Better security** - Secrets aren't unnecessarily passed through input parameters  
✅ **Clearer intent** - B2C configuration is explicitly secret data  
✅ **Fail-fast validation** - Missing or malformed secrets cause immediate, clear failures  
✅ **Consistent masking** - All B2C values are masked in logs  
✅ **Simpler callers** - Can use `secrets: inherit` instead of listing everything  

## Troubleshooting

### Error: "Missing required B2C secrets for E2E tests"

The validation step failed. Ensure all four B2C secrets are configured in your repository settings:
1. Go to Settings → Secrets and variables → Actions
2. Add the missing secrets listed in the error message

### Tests fail with authentication errors

Verify your B2C secrets contain the correct values:
- `AAD_B2C_AUTHORITY` should be the full authority URL with policy name
- `B2C_SMOKE_CLIENT_ID` should match the app registration client ID
- `AAD_B2C_API_SCOPE` should be the full scope URL
- `B2C_SMOKE_CLIENT_SECRET` should be a valid, non-expired client secret

### Error: "Invalid e2e_secrets JSON syntax"

Your `e2e_secrets` or `e2e_env_vars` contains invalid JSON. Validate using:
```bash
echo '${{ secrets.E2E_SECRETS_JSON }}' | jq .
```

## Version Compatibility

- **v4.3.0+**: New secrets-based B2C configuration (use this migration guide)
- **v4.2.x and earlier**: Old input-based B2C configuration (legacy)

When upgrading to v4.3.0+, apply the changes described in this guide.
