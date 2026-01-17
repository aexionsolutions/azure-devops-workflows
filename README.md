# azure-devops-workflows

**Reusable GitHub Actions workflows for Azure-based .NET + React/Next.js applications**

[![License](https://img.shields.io/badge/license-Internal-blue.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-Active-success.svg)]()

## 🎯 Purpose

This repository provides battle-tested, reusable CI/CD workflows for Azure deployments, eliminating duplication across projects and ensuring consistency.

**Currently used by**:
- [TEMS](https://github.com/aexionsolutions/tems)
- [RavenXpress](https://github.com/aexionsolutions/ravenxpress)

---

## ⚠️ Important: Required Inputs (No Defaults)

**All repo-specific paths MUST be explicitly provided** - there are NO fallback defaults to prevent silent failures.

### Why No Defaults?
- **Fail-safe**: Missing configuration fails immediately with clear errors
- **Self-documenting**: Calling workflows explicitly show their structure
- **Multi-repo safe**: Works with any project structure (TEMS, RavenXpress, etc.)
- **No hidden behavior**: No assumptions about your repository layout

### What You Must Provide:
- ✅ `js_lcov_path` - Path to lcov.info (e.g., `web/tems-portal/coverage/lcov.info`)
- ✅ `sonar_exclusions` - Files to exclude from SonarCloud analysis
- ✅ `sonar_coverage_exclusions` - Files to exclude from coverage
- ✅ `concurrency_group` - Unique build concurrency group name
- ✅ `web_directory` / `api_project` - Project paths

---

## 🚀 Quick Start

### 1. Prerequisites

- Azure subscription with OIDC configured
- GitHub repository secrets configured
- Bicep templates for infrastructure (if using infra workflows)

### 2. Use in Your Workflow

#### Example: .NET CI with SonarCloud

```yaml
name: PR CI

on:
  pull_request:
    branches: [main, dev]

jobs:
  ci:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.0.1
    with:
      solution: Ems.sln
      web_working_directory: web/tems-portal
      run_web_unit_tests: true
      
      # Required: Explicit lcov path (no defaults!)
      js_lcov_path: web/tems-portal/coverage/lcov.info
      
      # Required: SonarCloud exclusions (customize for your repo)
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
```

#### Example: Web Deployment

```yaml
name: Build Web

on:
  push:
    tags: ['v*']

jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/web-deploy.yml@v4.0.1
    with:
      web_directory: web/tems-portal           # Required: No defaults
      concurrency_group: tems-web-build        # Required: Unique per repo
```

#### Example: API Deployment

```yaml
name: Build API

on:
  push:
    tags: ['v*']

jobs:
  build:
    uses: aexionsolutions/azure-devops-workflows/.github/workflows/api-deploy.yml@v3.2.0
    with:
      api_project: backend/src/Ems.Api/Ems.Api.csproj
      unit_test_project: tests/Ems.UnitTests/Ems.UnitTests.csproj
      concurrency_group: tems-api-build        # Required: Unique per repo
```

---

## 📚 Available Workflows

| Workflow | Purpose | Required Inputs | Status |
|----------|---------|----------------|--------|
| [dotnet-ci.yml](.github/workflows/dotnet-ci.yml) | .NET build, test, coverage, SonarCloud | `js_lcov_path`, `sonar_exclusions`, `sonar_coverage_exclusions` | ✅ Ready |
| [web-deploy.yml](.github/workflows/web-deploy.yml) | Next.js build & package | `web_directory`, `concurrency_group` | ✅ Ready |
| [api-deploy.yml](.github/workflows/api-deploy.yml) | .NET API build & package | `api_project`, `concurrency_group` | ✅ Ready |
| [azure-infra-deploy.yml](.github/workflows/azure-infra-deploy.yml) | Deploy Bicep infrastructure | `environment`, `resource_group`, `name_prefix` | ✅ Ready |
| [web-ci.yml](.github/workflows/web-ci.yml) | React/Next.js lint, test | - | ✅ Ready |

---

## 🔧 Configuration Guide

### SonarCloud Configuration

All SonarCloud paths are **required** and must match your repo structure:

#### Base Exclusions (Common for all repos)
```yaml
sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/dist/**,**/out/**,**/.github/workflows/**,**/Program.cs'
```

#### Coverage Exclusions (Customize paths!)
```yaml
# TEMS Example:
sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/*.config.{ts,js,mjs},web/tems-portal/vitest.{config,setup}.ts,web/tems-portal/tests/**'

# RavenXpress Example:
sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,rx-web/next-env.d.ts,**/*.d.ts,**/*.css,rx-web/*.config.{ts,js,mjs},rx-web/vitest.{config,setup}.ts,rx-web/tests/**'
```

#### Infrastructure Exclusions (Optional, repo-specific)
```yaml
# TEMS:
sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**'

# RavenXpress:
sonar_infra_exclusions: 'infra/ravenxpress-infra/**/*.bicep'

# None:
sonar_infra_exclusions: ''
```

### Concurrency Groups

Prevent concurrent builds by specifying unique concurrency groups:

```yaml
# TEMS:
concurrency_group: tems-web-build
concurrency_group: tems-api-build

# RavenXpress:
concurrency_group: ravenxpress-web-build
concurrency_group: ravenxpress-api-build
```

---

## 📖 Complete Input Reference

### dotnet-ci.yml

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `solution` | ✅ | Path to .sln file | `Ems.sln` |
| `web_working_directory` | ❌ | Web tests directory | `web/tems-portal` |
| `run_web_unit_tests` | ❌ | Enable web tests | `true` |
| `js_lcov_path` | ✅ | Path to lcov.info | `web/tems-portal/coverage/lcov.info` |
| `sonar_exclusions` | ✅ | File exclusions | See examples above |
| `sonar_coverage_exclusions` | ✅ | Coverage exclusions | See examples above |
| `sonar_infra_exclusions` | ❌ | Infra exclusions | `infra/**/*.bicep` |
| `pr_number` | ❌ | PR number | `${{ github.event.pull_request.number }}` |
| `pr_head` | ❌ | PR head branch | `${{ github.head_ref }}` |
| `pr_base` | ❌ | PR base branch | `${{ github.base_ref }}` |

### web-deploy.yml

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `web_directory` | ✅ | Web project path | `web/tems-portal` |
| `concurrency_group` | ✅ | Build group name | `tems-web-build` |
| `release_tag` | ❌ | Release tag | `v1.2.3` |
| `allow_override` | ❌ | Replace existing asset | `false` |

### api-deploy.yml

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `api_project` | ✅ | API csproj path | `backend/src/Ems.Api/Ems.Api.csproj` |
| `unit_test_project` | ✅ | Test project path | `tests/Ems.UnitTests/Ems.UnitTests.csproj` |
| `concurrency_group` | ✅ | Build group name | `tems-api-build` |
| `release_tag` | ❌ | Release tag | `v1.2.3` |

---

## 🔐 Required Secrets

### Repository Secrets (one-time)
```
AZURE_CLIENT_ID          # Service principal application ID
AZURE_TENANT_ID          # Azure AD tenant ID  
AZURE_SUBSCRIPTION_ID    # Azure subscription ID
SONAR_TOKEN             # SonarCloud token
SONAR_ORG               # SonarCloud organization key
SONAR_PROJECT_KEY       # SonarCloud project key
```

### Environment Secrets (per environment)
```
POSTGRES_ADMIN_PASSWORD  # PostgreSQL admin password
```

---

## 🔄 Versioning

This repository uses **fully automated versioning** based on [Conventional Commits](https://www.conventionalcommits.org/) and [Semantic Versioning](https://semver.org/).

### How It Works

1. **Create PR** → Pre-release tag automatically generated (e.g., `v4.1.0-pr.3.abc123`)
2. **Test pre-release** → Use pre-release tag in calling repos for validation
3. **Merge to main** → Stable tag automatically created (e.g., `v4.1.0`)

### 🔒 Version Immutability

When you reference a workflow at a specific tag (e.g., `@v4.1.0`), **the workflow definition is immutable**.

Because reusable workflows execute in the *calling repo's* workspace, internal composite actions from this repo are resolved via a **dual-checkout** pattern:

- The calling repo is checked out into `caller/` (this is where build/test commands run)
- This repo is checked out into `shared/` at the same `@ref` the caller pinned in `uses: ...@ref` (passed explicitly as `shared_ref`)
- Composite actions are invoked from `./shared/.github/actions/...`

This keeps the reusable workflow + its internal actions locked to the same tag/branch without needing any workflow-file rewriting.

**Important:** GitHub does not provide the `uses: ...@ref` value to the called workflow at runtime. If you pin to a tag (stable or prerelease), pass `with: shared_ref: <same ref>`.

### Version Bump Rules

Commit messages determine the version bump:

- `feat!:` or `BREAKING CHANGE:` → **Major** version bump (v3.0.0 → v4.0.0)
- `feat:` → **Minor** version bump (v3.0.0 → v3.1.0)
- `fix:`, `chore:`, `refactor:`, `perf:` → **Patch** version bump (v3.0.0 → v3.0.1)
- Other commits → **No version bump**

### Version Pinning Strategies

```yaml
# ✅ Production: Pin to stable version
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1.0

# 🧪 Testing: Use pre-release tag from PR comment
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1.0-pr.3.abc123

# ✅ Safe: Latest patch version (v4.1.x)
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1

# ✅ Moderate risk: Latest minor version (v4.x.x)
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4

# ⚠️ Not recommended for production: Always latest (may break without warning)
uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@main
```

### Testing Pre-releases

When you create a PR in this repo, a bot comment provides the pre-release tag:

```
## 📦 Pre-release Tag Created

**Tag:** `v4.1.0-pr.3.abc123`
**Next Version:** `v4.1.0`
**Bump Type:** `minor`

### 🧪 Test this pre-release in calling repos:

uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1.0-pr.3.abc123
```

Copy the tag to your calling repo's workflow to test before merging.

## 🛠️ Development

### Making Changes

1. **Create feature branch**:
   ```bash
   git checkout -b feature/my-change
   ```

2. **Make changes** using conventional commits:
   ```bash
   git commit -m "feat: add new deployment workflow"
   git commit -m "fix: resolve SonarCloud coverage issue"
   git commit -m "feat!: remove deprecated workflow_ref parameter"
   ```

3. **Create PR** → Pre-release tag auto-generated (e.g., `v4.1.0-pr.3.abc123`)

4. **Test pre-release** in calling repos:
   ```yaml
   # In TEMS/.github/workflows/pr-ci.yml
   uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1.0-pr.3.abc123
   ```

5. **Merge to main** → Stable tag auto-created (e.g., `v4.1.0`)

6. **Update calling repos** to use stable tag:
   ```yaml
   uses: aexionsolutions/azure-devops-workflows/.github/workflows/dotnet-ci.yml@v4.1.0
   ```

### Contributing

1. ✅ Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages
2. ✅ Follow existing workflow patterns and naming conventions
3. ✅ Document all inputs, secrets, and outputs
4. ✅ Add usage examples to [docs/examples/](docs/examples/)
5. ✅ Test pre-release tags in calling repos (TEMS/RavenXpress) before merging
6. ✅ Update [CHANGELOG.md](CHANGELOG.md) when releasing new versions
7. ❌ **Never manually create version tags** - automation handles this

## 📊 Adoption Status

| Project | Status | Version | Migration Date |
|---------|--------|---------|----------------|
| TEMS | 🚧 In Progress | - | January 2026 |
| RavenXpress | 📋 Planned | - | TBD |

## 🎯 Benefits

### Before (Inline Workflows)
- 🔄 Duplicate workflow code across projects
- ⚠️ Manual synchronization required
- 🐛 Bugs fixed in one place, forgotten in another
- ⏰ Time-consuming updates across multiple repos

### After (Shared Workflows)
- ✅ Single source of truth
- ✅ Update once, benefit everywhere
- ✅ No drift between projects
- ✅ Faster onboarding for new projects

## 🆘 Support

**Having issues?**
1. Check [documentation](docs/)
2. Review [examples](docs/examples/)
3. Search [existing issues](https://github.com/aexionsolutions/azure-devops-workflows/issues)
4. Open a [new issue](https://github.com/aexionsolutions/azure-devops-workflows/issues/new)

## 📝 License

Internal use only - AexionSolutions Ltd © 2026

## 🔗 Related Resources

- [GitHub Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Azure OIDC with GitHub Actions](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
