# 🚀 TEMS Quick Migration - azure-devops-workflows v3.2.0

## ⚡ Copy & Paste This Into Your PR

---

### 📝 Changes Required in `.github/workflows/pr-ci.yml`

**Update version and add 4 new required inputs:**

```yaml
jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v3.2.0  # Update version
    with:
      solution: Ems.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      
      # ⭐ NEW: Add these 4 required inputs
      js_lcov_path: web/tems-portal/coverage/lcov.info
      sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/dist/**,**/out/**,**/.github/workflows/**,**/Program.cs'
      sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/*Designer.cs,**/Migrations/**,**/bin/**,**/obj/**,**/Program.cs,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/eslint.config.mjs,web/tems-portal/postcss.config.mjs,web/tems-portal/vitest.config.ts,web/tems-portal/vitest.setup.ts,web/tems-portal/tsconfig.json,web/tems-portal/next.config.ts,web/tems-portal/next.config.mjs,web/tems-portal/playwright.config.ts,web/tems-portal/playwright.config.js,web/tems-portal/playwright.prod.config.ts,web/tems-portal/server.js,web/tems-portal/tests/**'
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

### 📝 If You Have `.github/workflows/web-deploy.yml`

**Add 1 new required input:**

```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-deploy.yml@v3.2.0  # Update version
    with:
      web_directory: web/tems-portal
      concurrency_group: tems-web-build  # ⭐ NEW: Add this
      # ... rest of your inputs
```

---

### 📝 If You Have `.github/workflows/api-deploy.yml`

**Add 1 new required input:**

```yaml
jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/api-deploy.yml@v3.2.0  # Update version
    with:
      api_project: backend/src/Ems.Api/Ems.Api.csproj
      unit_test_project: tests/Ems.UnitTests/Ems.UnitTests.csproj
      concurrency_group: tems-api-build  # ⭐ NEW: Add this
      # ... rest of your inputs
```

---

## ✅ Why These Changes?

### Before (v3.1.x):
- ❌ Hardcoded TEMS paths in shared workflows
- ❌ SonarCloud showed **0.0% coverage** (wrong path)
- ❌ Silent failures when paths didn't match
- ❌ RavenXpress couldn't use workflows

### After (v3.2.0):
- ✅ Explicit configuration (self-documenting)
- ✅ SonarCloud shows **actual coverage** ✨
- ✅ Fails fast with clear errors
- ✅ Works for any repo structure

---

## 🎯 What This Fixes

**Main Issue:** SonarCloud 0.0% coverage bug
- Shared workflow looked for: `tems-web/coverage/lcov.info`
- Actual TEMS path: `web/tems-portal/coverage/lcov.info`
- Result: File not found → 0.0% coverage reported

**Now:** You explicitly tell it where to find coverage ✅

---

## 🧪 Testing After Changes

1. **Create PR** with these changes
2. **Verify workflow runs** (doesn't fail on "missing required input")
3. **Check SonarCloud** after run:
   - Coverage > 0.0% ✅
   - `route.ts` shows actual test coverage ✅

---

## 🆘 Errors After Upgrade?

### "Missing required input: js_lcov_path"
✅ **Copy the exact inputs from above** - they're ready to paste!

### "Missing required input: concurrency_group"
✅ **Add:** `concurrency_group: tems-web-build` (or `tems-api-build`)

### Still 0.0% coverage in SonarCloud
✅ **Check:** Path matches exactly: `web/tems-portal/coverage/lcov.info`

---

## 📚 Full Details

See [TEMS-MIGRATION-GUIDE.md](https://github.com/aexionsolutions/azure-devops-workflows/blob/main/TEMS-MIGRATION-GUIDE.md)

---

## 📝 Suggested Commit Message

```
chore: migrate to azure-devops-workflows v3.2.0

- Add required js_lcov_path for SonarCloud coverage reporting
- Add required sonar_exclusions and sonar_coverage_exclusions
- Add required concurrency_group for build isolation
- Fixes SonarCloud 0.0% coverage issue

Breaking: Requires azure-devops-workflows v3.2.0+
Resolves: #<issue-number>
```

---

## 🎉 That's It!

Just copy-paste the config sections above and you're done!
