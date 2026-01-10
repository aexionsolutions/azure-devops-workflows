# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
