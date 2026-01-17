# TEMS Action Items - Update to azure-devops-workflows@v4.0.1

## 🎯 What TEMS Needs to Do

### 1. Update `pr-ci.yml` - Change version from @v3.1.5 to @v4.0.1

**File:** `.github/workflows/pr-ci.yml`

**Current (Wrong):**
```yaml
jobs:
  api-ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v3.1.5
    # or @v4.0.0 (also broken)
```

**Fix:**
```yaml
jobs:
  api-ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.0.1
    with:
      # Your existing inputs are correct, just update the version above
      solution: TEMS.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      run_integration: true
      sonar_enabled: true
      enforce_coverage: true
      coverage_threshold: 80
      coverage_assembly_filters: '-Ems.Infrastructure'
      
      js_lcov_path: web/tems-portal/coverage/lcov.info
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/.github/workflows/**,**/Program.cs,backend/Ems.Api/Extensions/**,web/tems-portal/src/app/signin/**'
      sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,backend/Ems.Api/Extensions/**,web/tems-portal/src/app/signin/**,**/*.d.ts,**/*.css,**/*.config.ts,**/*.config.mjs,**/*.config.js,web/tems-portal/tests/**'
      
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.head_ref }}
      pr_base: ${{ github.base_ref }}
```

### 2. Remove the `web-ci` job (it doesn't exist)

**Current (Wrong):**
```yaml
  web-ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-ci.yml@v4.0.2-pr-3.fc2wd2  # ❌ This workflow doesn't exist!
```

**Fix:**
Just remove the entire `web-ci` job. The `api-ci` job (dotnet-ci.yml) already runs web unit tests when you set `run_web_unit_tests: true`.

---

## 📝 Complete Example

Here's what your TEMS `pr-ci.yml` should look like:

```yaml
name: PR CI (Build, Test, Coverage)

on:
  pull_request:
    branches: [ main ]

jobs:
  api-ci:
    name: CI (API + Web Unit Tests)
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.0.1
    secrets: inherit
    with:
      solution: TEMS.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true  # ✅ This already runs Vitest
      run_integration: true
      sonar_enabled: true
      enforce_coverage: true
      coverage_threshold: 80
      coverage_assembly_filters: '-Ems.Infrastructure'
      
      # Required lcov path for SonarCloud JavaScript coverage
      js_lcov_path: web/tems-portal/coverage/lcov.info
      
      # Required SonarCloud exclusions
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/dist/**,**/out/**,**/.github/workflows/**,**/tools/**,**/Program.cs,backend/Ems.Api/Extensions/**,web/tems-portal/src/app/signin/**'
      
      # Required coverage exclusions
      sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/*Designer.cs,**/Migrations/**,**/bin/**,**/obj/**,**/Program.cs,backend/Ems.Api/Extensions/**,web/tems-portal/src/app/signin/**,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/eslint.config.mjs,web/tems-portal/postcss.config.mjs,web/tems-portal/vitest.config.ts,web/tems-portal/vitest.setup.ts,web/tems-portal/tsconfig.json,web/tems-portal/next.config.ts,web/tems-portal/next.config.mjs,web/tems-portal/playwright.config.ts,web/tems-portal/playwright.config.js,web/tems-portal/playwright.prod.config.ts,web/tems-portal/playwright.smoke.config.ts,web/tems-portal/server.js,web/tems-portal/tests/**'
      
      # Optional infrastructure exclusions
      sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**,setup-oidc.ps1'
      
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.head_ref }}
      pr_base: ${{ github.base_ref }}
```

---

## 🔍 Why This Fixes the Issues

### Problem #1: 0.0% Coverage
**Root Cause:** TEMS was using `@v4.0.0` workflow which called `@v3.1.5` actions that didn't support the new exclusion parameters.

**Solution:** `@v4.0.1` ensures workflow version matches action versions.

### Problem #2: Exclusions Not Working
**Root Cause:** The v3.1.5 actions didn't have `sonar_exclusions` or `sonar_coverage_exclusions` parameters.

**Solution:** v4.0.1 actions have these parameters and properly pass them to SonarCloud.

### Problem #3: web-ci.yml Not Found
**Root Cause:** That workflow was never created in azure-devops-workflows.

**Solution:** Use `dotnet-ci.yml` with `run_web_unit_tests: true` - it already handles both .NET and web tests.

---

## ✅ After Making Changes

1. **Commit the change** to TEMS pr-ci.yml
2. **Create a PR** in TEMS
3. **Watch the workflow run** - you should see:
   - ✅ Workflow completes successfully
   - ✅ SonarCloud shows actual coverage % (not 0.0%)
   - ✅ Exclusion patterns appear in logs
   - ✅ `backend/Ems.Api/Extensions/**` and `web/tems-portal/src/app/signin/**` excluded from coverage

---

## 🆘 If Issues Persist

Check the workflow logs for:
```
Using workflow version: v4.0.1
```

And in SonarCloud scanner output:
```
Excluded sources: **/bin/**, **/obj/**, ..., backend/Ems.Api/Extensions/**
Excluded sources for coverage: **/*.g.cs, ..., backend/Ems.Api/Extensions/**, web/tems-portal/src/app/signin/**
```

If you still see v3.1.5 or missing exclusions, double-check the version in your pr-ci.yml file.
