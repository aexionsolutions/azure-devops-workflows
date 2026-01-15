# TEMS Migration Guide - v3.2.0 Breaking Changes

## 🚨 Breaking Changes Summary

The shared workflows now **require explicit inputs** for all repo-specific paths - **defaults have been removed**.

### What Changed:
1. ✅ **`js_lcov_path`** - Now REQUIRED (was optional with auto-construction)
2. ✅ **`sonar_exclusions`** - Now REQUIRED (was hardcoded)
3. ✅ **`sonar_coverage_exclusions`** - Now REQUIRED (was hardcoded)
4. ✅ **`concurrency_group`** - Now REQUIRED in web-deploy.yml and api-deploy.yml
5. ✅ **All hardcoded TEMS paths removed** - Generic for any repo

### Why:
- **Fail-safe**: Missing config = immediate error (not silent failure)
- **Multi-repo compatible**: Works with TEMS, RavenXpress, any project
- **Self-documenting**: Caller workflows show exact structure
- **No hidden behavior**: Explicit is better than implicit

---

## 📋 Required Changes in TEMS Repo

### 1. Update `.github/workflows/pr-ci.yml`

**Location:** Line ~35 (in the `ci` job)

**Find:**
```yaml
jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v3.1.5
    with:
      solution: Ems.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.head_ref }}
      pr_base: ${{ github.base_ref }}
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_ORG: ${{ secrets.SONAR_ORG }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

**Replace with:**
```yaml
jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v3.2.0
    with:
      solution: Ems.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      
      # NEW: Required lcov path
      js_lcov_path: web/tems-portal/coverage/lcov.info
      
      # NEW: Required SonarCloud exclusions
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/dist/**,**/out/**,**/.github/workflows/**,**/Program.cs'
      
      # NEW: Required coverage exclusions (TEMS-specific config files)
      sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/*Designer.cs,**/Migrations/**,**/bin/**,**/obj/**,**/Program.cs,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/eslint.config.mjs,web/tems-portal/postcss.config.mjs,web/tems-portal/vitest.config.ts,web/tems-portal/vitest.setup.ts,web/tems-portal/tsconfig.json,web/tems-portal/next.config.ts,web/tems-portal/next.config.mjs,web/tems-portal/playwright.config.ts,web/tems-portal/playwright.config.js,web/tems-portal/playwright.prod.config.ts,web/tems-portal/server.js,web/tems-portal/tests/**'
      
      # NEW: Optional infrastructure exclusions
      sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**,setup-oidc.ps1'
      
      pr_number: ${{ github.event.pull_request.number }}
      pr_head: ${{ github.head_ref }}
      pr_base: ${{ github.base_ref }}
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_ORG: ${{ secrets.SONAR_ORG }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

---

### 2. Update `.github/workflows/web-deploy.yml` (if exists)

**Find:**
```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-deploy.yml@v3.1.5
    with:
      web_directory: web/tems-portal
      # ... other inputs
```

**Replace with:**
```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-deploy.yml@v3.2.0
    with:
      web_directory: web/tems-portal
      concurrency_group: tems-web-build  # NEW: Required
      # ... other inputs
```

---

### 3. Update `.github/workflows/api-deploy.yml` (if exists)

**Find:**
```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/api-deploy.yml@v3.1.5
    with:
      api_project: backend/src/Ems.Api/Ems.Api.csproj
      unit_test_project: tests/Ems.UnitTests/Ems.UnitTests.csproj
      # ... other inputs
```

**Replace with:**
```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/api-deploy.yml@v3.2.0
    with:
      api_project: backend/src/Ems.Api/Ems.Api.csproj
      unit_test_project: tests/Ems.UnitTests/Ems.UnitTests.csproj
      concurrency_group: tems-api-build  # NEW: Required
      # ... other inputs
```

---

## ✅ What Stays the Same

- Infrastructure deployment workflows (no changes)
- Secret configuration (no changes)
- Azure OIDC setup (no changes)
- All other inputs remain backward compatible

---

## 🔍 Verification Steps

After applying changes:

1. **Create a test PR** in TEMS repo
2. **Check workflow starts** (not fails immediately with "missing required input")
3. **Monitor logs** for:
   ```
   ✅ lcov.info found at web/tems-portal/coverage/lcov.info
   Size: 15K
   Found OpenCover files: 2
   ```
4. **Check SonarCloud** after PR completes:
   - Coverage > 0.0%
   - `route.ts` shows actual coverage
5. **Verify quality gate** passes/fails based on real data

---

## 🐛 Troubleshooting

### Error: "Missing required input 'js_lcov_path'"
**Fix:** Add to caller workflow:
```yaml
js_lcov_path: web/tems-portal/coverage/lcov.info
```

### Error: "Missing required input 'sonar_exclusions'"
**Fix:** Copy the complete exclusion patterns from this guide

### SonarCloud still shows 0.0% coverage
**Verify:**
1. `js_lcov_path` matches actual file location
2. Web tests ran successfully (check workflow logs)
3. Coverage report was generated: `ls -la web/tems-portal/coverage/`

---

## 📊 Impact Analysis

| File | Changes | Breaking? | Action Required |
|------|---------|-----------|-----------------|
| `.github/workflows/pr-ci.yml` | Add 4 new inputs | ✅ Yes | Update required |
| `.github/workflows/web-deploy.yml` | Add 1 new input | ✅ Yes | Update required |
| `.github/workflows/api-deploy.yml` | Add 1 new input | ✅ Yes | Update required |
| Infrastructure workflows | None | ❌ No | No action |

---

## 🎯 Benefits After Migration

### Before (v3.1.5):
- ❌ Hardcoded TEMS paths in shared workflows
- ❌ Silent failures when paths wrong
- ❌ RavenXpress couldn't use shared workflows
- ❌ SonarCloud showed 0.0% coverage due to hardcoded path

### After (v3.2.0):
- ✅ Explicit configuration per repo
- ✅ Fails fast with clear errors
- ✅ Works for TEMS, RavenXpress, any repo
- ✅ SonarCloud gets correct coverage data
- ✅ Self-documenting caller workflows

---

## 📅 Timeline

- **v3.2.0 Release:** January 15, 2026
- **TEMS Migration:** Immediate (required for next PR)
- **RavenXpress Migration:** When adopting shared workflows

---

## 🆘 Need Help?

- **Review:** [Complete README](README.md#-configuration-guide)
- **Check:** Workflow logs for specific errors
- **Example:** [docs/examples/tems-pr-ci-complete.yml](docs/examples/)
- **Questions:** Open issue in azure-devops-workflows repo

---

## 📝 Commit Message Template

```
chore: migrate to azure-devops-workflows v3.2.0

- Add required js_lcov_path for SonarCloud coverage
- Add required sonar_exclusions and sonar_coverage_exclusions
- Add required concurrency_group for web/api builds
- Fixes SonarCloud 0.0% coverage issue

Breaking: Requires azure-devops-workflows v3.2.0+
```
