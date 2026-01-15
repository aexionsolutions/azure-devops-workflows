# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 🚨 Breaking Changes

#### All Repo-Specific Paths Now Required (No Defaults)

**Philosophy Change:** Explicit configuration over implicit defaults for fail-safe multi-repo compatibility.

##### dotnet-ci.yml
- **BREAKING:** `js_lcov_path` now **required** (was optional with auto-construction)
  - Before: Auto-constructed from `web_working_directory` (could fail silently)
  - After: Must explicitly provide path (e.g., `web/tems-portal/coverage/lcov.info`)
  - Reason: Prevents silent failures when path wrong, works for any repo structure
  
- **BREAKING:** `sonar_exclusions` now **required** (was hardcoded with TEMS paths)
  - Before: Hardcoded `infra/tems-infra/azure/modules/**/*.bicep` etc.
  - After: Caller must provide comma-separated exclusion patterns
  - Reason: Generic for any repo (TEMS, RavenXpress, etc.)
  
- **BREAKING:** `sonar_coverage_exclusions` now **required** (was hardcoded with TEMS paths)
  - Before: Hardcoded `web/tems-portal/vitest.config.ts`, `web/tems-portal/tests/**` etc.
  - After: Caller must provide patterns matching their structure
  - Reason: Different repos have different config file locations
  
- **ADDED:** `sonar_infra_exclusions` - Optional infrastructure-specific exclusions
  - Use for repo-specific infra paths (e.g., `infra/tems-infra/**/*.bicep`)

##### web-deploy.yml
- **BREAKING:** `concurrency_group` now **required** (was hardcoded as `tems-web-build`)
  - Before: All repos used same group (could block each other)
  - After: Must provide unique group name per repo (e.g., `tems-web-build`, `ravenxpress-web-build`)
  - Reason: Prevents cross-repo concurrency conflicts
  
- **BREAKING:** Removed all `web_directory || 'web/tems-portal'` fallbacks
  - Before: Defaulted to TEMS structure if not provided
  - After: Fails fast if `web_directory` not provided
  - Reason: Explicit is better than implicit

##### api-deploy.yml
- **BREAKING:** `concurrency_group` now **required** (was hardcoded as `tems-api-build`)
  - Before: Hardcoded TEMS-specific group name
  - After: Must provide unique group name per repo
  - Reason: Multi-repo compatibility

##### sonar-dotnet-begin action
- **BREAKING:** All inputs now required (removed defaults)
  - `js_lcov`: Must provide explicit path
  - `sonar_exclusions`: Must provide explicit patterns
  - `sonar_coverage_exclusions`: Must provide explicit patterns
- **ADDED:** Dynamic exclusion building with optional infra paths
- **REMOVED:** All TEMS-specific hardcoded paths from line 73-74

### Fixed
- SonarCloud 0.0% coverage issue (hardcoded `tems-web/coverage/lcov.info` didn't match actual path)
- Multi-repo compatibility issues (RavenXpress couldn't use shared workflows)
- Silent path failures (now fail fast with clear errors)

### Added
- [TEMS-MIGRATION-GUIDE.md](TEMS-MIGRATION-GUIDE.md) - Complete migration instructions
- Comprehensive README with configuration examples for different repos
- Self-documenting caller workflows (explicit inputs show repo structure)

### Migration Required
**All calling repos (TEMS, RavenXpress) MUST update workflows before upgrading to v3.2.0**

See [TEMS-MIGRATION-GUIDE.md](TEMS-MIGRATION-GUIDE.md) for complete instructions.

**Quick Summary for TEMS:**
```yaml
# Add these required inputs to pr-ci.yml:
js_lcov_path: web/tems-portal/coverage/lcov.info
sonar_exclusions: '**/bin/**,**/obj/**,**/node_modules/**,**/.next/**,**/coverage/**,**/.github/workflows/**,**/Program.cs'
sonar_coverage_exclusions: '**/*.g.cs,**/*.generated.cs,**/Migrations/**,web/tems-portal/next-env.d.ts,**/*.d.ts,**/*.css,web/tems-portal/*.config.{ts,js,mjs},web/tems-portal/vitest.{config,setup}.ts,web/tems-portal/tests/**'
sonar_infra_exclusions: 'infra/tems-infra/azure/modules/**/*.bicep,docs/tools/**,setup-oidc.ps1'

# Add to web-deploy.yml:
concurrency_group: tems-web-build

# Add to api-deploy.yml:
concurrency_group: tems-api-build
```

---

## [1.0.0] - 2026-01-10

### Added

#### Workflows
- **azure-infra-deploy.yml**: Azure infrastructure deployment using Bicep
  - OIDC authentication with Azure
  - Automatic PostgreSQL server management (start/stop/wait)
  - Key Vault RBAC auto-configuration
  - Resource provider registration (PostgreSQL, Application Insights)
  - Secret validation before deployment
  - Comprehensive error reporting
  
- **dotnet-ci.yml**: .NET CI with testing and quality gates
  - Build and test .NET solutions
  - Code coverage with threshold enforcement
  - Integration test support (PostgreSQL + Azurite services)
  - Playwright E2E test support
  - SonarCloud integration with PR decoration
  - Artifact uploads (coverage reports, test results)
  
- **web-ci.yml**: Web CI for React/Next.js applications
  - Lint, test, and build workflows
  - npm and pnpm support
  - Playwright browser automation
  - Build artifact uploads

#### Documentation
- Complete usage guide with examples
- Parameters reference for all workflows
- Migration guide from inline workflows
- Azure OIDC setup instructions
- Real-world examples from TEMS project

#### Scripts
- `setup-repository.ps1`: Automated repository initialization and publishing
- `setup-azure-federated-credentials.ps1`: Azure OIDC credential setup

### Features

- 🔐 OIDC authentication (no long-lived secrets)
- 🚀 Reusable across multiple projects
- 📦 Versioned releases for stability
- 📚 Comprehensive documentation
- ✅ Production-tested with TEMS project

### Breaking Changes

None (initial release)

---

## Release Notes Template

Use this template for future releases:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features or workflows

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security improvements
```
